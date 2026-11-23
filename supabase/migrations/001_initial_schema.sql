-- 001_initial_schema.sql
-- ClassCue by KYUJUSAN 93 — Hardened Core Schema (v3.1)

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Campus clock: Supabase runs in UTC, the campus runs in IST (UTC+05:30).
-- Every "is this date in the past?" check and the base_timetable default use this.
CREATE OR REPLACE FUNCTION public.today_ist()
RETURNS DATE
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT (NOW() AT TIME ZONE 'Asia/Kolkata')::DATE;
$$;

-- 1. Academic Cohorts (e.g., MSc IDS Sem VII, Sem IX)
CREATE TABLE public.cohorts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT UNIQUE NOT NULL,
  program TEXT NOT NULL,
  semester INT NOT NULL CHECK (semester BETWEEN 1 AND 12)
);

-- 2. User Profiles linked to Supabase Auth
-- Students MUST be explicitly assigned B1 or B2; ALL is reserved for cr, faculty, and admin
CREATE TABLE public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT NOT NULL,
  email TEXT UNIQUE NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('student', 'cr', 'faculty', 'admin')),
  cohort_id UUID REFERENCES public.cohorts(id),
  lab_batch TEXT NOT NULL CHECK (lab_batch IN ('ALL', 'B1', 'B2')),
  faculty_type TEXT CHECK (faculty_type IN ('permanent', 'visiting', 'contributory')),
  faculty_code TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_profile_role_batch_cohort CHECK (
    (role = 'student' AND lab_batch IN ('B1', 'B2') AND cohort_id IS NOT NULL AND faculty_type IS NULL)
    OR (role = 'cr' AND lab_batch = 'ALL' AND cohort_id IS NOT NULL AND faculty_type IS NULL)
    OR (role = 'faculty' AND lab_batch = 'ALL' AND cohort_id IS NULL)
    OR (role = 'admin' AND lab_batch = 'ALL')
  )
);

-- 3. Classrooms & Labs
CREATE TABLE public.rooms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_number TEXT UNIQUE NOT NULL,
  building TEXT NOT NULL DEFAULT 'GBS',
  is_lab BOOLEAN NOT NULL DEFAULT FALSE,
  capacity INT NOT NULL DEFAULT 40 CHECK (capacity > 0)
);

-- 4. Courses & Normalized Assignments (course_faculty is the sole source of truth for primary faculty)
CREATE TABLE public.courses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  is_elective BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE public.course_cohorts (
  course_id UUID REFERENCES public.courses(id) ON DELETE CASCADE,
  cohort_id UUID REFERENCES public.cohorts(id) ON DELETE CASCADE,
  PRIMARY KEY (course_id, cohort_id)
);

CREATE TABLE public.course_faculty (
  course_id UUID REFERENCES public.courses(id) ON DELETE CASCADE,
  faculty_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  is_primary BOOLEAN NOT NULL DEFAULT FALSE,
  PRIMARY KEY (course_id, faculty_id)
);

CREATE UNIQUE INDEX uq_one_primary_faculty_per_course
  ON public.course_faculty (course_id)
  WHERE is_primary IS TRUE;

-- 5. Predefined Weekly Base Timetable (handles Permanent Changes)
CREATE TABLE public.base_timetable (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  course_id UUID REFERENCES public.courses(id) ON DELETE CASCADE NOT NULL,
  faculty_id UUID REFERENCES public.profiles(id) NOT NULL,
  room_id UUID REFERENCES public.rooms(id) NOT NULL,
  day_of_week INT NOT NULL CHECK (day_of_week BETWEEN 1 AND 6), -- 1=Mon..6=Sat
  start_time TIME NOT NULL,
  end_time TIME NOT NULL,
  batch TEXT NOT NULL DEFAULT 'ALL' CHECK (batch IN ('ALL', 'B1', 'B2')),
  session_type TEXT NOT NULL DEFAULT 'theory' CHECK (session_type IN ('theory', 'practical', 'mentoring')),
  effective_from DATE NOT NULL DEFAULT public.today_ist(),
  effective_to DATE,
  CONSTRAINT chk_base_timetable_time_range CHECK (end_time > start_time),
  CONSTRAINT chk_base_timetable_effective_range CHECK (effective_to IS NULL OR effective_to >= effective_from)
);

-- 6. Audit Log for Base Timetable Mutations (Preserves trail even if a split row is deleted on undo)
-- created_at uses clock_timestamp() (not NOW()) so rows are ordered by real insertion time,
-- which the undo "was this modified again?" check relies on.
CREATE TABLE public.base_timetable_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  base_timetable_id UUID REFERENCES public.base_timetable(id) ON DELETE SET NULL,
  target_base_timetable_id UUID NOT NULL,
  course_id UUID REFERENCES public.courses(id) ON DELETE CASCADE NOT NULL,
  faculty_id UUID REFERENCES public.profiles(id) NOT NULL,
  batch TEXT NOT NULL CHECK (batch IN ('ALL', 'B1', 'B2')),
  changed_by UUID REFERENCES public.profiles(id),
  action_type TEXT NOT NULL CHECK (action_type IN ('insert', 'update', 'delete', 'undo')),
  previous_state JSONB,
  new_state JSONB,
  reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);

-- 7. Concrete Dated Lecture Sessions (handles Temporary/Permanent Status & Optimistic Version)
CREATE TABLE public.lecture_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  base_timetable_id UUID REFERENCES public.base_timetable(id) ON DELETE SET NULL,
  course_id UUID REFERENCES public.courses(id) ON DELETE CASCADE NOT NULL,
  faculty_id UUID REFERENCES public.profiles(id) NOT NULL,
  covering_faculty_id UUID REFERENCES public.profiles(id),
  room_id UUID REFERENCES public.rooms(id) NOT NULL,

  session_date DATE NOT NULL,
  start_time TIME NOT NULL,
  end_time TIME NOT NULL,
  batch TEXT NOT NULL DEFAULT 'ALL' CHECK (batch IN ('ALL', 'B1', 'B2')),

  -- All-or-none original-slot snapshot for Original vs Updated UI
  original_date DATE,
  original_start_time TIME,
  original_end_time TIME,
  original_room_id UUID REFERENCES public.rooms(id),

  status TEXT NOT NULL DEFAULT 'scheduled'
    CHECK (status IN ('scheduled', 'cancelled', 'rescheduling_pending', 'rescheduled', 'covered')),
  change_scope TEXT NOT NULL DEFAULT 'temporary'
    CHECK (change_scope IN ('temporary', 'permanent')),
  reason TEXT,
  is_open_for_coverage BOOLEAN NOT NULL DEFAULT FALSE,
  version INT NOT NULL DEFAULT 1 CHECK (version >= 1),
  updated_by UUID REFERENCES public.profiles(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_lecture_session_time_range CHECK (end_time > start_time),
  CONSTRAINT chk_lecture_session_original_snapshot CHECK (
    (
      original_date IS NULL
      AND original_start_time IS NULL
      AND original_end_time IS NULL
      AND original_room_id IS NULL
    )
    OR (
      original_date IS NOT NULL
      AND original_start_time IS NOT NULL
      AND original_end_time IS NOT NULL
      AND original_room_id IS NOT NULL
      AND original_end_time > original_start_time
    )
  ),
  CONSTRAINT chk_covered_requires_covering_faculty CHECK (
    status <> 'covered' OR covering_faculty_id IS NOT NULL
  ),
  CONSTRAINT chk_covering_not_same_as_primary CHECK (
    covering_faculty_id IS NULL OR covering_faculty_id <> faculty_id
  )
);

-- 8. CR / Faculty Reschedule Polls (At most ONE open poll per session + version binding)
CREATE TABLE public.reschedule_polls (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lecture_session_id UUID REFERENCES public.lecture_sessions(id) ON DELETE CASCADE NOT NULL,
  created_by UUID REFERENCES public.profiles(id) NOT NULL,
  expected_session_version INT NOT NULL DEFAULT 1 CHECK (expected_session_version >= 1),
  status TEXT NOT NULL DEFAULT 'open'
    CHECK (status IN ('open', 'confirmed', 'cancelled_fallback', 'superseded')),
  closes_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX uq_one_open_poll_per_session
  ON public.reschedule_polls (lecture_session_id)
  WHERE status = 'open';

CREATE TABLE public.poll_options (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  poll_id UUID REFERENCES public.reschedule_polls(id) ON DELETE CASCADE NOT NULL,
  proposed_date DATE NOT NULL,
  proposed_start_time TIME NOT NULL,
  proposed_end_time TIME NOT NULL,
  proposed_room_id UUID REFERENCES public.rooms(id),
  is_selected BOOLEAN NOT NULL DEFAULT FALSE,
  CONSTRAINT uq_poll_options_poll_id_id UNIQUE (poll_id, id),
  CONSTRAINT chk_poll_option_time_range CHECK (proposed_end_time > proposed_start_time)
);

CREATE TABLE public.poll_votes (
  poll_id UUID NOT NULL,
  option_id UUID NOT NULL,
  student_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  voted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (poll_id, student_id),
  CONSTRAINT fk_poll_votes_poll_option
    FOREIGN KEY (poll_id, option_id)
    REFERENCES public.poll_options (poll_id, id)
    ON DELETE CASCADE
);

-- 9. Timetable Change History & Atomic Undo Snapshots (including base_timetable & poll side effects)
CREATE TABLE public.change_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lecture_session_id UUID REFERENCES public.lecture_sessions(id) ON DELETE CASCADE NOT NULL,
  changed_by UUID REFERENCES public.profiles(id) NOT NULL,
  action_type TEXT NOT NULL
    CHECK (action_type IN ('cancel', 'reschedule', 'room_change', 'cover_opt_in', 'permanent_update', 'status_update', 'undo')),
  previous_state JSONB NOT NULL,
  new_state JSONB NOT NULL,
  side_effects JSONB,
  reason TEXT,
  reverts_history_id UUID UNIQUE REFERENCES public.change_history(id),
  undone_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);

-- 10. Notifications Feed
CREATE TABLE public.notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  lecture_session_id UUID REFERENCES public.lecture_sessions(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  type TEXT NOT NULL
    CHECK (type IN ('cancellation', 'reschedule', 'room_change', 'poll', 'coverage_open', 'reminder')),
  is_read BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Performance Indexes
CREATE INDEX idx_profiles_cohort ON public.profiles(cohort_id);
CREATE INDEX idx_course_cohorts_cohort ON public.course_cohorts(cohort_id, course_id);
CREATE INDEX idx_course_faculty_faculty ON public.course_faculty(faculty_id, course_id);
CREATE INDEX idx_base_timetable_day_faculty ON public.base_timetable(day_of_week, faculty_id);
CREATE INDEX idx_base_timetable_day_room ON public.base_timetable(day_of_week, room_id);
CREATE INDEX idx_base_timetable_course ON public.base_timetable(course_id);
CREATE INDEX idx_base_timetable_history_target ON public.base_timetable_history(target_base_timetable_id, created_at DESC);
CREATE INDEX idx_sessions_date_status ON public.lecture_sessions(session_date, status);
CREATE INDEX idx_sessions_faculty_date ON public.lecture_sessions(faculty_id, session_date);
CREATE INDEX idx_sessions_covering_date ON public.lecture_sessions(covering_faculty_id, session_date);
CREATE INDEX idx_sessions_room_date ON public.lecture_sessions(room_id, session_date);
CREATE INDEX idx_sessions_base_date ON public.lecture_sessions(base_timetable_id, session_date);
CREATE INDEX idx_sessions_course_date ON public.lecture_sessions(course_id, session_date);
CREATE INDEX idx_polls_session ON public.reschedule_polls(lecture_session_id);
CREATE INDEX idx_poll_votes_option ON public.poll_votes(poll_id, option_id);
CREATE INDEX idx_history_session_created ON public.change_history(lecture_session_id, created_at DESC);
CREATE INDEX idx_notifications_user_read ON public.notifications(user_id, is_read, created_at DESC);
CREATE INDEX idx_notifications_session ON public.notifications(lecture_session_id);

-- Idempotent Realtime Publication Registration
-- Includes base_timetable for live permanent edits; omits poll_votes to preserve voter privacy
DO $$
DECLARE
  v_table TEXT;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    FOREACH v_table IN ARRAY ARRAY['base_timetable', 'lecture_sessions', 'notifications', 'reschedule_polls']
    LOOP
      IF NOT EXISTS (
        SELECT 1
        FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND schemaname = 'public'
          AND tablename = v_table
      ) THEN
        EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', v_table);
      END IF;
    END LOOP;
  END IF;
END
$$;