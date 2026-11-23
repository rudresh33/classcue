-- 002_rls_policies.sql
-- ClassCue — Strict RLS, RPC-Only Session Writes, B1/B2 Separation & Vote Privacy (v3.1)

-- 1. Helper Functions (SECURITY DEFINER avoids RLS recursion)
CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT role FROM public.profiles WHERE id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.current_user_cohort_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT cohort_id FROM public.profiles WHERE id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.current_user_lab_batch()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT lab_batch FROM public.profiles WHERE id = auth.uid();
$$;

-- Sole source of truth: public.course_faculty
CREATE OR REPLACE FUNCTION public.is_faculty_assigned_to_course(p_course_id UUID, p_faculty_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.course_faculty cf
    WHERE cf.course_id = p_course_id AND cf.faculty_id = p_faculty_id
  );
$$;

CREATE OR REPLACE FUNCTION public.can_manage_session_poll(p_session_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.lecture_sessions ls
    WHERE ls.id = p_session_id
      AND (
        public.current_user_role() = 'admin'
        OR (
          public.current_user_role() = 'faculty'
          AND (ls.faculty_id = auth.uid() OR ls.covering_faculty_id = auth.uid())
        )
        OR (
          public.current_user_role() = 'cr'
          AND EXISTS (
            SELECT 1
            FROM public.course_cohorts cc
            WHERE cc.course_id = ls.course_id
              AND cc.cohort_id = public.current_user_cohort_id()
          )
        )
      )
  );
$$;

-- Lock down helper execute privileges
REVOKE ALL ON FUNCTION public.current_user_role() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.current_user_cohort_id() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.current_user_lab_batch() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_faculty_assigned_to_course(UUID, UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.can_manage_session_poll(UUID) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.current_user_role() TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_user_cohort_id() TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_user_lab_batch() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_faculty_assigned_to_course(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_manage_session_poll(UUID) TO authenticated;

-- 2. Faculty Directory View
-- Runs with the owner's rights on purpose (so every signed-in user can see faculty names),
-- but ONLY faculty rows are exposed: no students, CRs, admins, emails, roles or cohorts.
CREATE OR REPLACE VIEW public.profile_directory AS
SELECT
  id,
  full_name,
  faculty_code
FROM public.profiles
WHERE role = 'faculty';

-- 3. Profile Guard Trigger (Blocks non-admin privileged edits AND prevents demoting assigned faculty)
CREATE OR REPLACE FUNCTION public.guard_profile_privileged_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND public.current_user_role() IS DISTINCT FROM 'admin' THEN
    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.email IS DISTINCT FROM OLD.email
       OR NEW.role IS DISTINCT FROM OLD.role
       OR NEW.cohort_id IS DISTINCT FROM OLD.cohort_id
       OR NEW.lab_batch IS DISTINCT FROM OLD.lab_batch
       OR NEW.faculty_type IS DISTINCT FROM OLD.faculty_type
       OR NEW.faculty_code IS DISTINCT FROM OLD.faculty_code THEN
      RAISE EXCEPTION 'Insufficient privileges to modify protected profile fields.';
    END IF;
  END IF;

  IF OLD.role = 'faculty' AND NEW.role IS DISTINCT FROM 'faculty' THEN
    IF EXISTS (SELECT 1 FROM public.course_faculty WHERE faculty_id = OLD.id)
       OR EXISTS (SELECT 1 FROM public.base_timetable WHERE faculty_id = OLD.id)
       OR EXISTS (SELECT 1 FROM public.lecture_sessions WHERE faculty_id = OLD.id OR covering_faculty_id = OLD.id) THEN
      RAISE EXCEPTION 'Cannot change role away from faculty while profile is still assigned to courses or lectures.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.guard_profile_privileged_fields() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_guard_profile_privileged_fields ON public.profiles;
CREATE TRIGGER trg_guard_profile_privileged_fields
BEFORE UPDATE ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.guard_profile_privileged_fields();

-- 4. Explicit Table & Column Privileges
-- Supabase's default grants give anon/authenticated ALL rights on every new table
-- (including TRUNCATE, TRIGGER, REFERENCES). Start from zero, then grant only what is needed.
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon, authenticated;

-- Reference metadata: read-only for authenticated users
GRANT SELECT ON public.cohorts, public.rooms, public.courses, public.course_cohorts, public.course_faculty TO authenticated;

-- Faculty directory view
GRANT SELECT ON public.profile_directory TO authenticated;

-- Profiles: read own/admin via RLS; update ONLY full_name
GRANT SELECT ON public.profiles TO authenticated;
GRANT UPDATE (full_name) ON public.profiles TO authenticated;

-- Base Timetable: SELECT/INSERT/UPDATE for assigned faculty & admin; DELETE gated to admin via RLS
GRANT SELECT, INSERT, UPDATE, DELETE ON public.base_timetable TO authenticated;

-- Base Timetable History: strictly append-only via database trigger
GRANT SELECT ON public.base_timetable_history TO authenticated;

-- Lecture Sessions: NO direct client UPDATE or DELETE (all updates MUST go through SECURITY DEFINER RPCs)
GRANT SELECT ON public.lecture_sessions TO authenticated;
GRANT INSERT ON public.lecture_sessions TO authenticated; -- Strictly gated to admin via RLS

-- Reschedule Polls: clients may insert open polls or update status (non-confirmed/non-superseded) & closes_at
GRANT SELECT, INSERT ON public.reschedule_polls TO authenticated;
GRANT UPDATE (status, closes_at) ON public.reschedule_polls TO authenticated;

-- Poll Options: NEVER grant client UPDATE on is_selected
GRANT SELECT, INSERT, DELETE ON public.poll_options TO authenticated;
GRANT UPDATE (proposed_date, proposed_start_time, proposed_end_time, proposed_room_id) ON public.poll_options TO authenticated;

-- Poll Votes: students/CRs insert or update ONLY option_id
GRANT SELECT, INSERT ON public.poll_votes TO authenticated;
GRANT UPDATE (option_id) ON public.poll_votes TO authenticated;

-- Change History: strictly append-only via database trigger
GRANT SELECT ON public.change_history TO authenticated;

-- Notifications: users can ONLY mark their own notifications as read
GRANT SELECT ON public.notifications TO authenticated;
GRANT UPDATE (is_read) ON public.notifications TO authenticated;

-- 5. Enable RLS on All Tables
ALTER TABLE public.cohorts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.courses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.course_cohorts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.course_faculty ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.base_timetable ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.base_timetable_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lecture_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reschedule_polls ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.poll_options ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.poll_votes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.change_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- 6. RLS Policies

-- Reference metadata
CREATE POLICY "read_cohorts" ON public.cohorts FOR SELECT TO authenticated USING (true);
CREATE POLICY "read_rooms" ON public.rooms FOR SELECT TO authenticated USING (true);
CREATE POLICY "read_courses" ON public.courses FOR SELECT TO authenticated USING (true);
CREATE POLICY "read_course_cohorts" ON public.course_cohorts FOR SELECT TO authenticated USING (true);
CREATE POLICY "read_course_faculty" ON public.course_faculty FOR SELECT TO authenticated USING (true);

-- PROFILES: Strictly own row or admin
CREATE POLICY "read_own_profile_or_admin" ON public.profiles
FOR SELECT TO authenticated
USING (id = auth.uid() OR public.current_user_role() = 'admin');

CREATE POLICY "update_own_safe_profile" ON public.profiles
FOR UPDATE TO authenticated
USING (id = auth.uid())
WITH CHECK (id = auth.uid());

-- BASE TIMETABLE: Strict B1/B2 separation for students (no ALL bypass for students)
CREATE POLICY "read_base_timetable_scoped" ON public.base_timetable
FOR SELECT TO authenticated
USING (
  public.current_user_role() = 'admin'
  OR (public.current_user_role() = 'faculty' AND faculty_id = auth.uid())
  OR (
    public.current_user_role() = 'cr'
    AND EXISTS (
      SELECT 1 FROM public.course_cohorts cc
      WHERE cc.course_id = base_timetable.course_id
        AND cc.cohort_id = public.current_user_cohort_id()
    )
  )
  OR (
    public.current_user_role() = 'student'
    AND (
      base_timetable.batch = 'ALL'
      OR base_timetable.batch = public.current_user_lab_batch()
    )
    AND EXISTS (
      SELECT 1 FROM public.course_cohorts cc
      WHERE cc.course_id = base_timetable.course_id
        AND cc.cohort_id = public.current_user_cohort_id()
    )
  )
);

-- Faculty may INSERT or UPDATE only for courses explicitly assigned to them (DELETE is admin-only)
CREATE POLICY "faculty_insert_own_assigned_base_timetable" ON public.base_timetable
FOR INSERT TO authenticated
WITH CHECK (
  public.current_user_role() = 'faculty'
  AND faculty_id = auth.uid()
  AND public.is_faculty_assigned_to_course(course_id, auth.uid())
);

CREATE POLICY "faculty_update_own_assigned_base_timetable" ON public.base_timetable
FOR UPDATE TO authenticated
USING (
  public.current_user_role() = 'faculty'
  AND faculty_id = auth.uid()
  AND public.is_faculty_assigned_to_course(course_id, auth.uid())
)
WITH CHECK (
  public.current_user_role() = 'faculty'
  AND faculty_id = auth.uid()
  AND public.is_faculty_assigned_to_course(course_id, auth.uid())
);

CREATE POLICY "admin_manage_base_timetable" ON public.base_timetable
FOR ALL TO authenticated
USING (public.current_user_role() = 'admin')
WITH CHECK (public.current_user_role() = 'admin');

-- BASE TIMETABLE HISTORY: Scoped identically to base_timetable
CREATE POLICY "read_base_timetable_history_scoped" ON public.base_timetable_history
FOR SELECT TO authenticated
USING (
  public.current_user_role() = 'admin'
  OR (
    public.current_user_role() = 'faculty'
    AND (
      faculty_id = auth.uid()
      OR public.is_faculty_assigned_to_course(course_id, auth.uid())
    )
  )
  OR (
    public.current_user_role() = 'cr'
    AND EXISTS (
      SELECT 1 FROM public.course_cohorts cc
      WHERE cc.course_id = base_timetable_history.course_id
        AND cc.cohort_id = public.current_user_cohort_id()
    )
  )
  OR (
    public.current_user_role() = 'student'
    AND (
      base_timetable_history.batch = 'ALL'
      OR base_timetable_history.batch = public.current_user_lab_batch()
    )
    AND EXISTS (
      SELECT 1 FROM public.course_cohorts cc
      WHERE cc.course_id = base_timetable_history.course_id
        AND cc.cohort_id = public.current_user_cohort_id()
    )
  )
);

-- LECTURE SESSIONS: Strict faculty privacy + strict B1/B2 student batch scoping + RPC-only updates
CREATE POLICY "read_sessions_scoped" ON public.lecture_sessions
FOR SELECT TO authenticated
USING (
  public.current_user_role() = 'admin'
  OR (
    public.current_user_role() = 'faculty'
    AND (
      faculty_id = auth.uid()
      OR covering_faculty_id = auth.uid()
      OR is_open_for_coverage IS TRUE
    )
  )
  OR (
    public.current_user_role() = 'cr'
    AND EXISTS (
      SELECT 1 FROM public.course_cohorts cc
      WHERE cc.course_id = lecture_sessions.course_id
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
      WHERE cc.course_id = lecture_sessions.course_id
        AND cc.cohort_id = public.current_user_cohort_id()
    )
  )
);

CREATE POLICY "admin_insert_sessions" ON public.lecture_sessions
FOR INSERT TO authenticated
WITH CHECK (public.current_user_role() = 'admin');

-- RESCHEDULE POLLS: One open poll per session; CR/faculty may open or mark cancelled_fallback
CREATE POLICY "read_polls_scoped" ON public.reschedule_polls
FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.lecture_sessions ls
    WHERE ls.id = reschedule_polls.lecture_session_id
  )
);

CREATE POLICY "cr_faculty_create_scoped_polls" ON public.reschedule_polls
FOR INSERT TO authenticated
WITH CHECK (
  created_by = auth.uid()
  AND status = 'open'
  AND closes_at > NOW()
  AND public.can_manage_session_poll(lecture_session_id)
);

CREATE POLICY "owner_faculty_admin_update_open_polls" ON public.reschedule_polls
FOR UPDATE TO authenticated
USING (
  status = 'open'
  AND (
    public.current_user_role() = 'admin'
    OR (
      public.can_manage_session_poll(lecture_session_id)
      AND (
        created_by = auth.uid()
        OR (
          public.current_user_role() = 'faculty'
          AND EXISTS (
            SELECT 1 FROM public.lecture_sessions ls
            WHERE ls.id = reschedule_polls.lecture_session_id
              AND (ls.faculty_id = auth.uid() OR ls.covering_faculty_id = auth.uid())
          )
        )
      )
    )
  )
)
WITH CHECK (
  (
    status = 'cancelled_fallback'
    OR (status = 'open' AND closes_at > NOW())
  )
  AND (
    public.current_user_role() = 'admin'
    OR (
      public.can_manage_session_poll(lecture_session_id)
      AND (
        created_by = auth.uid()
        OR (
          public.current_user_role() = 'faculty'
          AND EXISTS (
            SELECT 1 FROM public.lecture_sessions ls
            WHERE ls.id = reschedule_polls.lecture_session_id
              AND (ls.faculty_id = auth.uid() OR ls.covering_faculty_id = auth.uid())
          )
        )
      )
    )
  )
);

-- POLL OPTIONS: Editable only while parent poll is open & unexpired; is_selected must stay FALSE
CREATE POLICY "read_poll_options_scoped" ON public.poll_options
FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.reschedule_polls rp
    WHERE rp.id = poll_options.poll_id
  )
);

CREATE POLICY "manage_open_poll_options_scoped" ON public.poll_options
FOR ALL TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.reschedule_polls rp
    WHERE rp.id = poll_options.poll_id
      AND rp.status = 'open'
      AND rp.closes_at > NOW()
      AND (
        public.current_user_role() = 'admin'
        OR (
          public.can_manage_session_poll(rp.lecture_session_id)
          AND (
            rp.created_by = auth.uid()
            OR (
              public.current_user_role() = 'faculty'
              AND EXISTS (
                SELECT 1 FROM public.lecture_sessions ls
                WHERE ls.id = rp.lecture_session_id
                  AND (ls.faculty_id = auth.uid() OR ls.covering_faculty_id = auth.uid())
              )
            )
          )
        )
      )
  )
)
WITH CHECK (
  is_selected IS FALSE
  AND EXISTS (
    SELECT 1
    FROM public.reschedule_polls rp
    WHERE rp.id = poll_options.poll_id
      AND rp.status = 'open'
      AND rp.closes_at > NOW()
      AND (
        public.current_user_role() = 'admin'
        OR (
          public.can_manage_session_poll(rp.lecture_session_id)
          AND (
            rp.created_by = auth.uid()
            OR (
              public.current_user_role() = 'faculty'
              AND EXISTS (
                SELECT 1 FROM public.lecture_sessions ls
                WHERE ls.id = rp.lecture_session_id
                  AND (ls.faculty_id = auth.uid() OR ls.covering_faculty_id = auth.uid())
              )
            )
          )
        )
      )
  )
);

-- POLL VOTES: Strict voter privacy & strict B1/B2 student batch scoping
CREATE POLICY "read_own_poll_vote_or_admin" ON public.poll_votes
FOR SELECT TO authenticated
USING (student_id = auth.uid() OR public.current_user_role() = 'admin');

CREATE POLICY "cohort_student_cr_insert_vote" ON public.poll_votes
FOR INSERT TO authenticated
WITH CHECK (
  student_id = auth.uid()
  AND public.current_user_role() IN ('student', 'cr')
  AND EXISTS (
    SELECT 1
    FROM public.reschedule_polls rp
    JOIN public.poll_options po ON po.poll_id = rp.id AND po.id = poll_votes.option_id
    JOIN public.lecture_sessions ls ON ls.id = rp.lecture_session_id
    JOIN public.course_cohorts cc ON cc.course_id = ls.course_id
    WHERE rp.id = poll_votes.poll_id
      AND rp.status = 'open'
      AND rp.closes_at > NOW()
      AND cc.cohort_id = public.current_user_cohort_id()
      AND (
        public.current_user_role() = 'cr'
        OR ls.batch = 'ALL'
        OR ls.batch = public.current_user_lab_batch()
      )
  )
);

CREATE POLICY "cohort_student_cr_update_vote" ON public.poll_votes
FOR UPDATE TO authenticated
USING (
  student_id = auth.uid()
  AND public.current_user_role() IN ('student', 'cr')
  AND EXISTS (
    SELECT 1
    FROM public.reschedule_polls rp
    WHERE rp.id = poll_votes.poll_id
      AND rp.status = 'open'
      AND rp.closes_at > NOW()
  )
)
WITH CHECK (
  student_id = auth.uid()
  AND public.current_user_role() IN ('student', 'cr')
  AND EXISTS (
    SELECT 1
    FROM public.reschedule_polls rp
    JOIN public.poll_options po ON po.poll_id = rp.id AND po.id = poll_votes.option_id
    JOIN public.lecture_sessions ls ON ls.id = rp.lecture_session_id
    JOIN public.course_cohorts cc ON cc.course_id = ls.course_id
    WHERE rp.id = poll_votes.poll_id
      AND rp.status = 'open'
      AND rp.closes_at > NOW()
      AND cc.cohort_id = public.current_user_cohort_id()
      AND (
        public.current_user_role() = 'cr'
        OR ls.batch = 'ALL'
        OR ls.batch = public.current_user_lab_batch()
      )
  )
);

-- CHANGE HISTORY: Scoped via visible lecture_sessions
CREATE POLICY "read_history_scoped" ON public.change_history
FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.lecture_sessions ls
    WHERE ls.id = change_history.lecture_session_id
  )
);

-- NOTIFICATIONS: Strictly private to recipient
CREATE POLICY "read_own_notifications" ON public.notifications
FOR SELECT TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "mark_own_notifications_read" ON public.notifications
FOR UPDATE TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());