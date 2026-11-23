-- 004_poll_notifications_and_session_generator.sql
-- ClassCue — Poll-created notifications, expired-poll cleanup, and idempotent session generator (v1.1)

-- ============================================================================
-- 1. Notify affected Students (strict B1/B2), CRs and Faculty when a poll opens
-- ============================================================================
CREATE OR REPLACE FUNCTION public.handle_reschedule_poll_created()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.lecture_sessions%ROWTYPE;
  v_course_code TEXT;
  v_course_name TEXT;
  v_title TEXT;
  v_body TEXT;
BEGIN
  SELECT * INTO v_session
  FROM public.lecture_sessions
  WHERE id = NEW.lecture_session_id;

  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  SELECT code, name INTO v_course_code, v_course_name
  FROM public.courses
  WHERE id = v_session.course_id;

  v_title := v_course_code || ' — Vote on Replacement Slot';
  v_body := 'A reschedule poll is open for ' || v_course_name
    || CASE WHEN v_session.batch <> 'ALL' THEN ' (' || v_session.batch || ')' ELSE '' END
    || ' on ' || to_char(v_session.session_date, 'Dy DD Mon')
    || ' at ' || to_char(v_session.start_time, 'HH24:MI')
    || '. Voting closes ' || to_char(NEW.closes_at AT TIME ZONE 'Asia/Kolkata', 'DD Mon HH24:MI') || ' IST.';

  -- CRs of the course's cohort(s) and Students (strict B1/B2 batch match); skip the poll creator
  INSERT INTO public.notifications (user_id, lecture_session_id, title, body, type)
  SELECT DISTINCT p.id, NEW.lecture_session_id, v_title, v_body, 'poll'
  FROM public.profiles p
  JOIN public.course_cohorts cc ON cc.cohort_id = p.cohort_id
  WHERE cc.course_id = v_session.course_id
    AND p.id <> NEW.created_by
    AND (
      p.role = 'cr'
      OR (
        p.role = 'student'
        AND (v_session.batch = 'ALL' OR p.lab_batch = v_session.batch)
      )
    );

  -- Assigned / covering Faculty (skip if they opened the poll themselves)
  INSERT INTO public.notifications (user_id, lecture_session_id, title, body, type)
  SELECT DISTINCT p.id, NEW.lecture_session_id, v_title, v_body, 'poll'
  FROM public.profiles p
  WHERE p.id IN (v_session.faculty_id, v_session.covering_faculty_id)
    AND p.id <> NEW.created_by;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.handle_reschedule_poll_created() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_02_reschedule_poll_notify ON public.reschedule_polls;
CREATE TRIGGER trg_02_reschedule_poll_notify
AFTER INSERT ON public.reschedule_polls
FOR EACH ROW EXECUTE FUNCTION public.handle_reschedule_poll_created();

-- ============================================================================
-- 2. Expired polls must not block a new poll
--    uq_one_open_poll_per_session allows one status='open' poll per session, and nothing
--    ever moved an unconfirmed poll out of 'open', so one lapsed poll blocked the session forever.
-- ============================================================================

-- 2A. Opening a new poll retires that session's already-expired open poll first.
--     Fires before trg_prepare_reschedule_poll (alphabetical: '0' sorts before 'p').
CREATE OR REPLACE FUNCTION public.retire_expired_polls_before_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.reschedule_polls
  SET status = 'cancelled_fallback'
  WHERE lecture_session_id = NEW.lecture_session_id
    AND status = 'open'
    AND closes_at <= NOW();
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.retire_expired_polls_before_insert() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_01_retire_expired_polls ON public.reschedule_polls;
CREATE TRIGGER trg_01_retire_expired_polls
BEFORE INSERT ON public.reschedule_polls
FOR EACH ROW EXECUTE FUNCTION public.retire_expired_polls_before_insert();

-- 2B. Housekeeping: close polls that passed the 48-hour confirmation window of confirm_poll_option().
--     Run from the SQL Editor / a scheduled job (auth.uid() IS NULL) or as an admin.
CREATE OR REPLACE FUNCTION public.expire_stale_polls()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INT;
BEGIN
  IF auth.uid() IS NOT NULL AND public.current_user_role() IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'Only admins can expire stale polls.';
  END IF;

  UPDATE public.reschedule_polls
  SET status = 'cancelled_fallback'
  WHERE status = 'open'
    AND closes_at < NOW() - INTERVAL '48 hours';

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.expire_stale_polls() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.expire_stale_polls() TO authenticated;

-- ============================================================================
-- 3. Idempotent Session Generator RPC (Admin, or SQL Editor / seed with no JWT)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.generate_lecture_sessions(
  p_start_date DATE,
  p_end_date DATE
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inserted INT := 0;
BEGIN
  IF auth.uid() IS NOT NULL AND public.current_user_role() IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'Only admins can generate lecture sessions from the base timetable.';
  END IF;

  IF p_start_date IS NULL OR p_end_date IS NULL OR p_end_date < p_start_date THEN
    RAISE EXCEPTION 'Valid start_date and end_date (end_date >= start_date) are required.';
  END IF;

  IF (p_end_date - p_start_date) > 90 THEN
    RAISE EXCEPTION 'Cannot generate more than 90 days of sessions in a single call.';
  END IF;

  -- Same lock, same order as every other write path
  PERFORM pg_advisory_xact_lock(704000, 1);

  INSERT INTO public.lecture_sessions (
    base_timetable_id, course_id, faculty_id, room_id,
    session_date, start_time, end_time, batch
  )
  SELECT
    bt.id, bt.course_id, bt.faculty_id, bt.room_id,
    d.session_date, bt.start_time, bt.end_time, bt.batch
  FROM generate_series(p_start_date::timestamp, p_end_date::timestamp, INTERVAL '1 day') AS gs(dt)
  CROSS JOIN LATERAL (SELECT gs.dt::date AS session_date) AS d
  JOIN public.base_timetable bt
    ON bt.day_of_week = EXTRACT(ISODOW FROM d.session_date)::INT
   AND bt.effective_from <= d.session_date
   AND (bt.effective_to IS NULL OR bt.effective_to >= d.session_date)
  WHERE NOT EXISTS (
    -- skips dates already generated, cancelled, or moved away from (original_date)
    SELECT 1
    FROM public.lecture_sessions ls
    WHERE ls.base_timetable_id = bt.id
      AND (ls.session_date = d.session_date OR ls.original_date = d.session_date)
  )
  ORDER BY d.session_date, bt.start_time;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  RETURN v_inserted;
END;
$$;

REVOKE ALL ON FUNCTION public.generate_lecture_sessions(DATE, DATE) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.generate_lecture_sessions(DATE, DATE) TO authenticated;