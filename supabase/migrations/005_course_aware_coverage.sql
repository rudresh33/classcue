-- 005_course_aware_coverage.sql  (v1.1)
-- ClassCue — Course-Aware Lecture Coverage (Replacement faculty teaches their own assigned course)
-- v1.1 changes vs v1.0: legacy-row backfill, original cancellation reason kept, withdraw_coverage() RPC,
--   covering faculty can no longer reinstate the original lecture, check_slot_conflicts() uses the effective course.

-- ============================================================================
-- 1. SCHEMA: Add covering_course_id + pair/status integrity constraints
-- ============================================================================
ALTER TABLE public.lecture_sessions
  ADD COLUMN IF NOT EXISTS covering_course_id UUID REFERENCES public.courses(id);

-- Backfill for any 'covered' rows created by the old single-argument opt_in_coverage():
--   pick a course the covering faculty actually teaches that shares a cohort with the cancelled course;
--   if none exists, put the slot back to cancelled + open so another faculty can take it.
UPDATE public.lecture_sessions ls
SET covering_course_id = (
  SELECT cf.course_id
  FROM public.course_faculty cf
  JOIN public.course_cohorts a ON a.course_id = cf.course_id
  JOIN public.course_cohorts b ON b.cohort_id = a.cohort_id
  WHERE cf.faculty_id = ls.covering_faculty_id
    AND b.course_id = ls.course_id
  ORDER BY cf.is_primary DESC, cf.course_id
  LIMIT 1
)
WHERE ls.status = 'covered' AND ls.covering_course_id IS NULL;

UPDATE public.lecture_sessions
SET status = 'cancelled',
    is_open_for_coverage = TRUE,
    covering_faculty_id = NULL
WHERE status = 'covered' AND covering_course_id IS NULL;

UPDATE public.lecture_sessions
SET covering_faculty_id = NULL,
    covering_course_id = NULL
WHERE status <> 'covered'
  AND (covering_faculty_id IS NOT NULL OR covering_course_id IS NOT NULL);

ALTER TABLE public.lecture_sessions
  DROP CONSTRAINT IF EXISTS chk_covered_requires_covering_course;
ALTER TABLE public.lecture_sessions
  ADD CONSTRAINT chk_covered_requires_covering_course CHECK (
    (status = 'covered' AND covering_faculty_id IS NOT NULL AND covering_course_id IS NOT NULL)
    OR (status <> 'covered' AND covering_faculty_id IS NULL AND covering_course_id IS NULL)
  );

CREATE INDEX IF NOT EXISTS idx_sessions_covering_course
  ON public.lecture_sessions (covering_course_id)
  WHERE covering_course_id IS NOT NULL;

-- ============================================================================
-- 2. COHORT-ELIGIBLE COVERAGE HELPER & SCOPED RLS UPDATE
-- ============================================================================
CREATE OR REPLACE FUNCTION public.can_faculty_cover_session(
  p_session_course_id UUID,
  p_faculty_id UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.course_cohorts cc_open
    JOIN public.course_cohorts cc_mine ON cc_mine.cohort_id = cc_open.cohort_id
    JOIN public.course_faculty cf ON cf.course_id = cc_mine.course_id
    WHERE cc_open.course_id = p_session_course_id
      AND cf.faculty_id = p_faculty_id
  );
$$;

REVOKE ALL ON FUNCTION public.can_faculty_cover_session(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_faculty_cover_session(UUID, UUID) TO authenticated;

DROP POLICY IF EXISTS "read_sessions_scoped" ON public.lecture_sessions;
CREATE POLICY "read_sessions_scoped" ON public.lecture_sessions
FOR SELECT TO authenticated
USING (
  public.current_user_role() = 'admin'
  OR (
    public.current_user_role() = 'faculty'
    AND (
      faculty_id = auth.uid()
      OR covering_faculty_id = auth.uid()
      OR (
        is_open_for_coverage IS TRUE
        AND public.can_faculty_cover_session(lecture_sessions.course_id, auth.uid())
      )
    )
  )
  OR (
    public.current_user_role() = 'cr'
    AND EXISTS (
      SELECT 1 FROM public.course_cohorts cc
      WHERE cc.course_id IN (
        lecture_sessions.course_id,
        COALESCE(lecture_sessions.covering_course_id, lecture_sessions.course_id)
      )
        AND cc.cohort_id = public.current_user_cohort_id()
    )
  )
  OR (
    public.current_user_role() = 'student'
    AND (
      lecture_sessions.batch = 'ALL'
      OR lecture_sessions.batch = public.current_user_lab_batch()
    )
    AND EXISTS (
      SELECT 1 FROM public.course_cohorts cc
      WHERE cc.course_id IN (
        lecture_sessions.course_id,
        COALESCE(lecture_sessions.covering_course_id, lecture_sessions.course_id)
      )
        AND cc.cohort_id = public.current_user_cohort_id()
    )
  )
);

-- ============================================================================
-- 3. UPDATE TRIGGERS & DIFF HELPER TO TRACK covering_course_id
-- ============================================================================
CREATE OR REPLACE FUNCTION public.enforce_faculty_role()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.faculty_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.profiles WHERE id = NEW.faculty_id AND role = 'faculty'
  ) THEN
    RAISE EXCEPTION 'Referenced faculty_id % in % must have role = faculty.', NEW.faculty_id, TG_TABLE_NAME;
  END IF;

  IF TG_TABLE_NAME = 'lecture_sessions' THEN
    IF NEW.covering_faculty_id IS NOT NULL THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.profiles WHERE id = NEW.covering_faculty_id AND role = 'faculty'
      ) THEN
        RAISE EXCEPTION 'Referenced covering_faculty_id % must have role = faculty.', NEW.covering_faculty_id;
      END IF;

      IF NEW.covering_course_id IS NOT NULL
         AND NOT public.is_faculty_assigned_to_course(NEW.covering_course_id, NEW.covering_faculty_id) THEN
        RAISE EXCEPTION 'Covering faculty % is not assigned to covering_course_id %.',
          NEW.covering_faculty_id, NEW.covering_course_id;
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.enforce_faculty_role() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_01_lecture_sessions_faculty_role ON public.lecture_sessions;
CREATE TRIGGER trg_01_lecture_sessions_faculty_role
BEFORE INSERT OR UPDATE OF faculty_id, covering_faculty_id, covering_course_id ON public.lecture_sessions
FOR EACH ROW EXECUTE FUNCTION public.enforce_faculty_role();

CREATE OR REPLACE FUNCTION public.lecture_session_row_changed(
  p_old public.lecture_sessions,
  p_new public.lecture_sessions
)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT
    p_old.base_timetable_id IS DISTINCT FROM p_new.base_timetable_id
    OR p_old.status IS DISTINCT FROM p_new.status
    OR p_old.session_date IS DISTINCT FROM p_new.session_date
    OR p_old.start_time IS DISTINCT FROM p_new.start_time
    OR p_old.end_time IS DISTINCT FROM p_new.end_time
    OR p_old.room_id IS DISTINCT FROM p_new.room_id
    OR p_old.batch IS DISTINCT FROM p_new.batch
    OR p_old.faculty_id IS DISTINCT FROM p_new.faculty_id
    OR p_old.covering_faculty_id IS DISTINCT FROM p_new.covering_faculty_id
    OR p_old.covering_course_id IS DISTINCT FROM p_new.covering_course_id
    OR p_old.course_id IS DISTINCT FROM p_new.course_id
    OR p_old.change_scope IS DISTINCT FROM p_new.change_scope
    OR p_old.reason IS DISTINCT FROM p_new.reason
    OR p_old.is_open_for_coverage IS DISTINCT FROM p_new.is_open_for_coverage
    OR p_old.original_date IS DISTINCT FROM p_new.original_date
    OR p_old.original_start_time IS DISTINCT FROM p_new.original_start_time
    OR p_old.original_end_time IS DISTINCT FROM p_new.original_end_time
    OR p_old.original_room_id IS DISTINCT FROM p_new.original_room_id;
$$;

REVOKE ALL ON FUNCTION public.lecture_session_row_changed(public.lecture_sessions, public.lecture_sessions) FROM PUBLIC, anon, authenticated;

-- ============================================================================
-- 4. UPDATE OVERLAP TRIGGERS TO USE EFFECTIVE COURSE COALESCE(covering_course_id, course_id)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.enforce_base_timetable_no_overlap()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_updating_session_id UUID := NULLIF(current_setting('classcue.updating_session_id', true), '')::UUID;
  v_shifting_ids UUID[];
  v_shifting_raw TEXT := NULLIF(current_setting('classcue.shifting_session_ids', true), '');
BEGIN
  PERFORM pg_advisory_xact_lock(704000, 1);

  IF v_shifting_raw IS NOT NULL THEN
    v_shifting_ids := string_to_array(v_shifting_raw, ',')::UUID[];
  ELSE
    v_shifting_ids := ARRAY[]::UUID[];
  END IF;

  -- A. Recurring base_timetable overlaps
  IF EXISTS (
    SELECT 1 FROM public.base_timetable bt
    WHERE bt.id IS DISTINCT FROM NEW.id
      AND bt.faculty_id = NEW.faculty_id
      AND bt.day_of_week = NEW.day_of_week
      AND bt.start_time < NEW.end_time
      AND bt.end_time > NEW.start_time
      AND daterange(bt.effective_from, COALESCE(bt.effective_to, 'infinity'::DATE), '[]')
          && daterange(NEW.effective_from, COALESCE(NEW.effective_to, 'infinity'::DATE), '[]')
  ) THEN
    RAISE EXCEPTION 'Base timetable conflict: faculty already has an overlapping recurring lecture.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.base_timetable bt
    WHERE bt.id IS DISTINCT FROM NEW.id
      AND bt.room_id = NEW.room_id
      AND bt.day_of_week = NEW.day_of_week
      AND bt.start_time < NEW.end_time
      AND bt.end_time > NEW.start_time
      AND daterange(bt.effective_from, COALESCE(bt.effective_to, 'infinity'::DATE), '[]')
          && daterange(NEW.effective_from, COALESCE(NEW.effective_to, 'infinity'::DATE), '[]')
  ) THEN
    RAISE EXCEPTION 'Base timetable conflict: room is already booked for an overlapping recurring lecture.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.base_timetable bt
    JOIN public.course_cohorts cc_existing ON cc_existing.course_id = bt.course_id
    JOIN public.course_cohorts cc_target ON cc_target.cohort_id = cc_existing.cohort_id
    WHERE cc_target.course_id = NEW.course_id
      AND bt.id IS DISTINCT FROM NEW.id
      AND bt.day_of_week = NEW.day_of_week
      AND bt.start_time < NEW.end_time
      AND bt.end_time > NEW.start_time
      AND (bt.batch = 'ALL' OR NEW.batch = 'ALL' OR bt.batch = NEW.batch)
      AND daterange(bt.effective_from, COALESCE(bt.effective_to, 'infinity'::DATE), '[]')
          && daterange(NEW.effective_from, COALESCE(NEW.effective_to, 'infinity'::DATE), '[]')
  ) THEN
    RAISE EXCEPTION 'Base timetable conflict: cohort/batch already has an overlapping recurring lecture.';
  END IF;

  -- B. Symmetric check against active dated sessions (uses effective faculty & effective course)
  IF EXISTS (
    SELECT 1 FROM public.lecture_sessions ls
    WHERE ls.status IN ('scheduled', 'rescheduled', 'covered')
      AND ls.base_timetable_id IS DISTINCT FROM NEW.id
      AND (v_updating_session_id IS NULL OR ls.id <> v_updating_session_id)
      AND NOT (ls.id = ANY(v_shifting_ids))
      AND EXTRACT(ISODOW FROM ls.session_date)::INT = NEW.day_of_week
      AND ls.session_date >= NEW.effective_from
      AND (NEW.effective_to IS NULL OR ls.session_date <= NEW.effective_to)
      AND COALESCE(ls.covering_faculty_id, ls.faculty_id) = NEW.faculty_id
      AND ls.start_time < NEW.end_time
      AND ls.end_time > NEW.start_time
  ) THEN
    RAISE EXCEPTION 'Base timetable conflict: faculty already has an overlapping dated lecture session in this range.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.lecture_sessions ls
    WHERE ls.status IN ('scheduled', 'rescheduled', 'covered')
      AND ls.base_timetable_id IS DISTINCT FROM NEW.id
      AND (v_updating_session_id IS NULL OR ls.id <> v_updating_session_id)
      AND NOT (ls.id = ANY(v_shifting_ids))
      AND EXTRACT(ISODOW FROM ls.session_date)::INT = NEW.day_of_week
      AND ls.session_date >= NEW.effective_from
      AND (NEW.effective_to IS NULL OR ls.session_date <= NEW.effective_to)
      AND ls.room_id = NEW.room_id
      AND ls.start_time < NEW.end_time
      AND ls.end_time > NEW.start_time
  ) THEN
    RAISE EXCEPTION 'Base timetable conflict: room is already occupied by a dated lecture session in this range.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.lecture_sessions ls
    JOIN public.course_cohorts cc_existing ON cc_existing.course_id = COALESCE(ls.covering_course_id, ls.course_id)
    JOIN public.course_cohorts cc_target ON cc_target.cohort_id = cc_existing.cohort_id
    WHERE cc_target.course_id = NEW.course_id
      AND ls.status IN ('scheduled', 'rescheduled', 'covered')
      AND ls.base_timetable_id IS DISTINCT FROM NEW.id
      AND (v_updating_session_id IS NULL OR ls.id <> v_updating_session_id)
      AND NOT (ls.id = ANY(v_shifting_ids))
      AND EXTRACT(ISODOW FROM ls.session_date)::INT = NEW.day_of_week
      AND ls.session_date >= NEW.effective_from
      AND (NEW.effective_to IS NULL OR ls.session_date <= NEW.effective_to)
      AND ls.start_time < NEW.end_time
      AND ls.end_time > NEW.start_time
      AND (ls.batch = 'ALL' OR NEW.batch = 'ALL' OR ls.batch = NEW.batch)
  ) THEN
    RAISE EXCEPTION 'Base timetable conflict: cohort/batch already has an overlapping dated lecture session in this range.';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.enforce_base_timetable_no_overlap() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.enforce_lecture_session_no_overlap()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_dow INT;
  v_effective_faculty UUID;
  v_effective_course UUID;
  v_deleting_bt_id UUID := NULLIF(current_setting('classcue.deleting_bt_id', true), '')::UUID;
BEGIN
  IF NEW.status NOT IN ('scheduled', 'rescheduled', 'covered') THEN
    RETURN NEW;
  END IF;

  PERFORM pg_advisory_xact_lock(704000, 1);

  v_dow := EXTRACT(ISODOW FROM NEW.session_date)::INT;
  v_effective_faculty := COALESCE(NEW.covering_faculty_id, NEW.faculty_id);
  v_effective_course := COALESCE(NEW.covering_course_id, NEW.course_id);

  -- 1. Effective faculty overlap
  IF EXISTS (
    SELECT 1 FROM public.lecture_sessions ls
    WHERE ls.id IS DISTINCT FROM NEW.id
      AND ls.session_date = NEW.session_date
      AND ls.status IN ('scheduled', 'rescheduled', 'covered')
      AND COALESCE(ls.covering_faculty_id, ls.faculty_id) = v_effective_faculty
      AND ls.start_time < NEW.end_time
      AND ls.end_time > NEW.start_time
  ) OR EXISTS (
    SELECT 1 FROM public.base_timetable bt
    WHERE (NEW.base_timetable_id IS NULL OR bt.id <> NEW.base_timetable_id)
      AND (v_deleting_bt_id IS NULL OR bt.id <> v_deleting_bt_id)
      AND bt.faculty_id = v_effective_faculty
      AND bt.day_of_week = v_dow
      AND bt.effective_from <= NEW.session_date
      AND (bt.effective_to IS NULL OR bt.effective_to >= NEW.session_date)
      AND bt.start_time < NEW.end_time
      AND bt.end_time > NEW.start_time
      AND NOT EXISTS (
        SELECT 1 FROM public.lecture_sessions ls_mat
        WHERE ls_mat.base_timetable_id = bt.id
          AND (ls_mat.session_date = NEW.session_date OR ls_mat.original_date = NEW.session_date)
      )
  ) THEN
    RAISE EXCEPTION 'Slot conflict: instructor already has an overlapping lecture on % (% - %).',
      NEW.session_date, to_char(NEW.start_time, 'HH24:MI'), to_char(NEW.end_time, 'HH24:MI');
  END IF;

  -- 2. Room overlap
  IF EXISTS (
    SELECT 1 FROM public.lecture_sessions ls
    WHERE ls.id IS DISTINCT FROM NEW.id
      AND ls.session_date = NEW.session_date
      AND ls.status IN ('scheduled', 'rescheduled', 'covered')
      AND ls.room_id = NEW.room_id
      AND ls.start_time < NEW.end_time
      AND ls.end_time > NEW.start_time
  ) OR EXISTS (
    SELECT 1 FROM public.base_timetable bt
    WHERE (NEW.base_timetable_id IS NULL OR bt.id <> NEW.base_timetable_id)
      AND (v_deleting_bt_id IS NULL OR bt.id <> v_deleting_bt_id)
      AND bt.room_id = NEW.room_id
      AND bt.day_of_week = v_dow
      AND bt.effective_from <= NEW.session_date
      AND (bt.effective_to IS NULL OR bt.effective_to >= NEW.session_date)
      AND bt.start_time < NEW.end_time
      AND bt.end_time > NEW.start_time
      AND NOT EXISTS (
        SELECT 1 FROM public.lecture_sessions ls_mat
        WHERE ls_mat.base_timetable_id = bt.id
          AND (ls_mat.session_date = NEW.session_date OR ls_mat.original_date = NEW.session_date)
      )
  ) THEN
    RAISE EXCEPTION 'Slot conflict: selected room is already occupied on % (% - %).',
      NEW.session_date, to_char(NEW.start_time, 'HH24:MI'), to_char(NEW.end_time, 'HH24:MI');
  END IF;

  -- 3. Cohort + batch overlap (uses effective course COALESCE(covering_course_id, course_id))
  IF EXISTS (
    SELECT 1
    FROM public.lecture_sessions ls
    JOIN public.course_cohorts cc_existing ON cc_existing.course_id = COALESCE(ls.covering_course_id, ls.course_id)
    JOIN public.course_cohorts cc_target ON cc_target.cohort_id = cc_existing.cohort_id
    WHERE cc_target.course_id = v_effective_course
      AND ls.id IS DISTINCT FROM NEW.id
      AND ls.session_date = NEW.session_date
      AND ls.status IN ('scheduled', 'rescheduled', 'covered')
      AND ls.start_time < NEW.end_time
      AND ls.end_time > NEW.start_time
      AND (ls.batch = 'ALL' OR NEW.batch = 'ALL' OR ls.batch = NEW.batch)
  ) OR EXISTS (
    SELECT 1
    FROM public.base_timetable bt
    JOIN public.course_cohorts cc_existing ON cc_existing.course_id = bt.course_id
    JOIN public.course_cohorts cc_target ON cc_target.cohort_id = cc_existing.cohort_id
    WHERE cc_target.course_id = v_effective_course
      AND (NEW.base_timetable_id IS NULL OR bt.id <> NEW.base_timetable_id)
      AND (v_deleting_bt_id IS NULL OR bt.id <> v_deleting_bt_id)
      AND bt.day_of_week = v_dow
      AND bt.effective_from <= NEW.session_date
      AND (bt.effective_to IS NULL OR bt.effective_to >= NEW.session_date)
      AND bt.start_time < NEW.end_time
      AND bt.end_time > NEW.start_time
      AND (bt.batch = 'ALL' OR NEW.batch = 'ALL' OR bt.batch = NEW.batch)
      AND NOT EXISTS (
        SELECT 1 FROM public.lecture_sessions ls_mat
        WHERE ls_mat.base_timetable_id = bt.id
          AND (ls_mat.session_date = NEW.session_date OR ls_mat.original_date = NEW.session_date)
      )
  ) THEN
    RAISE EXCEPTION 'Slot conflict: affected cohort/batch already has an overlapping lecture on % (% - %).',
      NEW.session_date, to_char(NEW.start_time, 'HH24:MI'), to_char(NEW.end_time, 'HH24:MI');
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.enforce_lecture_session_no_overlap() FROM PUBLIC, anon, authenticated;

-- ============================================================================
-- 5. COURSE-AWARE opt_in_coverage(p_session_id, p_covering_course_id)
-- ============================================================================
DROP FUNCTION IF EXISTS public.opt_in_coverage(UUID);

CREATE OR REPLACE FUNCTION public.opt_in_coverage(
  p_session_id UUID,
  p_covering_course_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT;
  v_session public.lecture_sessions%ROWTYPE;
  v_cov_code TEXT;
  v_cov_name TEXT;
  v_faculty_name TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;

  SELECT role, full_name INTO v_role, v_faculty_name
  FROM public.profiles
  WHERE id = auth.uid();

  IF v_role IS DISTINCT FROM 'faculty' THEN
    RAISE EXCEPTION 'Only faculty members can opt in to cover a lecture.';
  END IF;

  IF p_covering_course_id IS NULL THEN
    RAISE EXCEPTION 'Please select which of your assigned courses you will conduct in this slot.';
  END IF;

  PERFORM pg_advisory_xact_lock(704000, 1);

  SELECT * INTO v_session
  FROM public.lecture_sessions
  WHERE id = p_session_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Lecture session not found.';
  END IF;

  IF v_session.is_open_for_coverage IS NOT TRUE
     OR v_session.status NOT IN ('cancelled', 'rescheduling_pending')
     OR v_session.covering_faculty_id IS NOT NULL THEN
    RAISE EXCEPTION 'This slot is no longer open for coverage.';
  END IF;

  IF v_session.faculty_id = auth.uid() THEN
    RAISE EXCEPTION 'Assigned faculty should restore or reschedule their own lecture instead of opting into coverage.';
  END IF;

  -- Volunteering faculty MUST actually teach p_covering_course_id
  IF NOT public.is_faculty_assigned_to_course(p_covering_course_id, auth.uid()) THEN
    RAISE EXCEPTION 'You can only cover an open slot with a course assigned to you.';
  END IF;

  -- Covering course MUST share at least one cohort with the cancelled lecture
  IF NOT EXISTS (
    SELECT 1
    FROM public.course_cohorts cc_open
    JOIN public.course_cohorts cc_cov ON cc_cov.cohort_id = cc_open.cohort_id
    WHERE cc_open.course_id = v_session.course_id
      AND cc_cov.course_id = p_covering_course_id
  ) THEN
    RAISE EXCEPTION 'Selected course does not belong to the cohort whose lecture was cancelled.';
  END IF;

  SELECT code, name INTO v_cov_code, v_cov_name
  FROM public.courses
  WHERE id = p_covering_course_id;

  -- Atomic UPDATE: overlap trigger validates faculty, room, and covering course cohort(s)
  UPDATE public.lecture_sessions
  SET covering_faculty_id = auth.uid(),
      covering_course_id = p_covering_course_id,
      status = 'covered',
      is_open_for_coverage = FALSE,
      reason = COALESCE(NULLIF(BTRIM(reason), '') || ' — ', '')
               || 'Slot taken by ' || v_cov_code || ' (' || v_faculty_name || ')'
  WHERE id = p_session_id;

  RETURN jsonb_build_object(
    'success', true,
    'session_id', p_session_id,
    'covering_course_id', p_covering_course_id,
    'covering_course_code', v_cov_code
  );
END;
$$;

REVOKE ALL ON FUNCTION public.opt_in_coverage(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.opt_in_coverage(UUID, UUID) TO authenticated;

-- ============================================================================
-- 6. UPDATE update_lecture_session, confirm_poll_option & undo_last_lecture_change
-- ============================================================================
CREATE OR REPLACE FUNCTION public.update_lecture_session(
  p_session_id UUID,
  p_status TEXT,
  p_session_date DATE DEFAULT NULL,
  p_start_time TIME DEFAULT NULL,
  p_end_time TIME DEFAULT NULL,
  p_room_id UUID DEFAULT NULL,
  p_change_scope TEXT DEFAULT 'temporary',
  p_reason TEXT DEFAULT NULL,
  p_is_open_for_coverage BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT;
  v_session public.lecture_sessions%ROWTYPE;
  v_bt public.base_timetable%ROWTYPE;
  v_future public.lecture_sessions%ROWTYPE;
  v_new_date DATE;
  v_new_start TIME;
  v_new_end TIME;
  v_new_room UUID;
  v_new_bt_id UUID;
  v_slot_changed BOOLEAN;
  v_cutover_date DATE;
  v_day_delta INT;
  v_mode TEXT;
  v_shift_ids UUID[] := ARRAY[]::UUID[];
  v_shifted_snapshots JSONB := '[]'::jsonb;
  v_side_effects JSONB := NULL;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;

  SELECT role INTO v_role FROM public.profiles WHERE id = auth.uid();
  IF v_role IS NULL OR v_role NOT IN ('faculty', 'admin') THEN
    RAISE EXCEPTION 'Only faculty or admins can update lecture sessions.';
  END IF;

  PERFORM pg_advisory_xact_lock(704000, 1);

  SELECT * INTO v_session
  FROM public.lecture_sessions
  WHERE id = p_session_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Lecture session not found.';
  END IF;

  IF v_role = 'faculty'
     AND v_session.faculty_id IS DISTINCT FROM auth.uid()
     AND v_session.covering_faculty_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'You are not assigned to this lecture session.';
  END IF;

  -- A replacement faculty may not restore/move the original lecture; they can only give the slot back.
  IF v_role = 'faculty'
     AND v_session.status = 'covered'
     AND v_session.faculty_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'You are covering this slot. Use withdraw_coverage() to give it back.';
  END IF;

  IF p_status NOT IN ('scheduled', 'cancelled', 'rescheduling_pending', 'rescheduled') THEN
    RAISE EXCEPTION 'Invalid target status. Use opt_in_coverage() for covered sessions.';
  END IF;

  IF p_change_scope NOT IN ('temporary', 'permanent') THEN
    RAISE EXCEPTION 'change_scope must be temporary or permanent.';
  END IF;

  v_new_date := COALESCE(p_session_date, v_session.session_date);
  v_new_start := COALESCE(p_start_time, v_session.start_time);
  v_new_end := COALESCE(p_end_time, v_session.end_time);
  v_new_room := COALESCE(p_room_id, v_session.room_id);
  v_new_bt_id := v_session.base_timetable_id;

  v_slot_changed := (
    v_new_date IS DISTINCT FROM v_session.session_date
    OR v_new_start IS DISTINCT FROM v_session.start_time
    OR v_new_end IS DISTINCT FROM v_session.end_time
    OR v_new_room IS DISTINCT FROM v_session.room_id
  );

  IF v_slot_changed AND p_status IN ('cancelled', 'rescheduling_pending') THEN
    RAISE EXCEPTION 'A cancelled or rescheduling-pending lecture cannot also change its slot. Use status rescheduled to move a lecture.';
  END IF;

  IF p_change_scope = 'permanent' THEN
    IF v_session.base_timetable_id IS NULL THEN
      RAISE EXCEPTION 'Permanent changes require a lecture session linked to a recurring base timetable entry.';
    END IF;

    IF p_status NOT IN ('scheduled', 'rescheduled') OR NOT v_slot_changed THEN
      RAISE EXCEPTION 'Permanent changes must move the lecture to a new active day, time, or room.';
    END IF;

    SELECT * INTO v_bt
    FROM public.base_timetable
    WHERE id = v_session.base_timetable_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Linked base timetable entry was not found.';
    END IF;

    IF v_role = 'faculty' AND (
      v_bt.faculty_id IS DISTINCT FROM auth.uid()
      OR NOT public.is_faculty_assigned_to_course(v_bt.course_id, auth.uid())
    ) THEN
      RAISE EXCEPTION 'Only the assigned course faculty or an admin can make permanent timetable changes.';
    END IF;

    v_cutover_date := LEAST(v_session.session_date, v_new_date);
    v_day_delta := EXTRACT(ISODOW FROM v_new_date)::INT - EXTRACT(ISODOW FROM v_session.session_date)::INT;

    SELECT COALESCE(array_agg(ls.id ORDER BY ls.session_date), ARRAY[]::UUID[])
    INTO v_shift_ids
    FROM public.lecture_sessions ls
    WHERE ls.base_timetable_id = v_bt.id
      AND ls.id <> p_session_id
      AND ls.session_date > v_session.session_date
      AND ls.status = 'scheduled'
      AND ls.original_date IS NULL;

    PERFORM set_config('classcue.updating_session_id', p_session_id::TEXT, true);
    PERFORM set_config('classcue.shifting_session_ids', COALESCE(array_to_string(v_shift_ids, ','), ''), true);
    PERFORM set_config('classcue.suppress_bt_notif', 'true', true);

    IF v_cutover_date <= v_bt.effective_from THEN
      v_mode := 'in_place';
      UPDATE public.base_timetable
      SET day_of_week = EXTRACT(ISODOW FROM v_new_date)::INT,
          start_time = v_new_start,
          end_time = v_new_end,
          room_id = v_new_room
      WHERE id = v_bt.id;
      v_new_bt_id := v_bt.id;
    ELSE
      v_mode := 'split';
      UPDATE public.base_timetable
      SET effective_to = v_cutover_date - 1
      WHERE id = v_bt.id;

      INSERT INTO public.base_timetable (
        course_id, faculty_id, room_id, day_of_week, start_time, end_time,
        batch, session_type, effective_from, effective_to
      ) VALUES (
        v_bt.course_id, v_bt.faculty_id, v_new_room, EXTRACT(ISODOW FROM v_new_date)::INT,
        v_new_start, v_new_end, v_bt.batch, v_bt.session_type, v_cutover_date, v_bt.effective_to
      )
      RETURNING id INTO v_new_bt_id;
    END IF;

    PERFORM set_config('classcue.bulk_permanent_shift', 'true', true);
    FOR v_future IN
      SELECT * FROM public.lecture_sessions
      WHERE id = ANY(v_shift_ids)
      ORDER BY session_date
      FOR UPDATE
    LOOP
      v_shifted_snapshots := v_shifted_snapshots || jsonb_build_array(
        jsonb_build_object(
          'id', v_future.id,
          'before', to_jsonb(v_future),
          'after_version', v_future.version + 1
        )
      );

      UPDATE public.lecture_sessions
      SET base_timetable_id = v_new_bt_id,
          session_date = v_future.session_date + v_day_delta,
          start_time = v_new_start,
          end_time = v_new_end,
          room_id = v_new_room,
          change_scope = 'permanent'
      WHERE id = v_future.id;
    END LOOP;
    PERFORM set_config('classcue.bulk_permanent_shift', 'false', true);

    v_side_effects := jsonb_build_object(
      'base_timetable', jsonb_build_object(
        'mode', v_mode,
        'old_bt_id', v_bt.id,
        'old_bt_state', to_jsonb(v_bt),
        'new_bt_id', CASE WHEN v_mode = 'split' THEN v_new_bt_id ELSE NULL END
      ),
      'shifted_sessions', v_shifted_snapshots
    );

    PERFORM set_config('classcue.side_effects', v_side_effects::TEXT, true);
  END IF;

  -- Non-covered statuses always clear covering_faculty_id and covering_course_id
  UPDATE public.lecture_sessions
  SET base_timetable_id = v_new_bt_id,
      session_date = v_new_date,
      start_time = v_new_start,
      end_time = v_new_end,
      room_id = v_new_room,
      original_date = CASE WHEN v_slot_changed AND original_date IS NULL THEN v_session.session_date ELSE original_date END,
      original_start_time = CASE WHEN v_slot_changed AND original_date IS NULL THEN v_session.start_time ELSE original_start_time END,
      original_end_time = CASE WHEN v_slot_changed AND original_date IS NULL THEN v_session.end_time ELSE original_end_time END,
      original_room_id = CASE WHEN v_slot_changed AND original_date IS NULL THEN v_session.room_id ELSE original_room_id END,
      status = p_status,
      change_scope = p_change_scope,
      reason = p_reason,
      is_open_for_coverage = CASE
        WHEN p_status IN ('cancelled', 'rescheduling_pending') THEN COALESCE(p_is_open_for_coverage, FALSE)
        ELSE FALSE
      END,
      covering_faculty_id = NULL,
      covering_course_id = NULL
  WHERE id = p_session_id;

  PERFORM set_config('classcue.updating_session_id', '', true);
  PERFORM set_config('classcue.shifting_session_ids', '', true);
  PERFORM set_config('classcue.suppress_bt_notif', 'false', true);
  PERFORM set_config('classcue.side_effects', '', true);

  RETURN jsonb_build_object(
    'success', true,
    'session_id', p_session_id,
    'status', p_status,
    'change_scope', p_change_scope
  );
END;
$$;


CREATE OR REPLACE FUNCTION public.confirm_poll_option(
  p_poll_id UUID,
  p_option_id UUID,
  p_reason TEXT DEFAULT NULL,
  p_allow_early_close BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT;
  v_poll public.reschedule_polls%ROWTYPE;
  v_option public.poll_options%ROWTYPE;
  v_session public.lecture_sessions%ROWTYPE;
  v_target_room UUID;
  v_side_effects JSONB;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;

  SELECT role INTO v_role FROM public.profiles WHERE id = auth.uid();
  IF v_role IS NULL OR v_role NOT IN ('faculty', 'admin') THEN
    RAISE EXCEPTION 'Only assigned faculty or admins can confirm a reschedule poll.';
  END IF;

  PERFORM pg_advisory_xact_lock(704000, 1);

  SELECT * INTO v_poll FROM public.reschedule_polls WHERE id = p_poll_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Reschedule poll not found.';
  END IF;

  IF v_poll.status IS DISTINCT FROM 'open' THEN
    RAISE EXCEPTION 'Poll is no longer open (current status: %).', v_poll.status;
  END IF;

  IF v_poll.closes_at > NOW() AND p_allow_early_close IS NOT TRUE THEN
    RAISE EXCEPTION 'Voting is still open until %. Pass p_allow_early_close := true to close and confirm early.',
      v_poll.closes_at;
  END IF;

  IF v_poll.closes_at < NOW() - INTERVAL '48 hours' THEN
    RAISE EXCEPTION 'Poll expired more than 48 hours ago and can no longer be confirmed.';
  END IF;

  SELECT * INTO v_option
  FROM public.poll_options
  WHERE id = p_option_id AND poll_id = p_poll_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Selected option does not belong to this poll.';
  END IF;

  IF v_option.proposed_date < public.today_ist() THEN
    RAISE EXCEPTION 'Cannot confirm a proposed slot in the past (%).', v_option.proposed_date;
  END IF;

  SELECT * INTO v_session
  FROM public.lecture_sessions
  WHERE id = v_poll.lecture_session_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Associated lecture session was not found.';
  END IF;

  IF v_role = 'faculty'
     AND v_session.faculty_id IS DISTINCT FROM auth.uid()
     AND v_session.covering_faculty_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Only the assigned faculty member can confirm this poll.';
  END IF;

  IF v_session.version IS DISTINCT FROM v_poll.expected_session_version THEN
    RAISE EXCEPTION 'This poll is stale because the lecture session was updated after the poll was created.';
  END IF;

  v_target_room := COALESCE(v_option.proposed_room_id, v_session.room_id);
  v_side_effects := jsonb_build_object(
    'confirmed_poll', jsonb_build_object(
      'poll_id', p_poll_id,
      'option_id', p_option_id
    )
  );

  PERFORM set_config('classcue.confirming_poll', 'true', true);
  PERFORM set_config('classcue.side_effects', v_side_effects::TEXT, true);

  UPDATE public.lecture_sessions
  SET session_date = v_option.proposed_date,
      start_time = v_option.proposed_start_time,
      end_time = v_option.proposed_end_time,
      room_id = v_target_room,
      original_date = COALESCE(original_date, v_session.session_date),
      original_start_time = COALESCE(original_start_time, v_session.start_time),
      original_end_time = COALESCE(original_end_time, v_session.end_time),
      original_room_id = COALESCE(original_room_id, v_session.room_id),
      status = 'rescheduled',
      change_scope = 'temporary',
      is_open_for_coverage = FALSE,
      covering_faculty_id = NULL,
      covering_course_id = NULL,
      reason = COALESCE(NULLIF(BTRIM(p_reason), ''), 'Confirmed via class reschedule poll')
  WHERE id = v_session.id;

  UPDATE public.poll_options
  SET is_selected = (id = p_option_id)
  WHERE poll_id = p_poll_id;

  UPDATE public.reschedule_polls
  SET status = 'confirmed',
      closes_at = LEAST(closes_at, NOW())
  WHERE id = p_poll_id;

  PERFORM set_config('classcue.confirming_poll', 'false', true);
  PERFORM set_config('classcue.side_effects', '', true);

  RETURN jsonb_build_object(
    'success', true,
    'poll_id', p_poll_id,
    'selected_option_id', p_option_id,
    'session_id', v_session.id
  );
END;
$$;


CREATE OR REPLACE FUNCTION public.undo_last_lecture_change(p_session_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_role TEXT;
  v_session public.lecture_sessions%ROWTYPE;
  v_latest public.change_history%ROWTYPE;
  v_prev JSONB;
  v_bt_meta JSONB;
  v_old_bt_id UUID;
  v_new_bt_id UUID;
  v_old_bt_state JSONB;
  v_bt_mode TEXT;
  v_shift_item JSONB;
  v_shift_before JSONB;
  v_shift_id UUID;
  v_shift_expected_ver INT;
  v_shift_current_ver INT;
  v_shift_ids UUID[] := ARRAY[]::UUID[];
  v_poll_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;

  SELECT role INTO v_caller_role FROM public.profiles WHERE id = auth.uid();
  IF v_caller_role IS NULL OR v_caller_role NOT IN ('faculty', 'admin') THEN
    RAISE EXCEPTION 'Only faculty or admins can undo lecture changes.';
  END IF;

  PERFORM pg_advisory_xact_lock(704000, 1);

  SELECT * INTO v_session
  FROM public.lecture_sessions
  WHERE id = p_session_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Lecture session not found.';
  END IF;

  IF v_caller_role = 'faculty'
     AND v_session.faculty_id IS DISTINCT FROM auth.uid()
     AND v_session.covering_faculty_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'You are not authorized to undo changes on this lecture session.';
  END IF;

  SELECT * INTO v_latest
  FROM public.change_history
  WHERE lecture_session_id = p_session_id
  ORDER BY created_at DESC, id DESC
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No change history exists for this lecture session.';
  END IF;

  IF v_latest.action_type = 'undo' OR v_latest.undone_at IS NOT NULL THEN
    RAISE EXCEPTION 'The latest change has already been undone.';
  END IF;

  IF v_caller_role <> 'admin' AND v_latest.changed_by IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'You can only undo your own most recent change.';
  END IF;

  v_prev := v_latest.previous_state;

  IF v_latest.side_effects IS NOT NULL AND (v_latest.side_effects -> 'base_timetable') IS NOT NULL THEN
    v_bt_meta := v_latest.side_effects->'base_timetable';
    v_bt_mode := v_bt_meta->>'mode';
    v_old_bt_id := (v_bt_meta->>'old_bt_id')::UUID;
    v_new_bt_id := NULLIF(v_bt_meta->>'new_bt_id', '')::UUID;
    v_old_bt_state := v_bt_meta->'old_bt_state';

    IF NOT EXISTS (SELECT 1 FROM public.base_timetable WHERE id = v_old_bt_id) THEN
      RAISE EXCEPTION 'Cannot undo permanent change: original base timetable entry no longer exists.';
    END IF;

    IF EXISTS (
      SELECT 1 FROM public.base_timetable_history
      WHERE target_base_timetable_id IN (v_old_bt_id, COALESCE(v_new_bt_id, v_old_bt_id))
        AND created_at > v_latest.created_at
    ) THEN
      RAISE EXCEPTION 'Cannot undo permanent change: the recurring base timetable was modified again after this change.';
    END IF;

    FOR v_shift_item IN
      SELECT value FROM jsonb_array_elements(COALESCE(v_latest.side_effects->'shifted_sessions', '[]'::jsonb))
    LOOP
      v_shift_id := (v_shift_item->>'id')::UUID;
      v_shift_expected_ver := (v_shift_item->>'after_version')::INT;
      SELECT version INTO v_shift_current_ver
      FROM public.lecture_sessions
      WHERE id = v_shift_id
      FOR UPDATE;

      IF NOT FOUND OR v_shift_current_ver IS DISTINCT FROM v_shift_expected_ver THEN
        RAISE EXCEPTION 'Cannot undo permanent change: a future shifted lecture session (%) was subsequently modified.', v_shift_id;
      END IF;
      v_shift_ids := array_append(v_shift_ids, v_shift_id);
    END LOOP;

    IF v_bt_mode = 'split' AND v_new_bt_id IS NOT NULL THEN
      IF EXISTS (
        SELECT 1 FROM public.lecture_sessions
        WHERE base_timetable_id = v_new_bt_id
          AND id <> p_session_id
          AND NOT (id = ANY(v_shift_ids))
      ) THEN
        RAISE EXCEPTION 'Cannot undo permanent change: other lecture sessions now depend on the new recurring timetable entry.';
      END IF;
      PERFORM set_config('classcue.deleting_bt_id', v_new_bt_id::TEXT, true);
    END IF;

    PERFORM set_config('classcue.updating_session_id', p_session_id::TEXT, true);
    PERFORM set_config('classcue.shifting_session_ids', COALESCE(array_to_string(v_shift_ids, ','), ''), true);
    PERFORM set_config('classcue.suppress_bt_notif', 'true', true);

    PERFORM set_config('classcue.bulk_permanent_shift', 'true', true);
    FOR v_shift_item IN
      SELECT value FROM jsonb_array_elements(COALESCE(v_latest.side_effects->'shifted_sessions', '[]'::jsonb))
    LOOP
      v_shift_id := (v_shift_item->>'id')::UUID;
      v_shift_before := v_shift_item->'before';

      UPDATE public.lecture_sessions
      SET base_timetable_id = NULLIF(v_shift_before->>'base_timetable_id', '')::UUID,
          session_date = (v_shift_before->>'session_date')::DATE,
          start_time = (v_shift_before->>'start_time')::TIME,
          end_time = (v_shift_before->>'end_time')::TIME,
          room_id = (v_shift_before->>'room_id')::UUID,
          change_scope = COALESCE(v_shift_before->>'change_scope', 'temporary')
      WHERE id = v_shift_id;
    END LOOP;
    PERFORM set_config('classcue.bulk_permanent_shift', 'false', true);
  END IF;

  PERFORM set_config('classcue.is_undo', 'true', true);
  PERFORM set_config('classcue.reverts_history_id', v_latest.id::TEXT, true);

  UPDATE public.lecture_sessions
  SET base_timetable_id = NULLIF(v_prev->>'base_timetable_id', '')::UUID,
      session_date = (v_prev->>'session_date')::DATE,
      start_time = (v_prev->>'start_time')::TIME,
      end_time = (v_prev->>'end_time')::TIME,
      room_id = (v_prev->>'room_id')::UUID,
      batch = COALESCE(v_prev->>'batch', batch),
      original_date = NULLIF(v_prev->>'original_date', '')::DATE,
      original_start_time = NULLIF(v_prev->>'original_start_time', '')::TIME,
      original_end_time = NULLIF(v_prev->>'original_end_time', '')::TIME,
      original_room_id = NULLIF(v_prev->>'original_room_id', '')::UUID,
      status = v_prev->>'status',
      change_scope = COALESCE(v_prev->>'change_scope', 'temporary'),
      reason = v_prev->>'reason',
      is_open_for_coverage = COALESCE((v_prev->>'is_open_for_coverage')::BOOLEAN, FALSE),
      covering_faculty_id = NULLIF(v_prev->>'covering_faculty_id', '')::UUID,
      covering_course_id = NULLIF(v_prev->>'covering_course_id', '')::UUID
  WHERE id = p_session_id;

  IF v_bt_meta IS NOT NULL THEN
    IF v_bt_mode = 'split' AND v_new_bt_id IS NOT NULL THEN
      DELETE FROM public.base_timetable WHERE id = v_new_bt_id;
    END IF;

    UPDATE public.base_timetable
    SET day_of_week = (v_old_bt_state->>'day_of_week')::INT,
        start_time = (v_old_bt_state->>'start_time')::TIME,
        end_time = (v_old_bt_state->>'end_time')::TIME,
        room_id = (v_old_bt_state->>'room_id')::UUID,
        effective_from = (v_old_bt_state->>'effective_from')::DATE,
        effective_to = NULLIF(v_old_bt_state->>'effective_to', '')::DATE
    WHERE id = v_old_bt_id;
  END IF;

  IF v_latest.side_effects IS NOT NULL AND (v_latest.side_effects -> 'confirmed_poll') IS NOT NULL THEN
    v_poll_id := (v_latest.side_effects->'confirmed_poll'->>'poll_id')::UUID;
    PERFORM set_config('classcue.confirming_poll', 'true', true);
    UPDATE public.poll_options SET is_selected = FALSE WHERE poll_id = v_poll_id;
    UPDATE public.reschedule_polls SET status = 'cancelled_fallback' WHERE id = v_poll_id;
    PERFORM set_config('classcue.confirming_poll', 'false', true);
  END IF;

  PERFORM set_config('classcue.is_undo', 'false', true);
  PERFORM set_config('classcue.reverts_history_id', '', true);
  PERFORM set_config('classcue.deleting_bt_id', '', true);
  PERFORM set_config('classcue.updating_session_id', '', true);
  PERFORM set_config('classcue.shifting_session_ids', '', true);
  PERFORM set_config('classcue.suppress_bt_notif', 'false', true);

  UPDATE public.change_history
  SET undone_at = NOW()
  WHERE id = v_latest.id;

  RETURN jsonb_build_object(
    'success', true,
    'reverted_history_id', v_latest.id,
    'restored_status', v_prev->>'status',
    'reverted_base_timetable', (v_bt_meta IS NOT NULL)
  );
END;
$$;


-- ============================================================================
-- 7. UPDATE NOTIFICATION TRIGGER FOR COURSE-AWARE COVERAGE & COHORT-SCOPED OPEN ALERTS
-- ============================================================================
CREATE OR REPLACE FUNCTION public.handle_lecture_session_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor UUID;
  v_is_undo BOOLEAN;
  v_is_confirming_poll BOOLEAN;
  v_is_bulk_shift BOOLEAN;
  v_reverts_id UUID;
  v_side_effects JSONB;
  v_course_code TEXT;
  v_course_name TEXT;
  v_cov_code TEXT;
  v_cov_name TEXT;
  v_cov_faculty_name TEXT;
  v_room_num TEXT;
  v_action TEXT := 'status_update';
  v_notif_type TEXT := 'reschedule';
  v_title TEXT;
  v_body TEXT;
  v_notify_course_id UUID;
BEGIN
  IF NOT public.lecture_session_row_changed(OLD, NEW) THEN
    RETURN NEW;
  END IF;

  v_is_confirming_poll := (COALESCE(current_setting('classcue.confirming_poll', true), '') = 'true');
  v_is_bulk_shift := (COALESCE(current_setting('classcue.bulk_permanent_shift', true), '') = 'true');

  IF NOT v_is_confirming_poll THEN
    PERFORM set_config('classcue.superseding_poll', 'true', true);
    UPDATE public.reschedule_polls
    SET status = 'superseded'
    WHERE lecture_session_id = NEW.id
      AND status = 'open';
    PERFORM set_config('classcue.superseding_poll', 'false', true);
  END IF;

  IF v_is_bulk_shift THEN
    RETURN NEW;
  END IF;

  v_actor := COALESCE(auth.uid(), NEW.updated_by, NEW.faculty_id);
  v_is_undo := (COALESCE(current_setting('classcue.is_undo', true), '') = 'true');
  v_reverts_id := NULLIF(current_setting('classcue.reverts_history_id', true), '')::UUID;
  v_side_effects := NULLIF(current_setting('classcue.side_effects', true), '')::JSONB;

  SELECT code, name INTO v_course_code, v_course_name FROM public.courses WHERE id = NEW.course_id;
  SELECT room_number INTO v_room_num FROM public.rooms WHERE id = NEW.room_id;

  -- Default recipient course is the active course (covering_course_id when covered)
  v_notify_course_id := COALESCE(NEW.covering_course_id, NEW.course_id);

  IF v_is_undo THEN
    v_action := 'undo';
    v_notif_type := 'reschedule';
    v_title := v_course_code || ' Update Reverted';
    v_body := v_course_name || ' was restored to ' || NEW.status || ' on '
      || to_char(NEW.session_date, 'Dy DD Mon') || ' (' || to_char(NEW.start_time, 'HH24:MI')
      || ', ' || v_room_num || ').';
  ELSIF NEW.status = 'cancelled' THEN
    v_action := 'cancel';
    v_notif_type := 'cancellation';
    v_title := v_course_code || ' Cancelled';
    v_body := v_course_name || ' on ' || to_char(NEW.session_date, 'Dy DD Mon')
      || ' (' || to_char(NEW.start_time, 'HH24:MI') || ') is cancelled.'
      || COALESCE(' Reason: ' || NULLIF(BTRIM(NEW.reason), ''), '');
  ELSIF NEW.status = 'rescheduling_pending' THEN
    v_action := 'status_update';
    v_notif_type := 'cancellation';
    v_title := v_course_code || ' — Rescheduling Pending';
    v_body := v_course_name || ' on ' || to_char(NEW.session_date, 'Dy DD Mon')
      || ' will be rescheduled. Replacement slot pending confirmation.';
  ELSIF NEW.status = 'covered'
        AND (OLD.covering_faculty_id IS DISTINCT FROM NEW.covering_faculty_id
             OR OLD.covering_course_id IS DISTINCT FROM NEW.covering_course_id) THEN
    SELECT code, name INTO v_cov_code, v_cov_name FROM public.courses WHERE id = NEW.covering_course_id;
    SELECT full_name INTO v_cov_faculty_name FROM public.profiles WHERE id = NEW.covering_faculty_id;

    v_action := 'cover_opt_in';
    v_notif_type := 'reschedule';
    v_title := v_cov_code || ' Taking Cancelled ' || v_course_code || ' Slot';
    v_body := v_cov_name || ' (' || COALESCE(v_cov_faculty_name, 'Replacement Faculty')
      || ') will be held in place of cancelled ' || v_course_code || ' on '
      || to_char(NEW.session_date, 'Dy DD Mon') || ' at ' || to_char(NEW.start_time, 'HH24:MI')
      || ' in ' || v_room_num || '.';
  ELSIF OLD.room_id IS DISTINCT FROM NEW.room_id
        AND OLD.start_time IS NOT DISTINCT FROM NEW.start_time
        AND OLD.end_time IS NOT DISTINCT FROM NEW.end_time
        AND OLD.session_date IS NOT DISTINCT FROM NEW.session_date THEN
    v_action := CASE WHEN NEW.change_scope = 'permanent' THEN 'permanent_update' ELSE 'room_change' END;
    v_notif_type := 'room_change';
    v_title := v_course_code || ' Room Changed to ' || v_room_num;
    v_body := v_course_name || ' on ' || to_char(NEW.session_date, 'Dy DD Mon')
      || ' (' || to_char(NEW.start_time, 'HH24:MI') || ') moved to room ' || v_room_num || '.';
  ELSIF OLD.session_date IS DISTINCT FROM NEW.session_date
        OR OLD.start_time IS DISTINCT FROM NEW.start_time
        OR OLD.end_time IS DISTINCT FROM NEW.end_time
        OR NEW.status = 'rescheduled' THEN
    v_action := CASE WHEN NEW.change_scope = 'permanent' THEN 'permanent_update' ELSE 'reschedule' END;
    v_notif_type := 'reschedule';
    v_title := v_course_code || ' Rescheduled (' || INITCAP(NEW.change_scope) || ')';
    v_body := v_course_name || ' moved to ' || to_char(NEW.session_date, 'Dy DD Mon')
      || ' at ' || to_char(NEW.start_time, 'HH24:MI') || ' in ' || v_room_num || '.';
  ELSE
    v_action := 'status_update';
    v_notif_type := 'reminder';
    v_title := v_course_code || ' Details Updated';
    v_body := v_course_name || ' on ' || to_char(NEW.session_date, 'Dy DD Mon')
      || ' (' || to_char(NEW.start_time, 'HH24:MI') || ', ' || v_room_num || ') has updated details.';
  END IF;

  INSERT INTO public.change_history (
    lecture_session_id, changed_by, action_type, previous_state, new_state, side_effects, reason, reverts_history_id
  ) VALUES (
    NEW.id, v_actor, v_action, to_jsonb(OLD), to_jsonb(NEW), v_side_effects, NEW.reason,
    CASE WHEN v_is_undo THEN v_reverts_id ELSE NULL END
  );

  -- Notify CRs & batch-matched Students for the active course (and previous covering course on undo)
  INSERT INTO public.notifications (user_id, lecture_session_id, title, body, type)
  SELECT DISTINCT p.id, NEW.id, v_title, v_body, v_notif_type
  FROM public.profiles p
  JOIN public.course_cohorts cc ON cc.cohort_id = p.cohort_id
  WHERE cc.course_id IN (v_notify_course_id, COALESCE(OLD.covering_course_id, v_notify_course_id))
    AND (
      p.role = 'cr'
      OR (p.role = 'student' AND (NEW.batch = 'ALL' OR p.lab_batch = NEW.batch))
    );

  -- Notify assigned, covering, and previously covering Faculty
  INSERT INTO public.notifications (user_id, lecture_session_id, title, body, type)
  SELECT DISTINCT p.id, NEW.id, v_title, v_body, v_notif_type
  FROM public.profiles p
  WHERE p.id IN (NEW.faculty_id, NEW.covering_faculty_id, OLD.covering_faculty_id)
    AND p.id IS NOT NULL;

  -- Notify ONLY cohort-eligible faculty when a slot opens for coverage
  IF NEW.is_open_for_coverage IS TRUE AND OLD.is_open_for_coverage IS NOT TRUE THEN
    INSERT INTO public.notifications (user_id, lecture_session_id, title, body, type)
    SELECT p.id, NEW.id,
      'Open Slot for Coverage: ' || v_course_code,
      'Cancelled ' || v_course_code || ' slot on ' || to_char(NEW.session_date, 'Dy DD Mon')
        || ' (' || to_char(NEW.start_time, 'HH24:MI') || ', ' || v_room_num
        || ') is open for you to conduct your assigned course.',
      'coverage_open'
    FROM public.profiles p
    WHERE p.role = 'faculty'
      AND p.id <> NEW.faculty_id
      AND p.id IS DISTINCT FROM OLD.covering_faculty_id
      AND public.can_faculty_cover_session(NEW.course_id, p.id);
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.handle_lecture_session_update() FROM PUBLIC, anon, authenticated;

-- ============================================================================
-- 8. withdraw_coverage(): the covering faculty gives the slot back (re-opens it for other faculty)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.withdraw_coverage(
  p_session_id UUID,
  p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT;
  v_session public.lecture_sessions%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;

  SELECT role INTO v_role FROM public.profiles WHERE id = auth.uid();
  IF v_role IS NULL OR v_role NOT IN ('faculty', 'admin') THEN
    RAISE EXCEPTION 'Only faculty or admins can withdraw coverage.';
  END IF;

  PERFORM pg_advisory_xact_lock(704000, 1);

  SELECT * INTO v_session FROM public.lecture_sessions WHERE id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Lecture session not found.';
  END IF;

  IF v_session.status <> 'covered' OR v_session.covering_faculty_id IS NULL THEN
    RAISE EXCEPTION 'This slot is not currently being covered.';
  END IF;

  IF v_role = 'faculty' AND v_session.covering_faculty_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Only the covering faculty member can withdraw coverage.';
  END IF;

  UPDATE public.lecture_sessions
  SET status = 'cancelled',
      is_open_for_coverage = TRUE,
      covering_faculty_id = NULL,
      covering_course_id = NULL,
      reason = COALESCE(NULLIF(BTRIM(p_reason), ''), 'Replacement faculty withdrew; slot is open again')
  WHERE id = p_session_id;

  RETURN jsonb_build_object('success', true, 'session_id', p_session_id, 'status', 'cancelled');
END;
$$;

REVOKE ALL ON FUNCTION public.withdraw_coverage(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.withdraw_coverage(UUID, TEXT) TO authenticated;

-- ============================================================================
-- 9. check_slot_conflicts(): treat a covered session as its EFFECTIVE course
--    (same rule the overlap trigger uses), so the preview never disagrees with the write.
--    Only change vs 003: cohort-overlap join uses COALESCE(ls.covering_course_id, ls.course_id).
-- ============================================================================
CREATE OR REPLACE FUNCTION public.check_slot_conflicts(
  p_course_id UUID,
  p_session_date DATE,
  p_start_time TIME,
  p_end_time TIME,
  p_room_id UUID,
  p_faculty_id UUID,
  p_batch TEXT DEFAULT 'ALL',
  p_exclude_session_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_role TEXT;
  v_caller_cohort UUID;
  v_exclude_bt_id UUID;
  v_dow INT;
  v_cohort_conflict BOOLEAN;
  v_faculty_conflict BOOLEAN;
  v_room_conflict BOOLEAN;
  v_suggested_rooms JSONB;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;

  SELECT role, cohort_id INTO v_caller_role, v_caller_cohort
  FROM public.profiles
  WHERE id = auth.uid();

  IF v_caller_role IS NULL OR v_caller_role NOT IN ('cr', 'faculty', 'admin') THEN
    RAISE EXCEPTION 'Only CRs, faculty, and admins can check slot conflicts.';
  END IF;

  IF p_course_id IS NULL OR p_session_date IS NULL OR p_start_time IS NULL OR p_end_time IS NULL OR p_faculty_id IS NULL THEN
    RAISE EXCEPTION 'Course, date, start time, end time, and faculty are required.';
  END IF;

  IF p_end_time <= p_start_time THEN
    RAISE EXCEPTION 'end_time must be strictly after start_time.';
  END IF;

  IF p_batch IS NULL OR p_batch NOT IN ('ALL', 'B1', 'B2') THEN
    RAISE EXCEPTION 'Invalid batch value. Must be ALL, B1, or B2.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_faculty_id AND role = 'faculty') THEN
    RAISE EXCEPTION 'Target instructor must be a valid faculty profile.';
  END IF;

  -- Validate excluded session belongs to p_course_id
  IF p_exclude_session_id IS NOT NULL THEN
    SELECT base_timetable_id INTO v_exclude_bt_id
    FROM public.lecture_sessions
    WHERE id = p_exclude_session_id AND course_id = p_course_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Excluded session does not exist or does not belong to the specified course.';
    END IF;
  END IF;

  -- Anti-probing authorization rules
  IF v_caller_role = 'faculty' THEN
    IF p_faculty_id IS DISTINCT FROM auth.uid() THEN
      RAISE EXCEPTION 'Faculty members may only check conflicts for their own schedule.';
    END IF;

    IF NOT public.is_faculty_assigned_to_course(p_course_id, auth.uid())
       AND NOT EXISTS (
         SELECT 1 FROM public.lecture_sessions ls
         WHERE ls.id = p_exclude_session_id
           AND ls.course_id = p_course_id
           AND (ls.faculty_id = auth.uid() OR ls.covering_faculty_id = auth.uid() OR ls.is_open_for_coverage IS TRUE)
       ) THEN
      RAISE EXCEPTION 'You are not assigned to this course or eligible to check this session.';
    END IF;
  ELSIF v_caller_role = 'cr' THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.course_cohorts
      WHERE course_id = p_course_id AND cohort_id = v_caller_cohort
    ) THEN
      RAISE EXCEPTION 'CR can only check conflicts for courses in their own cohort.';
    END IF;

    IF NOT public.is_faculty_assigned_to_course(p_course_id, p_faculty_id)
       AND NOT EXISTS (
         SELECT 1 FROM public.lecture_sessions ls
         WHERE ls.id = p_exclude_session_id
           AND ls.course_id = p_course_id
           AND (ls.faculty_id = p_faculty_id OR ls.covering_faculty_id = p_faculty_id)
       ) THEN
      RAISE EXCEPTION 'CR may only check conflicts for faculty assigned to this course or session.';
    END IF;
  END IF;

  v_dow := EXTRACT(ISODOW FROM p_session_date)::INT;

  -- A. Cohort overlap
  SELECT (
    EXISTS (
      SELECT 1
      FROM public.lecture_sessions ls
      JOIN public.course_cohorts cc_existing ON cc_existing.course_id = COALESCE(ls.covering_course_id, ls.course_id)
      JOIN public.course_cohorts cc_target ON cc_target.cohort_id = cc_existing.cohort_id
      WHERE cc_target.course_id = p_course_id
        AND ls.session_date = p_session_date
        AND ls.status IN ('scheduled', 'rescheduled', 'covered')
        AND ls.start_time < p_end_time
        AND ls.end_time > p_start_time
        AND (ls.batch = 'ALL' OR p_batch = 'ALL' OR ls.batch = p_batch)
        AND (p_exclude_session_id IS NULL OR ls.id <> p_exclude_session_id)
    )
    OR EXISTS (
      SELECT 1
      FROM public.base_timetable bt
      JOIN public.course_cohorts cc_existing ON cc_existing.course_id = bt.course_id
      JOIN public.course_cohorts cc_target ON cc_target.cohort_id = cc_existing.cohort_id
      WHERE cc_target.course_id = p_course_id
        AND (v_exclude_bt_id IS NULL OR bt.id <> v_exclude_bt_id)
        AND bt.day_of_week = v_dow
        AND bt.effective_from <= p_session_date
        AND (bt.effective_to IS NULL OR bt.effective_to >= p_session_date)
        AND bt.start_time < p_end_time
        AND bt.end_time > p_start_time
        AND (bt.batch = 'ALL' OR p_batch = 'ALL' OR bt.batch = p_batch)
        AND NOT EXISTS (
          SELECT 1 FROM public.lecture_sessions ls
          WHERE ls.base_timetable_id = bt.id
            AND (ls.session_date = p_session_date OR ls.original_date = p_session_date)
        )
    )
  ) INTO v_cohort_conflict;

  -- B. Effective faculty overlap (boolean only)
  SELECT (
    EXISTS (
      SELECT 1
      FROM public.lecture_sessions ls
      WHERE COALESCE(ls.covering_faculty_id, ls.faculty_id) = p_faculty_id
        AND ls.session_date = p_session_date
        AND ls.status IN ('scheduled', 'rescheduled', 'covered')
        AND ls.start_time < p_end_time
        AND ls.end_time > p_start_time
        AND (p_exclude_session_id IS NULL OR ls.id <> p_exclude_session_id)
    )
    OR EXISTS (
      SELECT 1
      FROM public.base_timetable bt
      WHERE (v_exclude_bt_id IS NULL OR bt.id <> v_exclude_bt_id)
        AND bt.faculty_id = p_faculty_id
        AND bt.day_of_week = v_dow
        AND bt.effective_from <= p_session_date
        AND (bt.effective_to IS NULL OR bt.effective_to >= p_session_date)
        AND bt.start_time < p_end_time
        AND bt.end_time > p_start_time
        AND NOT EXISTS (
          SELECT 1 FROM public.lecture_sessions ls
          WHERE ls.base_timetable_id = bt.id
            AND (ls.session_date = p_session_date OR ls.original_date = p_session_date)
        )
    )
  ) INTO v_faculty_conflict;

  -- C. Room overlap
  IF p_room_id IS NULL THEN
    v_room_conflict := FALSE;
  ELSE
    SELECT (
      EXISTS (
        SELECT 1
        FROM public.lecture_sessions ls
        WHERE ls.room_id = p_room_id
          AND ls.session_date = p_session_date
          AND ls.status IN ('scheduled', 'rescheduled', 'covered')
          AND ls.start_time < p_end_time
          AND ls.end_time > p_start_time
          AND (p_exclude_session_id IS NULL OR ls.id <> p_exclude_session_id)
      )
      OR EXISTS (
        SELECT 1
        FROM public.base_timetable bt
        WHERE (v_exclude_bt_id IS NULL OR bt.id <> v_exclude_bt_id)
          AND bt.room_id = p_room_id
          AND bt.day_of_week = v_dow
          AND bt.effective_from <= p_session_date
          AND (bt.effective_to IS NULL OR bt.effective_to >= p_session_date)
          AND bt.start_time < p_end_time
          AND bt.end_time > p_start_time
          AND NOT EXISTS (
            SELECT 1 FROM public.lecture_sessions ls
            WHERE ls.base_timetable_id = bt.id
              AND (ls.session_date = p_session_date OR ls.original_date = p_session_date)
          )
      )
    ) INTO v_room_conflict;
  END IF;

  -- D. Suggest free rooms
  SELECT COALESCE(
    jsonb_agg(jsonb_build_object('id', r.id, 'room_number', r.room_number, 'is_lab', r.is_lab) ORDER BY r.room_number),
    '[]'::jsonb
  )
  INTO v_suggested_rooms
  FROM public.rooms r
  WHERE NOT EXISTS (
    SELECT 1 FROM public.lecture_sessions ls
    WHERE ls.room_id = r.id
      AND ls.session_date = p_session_date
      AND ls.status IN ('scheduled', 'rescheduled', 'covered')
      AND ls.start_time < p_end_time
      AND ls.end_time > p_start_time
      AND (p_exclude_session_id IS NULL OR ls.id <> p_exclude_session_id)
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.base_timetable bt
    WHERE (v_exclude_bt_id IS NULL OR bt.id <> v_exclude_bt_id)
      AND bt.room_id = r.id
      AND bt.day_of_week = v_dow
      AND bt.effective_from <= p_session_date
      AND (bt.effective_to IS NULL OR bt.effective_to >= p_session_date)
      AND bt.start_time < p_end_time
      AND bt.end_time > p_start_time
      AND NOT EXISTS (
        SELECT 1 FROM public.lecture_sessions ls
        WHERE ls.base_timetable_id = bt.id
          AND (ls.session_date = p_session_date OR ls.original_date = p_session_date)
      )
  );

  RETURN jsonb_build_object(
    'has_conflict', (v_cohort_conflict OR v_faculty_conflict OR v_room_conflict),
    'cohort_conflict', v_cohort_conflict,
    'faculty_conflict', v_faculty_conflict,
    'room_conflict', v_room_conflict,
    'suggested_rooms', v_suggested_rooms
  );
END;
$$;