-- supabase/seed.sql
-- ClassCue by KYUJUSAN 93 — Real MSc IDS Sem VII & Sem IX Timetable Seed (Term I, Version 8, effective 25 Sep 2026)
-- Safe to re-run: every insert skips rows that already exist.

BEGIN;
SET LOCAL classcue.suppress_bt_notif = 'true';

DO $$
DECLARE
  v_missing TEXT;
BEGIN
  IF to_regprocedure('public.generate_lecture_sessions(date,date)') IS NULL THEN
    RAISE EXCEPTION 'Migration 004 has not been run on this project yet. Run 001 to 004 first.';
  END IF;

  SELECT string_agg(v.email, ', ' ORDER BY v.email) INTO v_missing
  FROM (VALUES
    ('admin@classcue.app'),
    ('cr.sem7@classcue.app'),
    ('student.b1@classcue.app'),
    ('student.b2@classcue.app'),
    ('student.sem9@classcue.app'),
    ('dnyandev@classcue.app'),
    ('tanmay@classcue.app'),
    ('teja@classcue.app'),
    ('venkatesh@classcue.app'),
    ('madhusudhan@classcue.app'),
    ('saurabh@classcue.app'),
    ('shaunak@classcue.app'),
    ('amogh@classcue.app')
  ) AS v(email)
  WHERE NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.email = v.email);

  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'Missing Auth accounts. Create these in Authentication -> Users first: %', v_missing;
  END IF;
END
$$;

-- 1. Cohorts
INSERT INTO public.cohorts (name, program, semester) VALUES
  ('MSc IDS Sem VII', 'MSc Integrated Data Science', 7),
  ('MSc IDS Sem IX',  'MSc Integrated Data Science', 9)
ON CONFLICT (name) DO NOTHING;

-- 2. Profiles (satisfies chk_profile_role_batch_cohort)
INSERT INTO public.profiles (id, full_name, email, role, cohort_id, lab_batch, faculty_type, faculty_code)
SELECT
  u.id,
  v.full_name,
  u.email,
  v.role,
  c.id,
  v.lab_batch,
  v.faculty_type,
  v.faculty_code
FROM (VALUES
  ('admin@classcue.app',       'GBS Programme Admin',      'admin',   NULL::text,        'ALL', NULL::text,     NULL::text),
  ('cr.sem7@classcue.app',     'Meera Desai',              'cr',      'MSc IDS Sem VII', 'ALL', NULL,           NULL),
  ('student.b1@classcue.app',  'Aarav Naik',               'student', 'MSc IDS Sem VII', 'B1',  NULL,           NULL),
  ('student.b2@classcue.app',  'Priya Naik',               'student', 'MSc IDS Sem VII', 'B2',  NULL,           NULL),
  ('student.sem9@classcue.app','Nisha Kamat',              'student', 'MSc IDS Sem IX',  'B1',  NULL,           NULL),
  ('dnyandev@classcue.app',    'Mr. Dnyandev Khadapkar',   'faculty', NULL,              'ALL', 'permanent',    'DK'),
  ('tanmay@classcue.app',      'Mr. Tanmay Parab',         'faculty', NULL,              'ALL', 'permanent',    'TN'),
  ('teja@classcue.app',        'Dr. Teja Khandolkar',      'faculty', NULL,              'ALL', 'permanent',    'TK'),
  ('venkatesh@classcue.app',   'Mr. Venkatesh Prabhu',     'faculty', NULL,              'ALL', 'visiting',     'VP'),
  ('madhusudhan@classcue.app', 'Dr. Madhusudhan Lanjewar', 'faculty', NULL,              'ALL', 'contributory', 'ML'),
  ('saurabh@classcue.app',     'Mr. Saurabh Borkar',       'faculty', NULL,              'ALL', 'visiting',     'SB'),
  ('shaunak@classcue.app',     'Mr. Shaunak Perni',        'faculty', NULL,              'ALL', 'visiting',     'SP'),
  ('amogh@classcue.app',       'Mr. Amogh Parwatkar',      'faculty', NULL,              'ALL', 'visiting',     'AP')
) AS v(email, full_name, role, cohort_name, lab_batch, faculty_type, faculty_code)
JOIN auth.users u ON u.email = v.email
LEFT JOIN public.cohorts c ON c.name = v.cohort_name
ON CONFLICT (id) DO NOTHING;

-- 3. Rooms
INSERT INTO public.rooms (room_number, building, is_lab, capacity) VALUES
  ('FF13', 'GBS', true,  40),
  ('FF11', 'GBS', true,  40),
  ('FF5',  'GBS', false, 30),
  ('FF4',  'GBS', false, 40),
  ('GF11', 'GBS', false, 40),
  ('CF9',  'GBS', true,  30),
  ('FF41', 'GBS', false, 40)
ON CONFLICT (room_number) DO NOTHING;

-- 4. Courses
INSERT INTO public.courses (code, name, is_elective) VALUES
  ('IMC-701', 'AI - Search Methods and Problem Solving',             false),
  ('IMC-702', 'Research Methodology and IP',                         false),
  ('IMC-703', 'Deep Learning',                                       false),
  ('IMC-704', 'Design Thinking for Data Driven App Development',     false),
  ('IMC-716', 'Internet of Things (IoT)',                            true),
  ('IMC-717', 'Numerical Methods',                                   false),
  ('IMC-911', 'Sequential Decision Making',                          false),
  ('IMC-611', 'Cloud Computing',                                     false)
ON CONFLICT (code) DO NOTHING;

-- 5. Course-to-cohort mapping (must precede base_timetable; IMC-716 IoT is shared by Sem VII + Sem IX)
INSERT INTO public.course_cohorts (course_id, cohort_id)
SELECT c.id, co.id
FROM (VALUES
  ('IMC-701', 'MSc IDS Sem VII'),
  ('IMC-702', 'MSc IDS Sem VII'),
  ('IMC-703', 'MSc IDS Sem VII'),
  ('IMC-704', 'MSc IDS Sem VII'),
  ('IMC-716', 'MSc IDS Sem VII'),
  ('IMC-716', 'MSc IDS Sem IX'),
  ('IMC-717', 'MSc IDS Sem IX'),
  ('IMC-911', 'MSc IDS Sem IX'),
  ('IMC-611', 'MSc IDS Sem IX')
) AS v(course_code, cohort_name)
JOIN public.courses c ON c.code = v.course_code
JOIN public.cohorts co ON co.name = v.cohort_name
ON CONFLICT DO NOTHING;

-- 6. Primary faculty per course
INSERT INTO public.course_faculty (course_id, faculty_id, is_primary)
SELECT c.id, p.id, TRUE
FROM (VALUES
  ('IMC-701', 'tanmay@classcue.app'),
  ('IMC-702', 'teja@classcue.app'),
  ('IMC-703', 'dnyandev@classcue.app'),
  ('IMC-704', 'venkatesh@classcue.app'),
  ('IMC-716', 'madhusudhan@classcue.app'),
  ('IMC-717', 'saurabh@classcue.app'),
  ('IMC-911', 'shaunak@classcue.app'),
  ('IMC-611', 'amogh@classcue.app')
) AS v(course_code, email)
JOIN public.courses c ON c.code = v.course_code
JOIN public.profiles p ON p.email = v.email
ON CONFLICT DO NOTHING;

-- 7. Weekly base timetable (25 slots)
INSERT INTO public.base_timetable (
  course_id, faculty_id, room_id, day_of_week, start_time, end_time, batch, session_type, effective_from
)
SELECT
  c.id,
  p.id,
  r.id,
  v.dow,
  v.st::TIME,
  v.et::TIME,
  v.batch,
  v.stype,
  DATE '2026-09-25'
FROM (VALUES
  (1, '10:30', '12:30', 'IMC-704', 'venkatesh@classcue.app',   'FF13', 'ALL', 'theory'),
  (1, '13:30', '17:30', 'IMC-703', 'dnyandev@classcue.app',    'FF13', 'B2',  'practical'),
  (1, '13:30', '17:30', 'IMC-701', 'tanmay@classcue.app',      'FF11', 'B1',  'practical'),
  (1, '10:30', '12:30', 'IMC-911', 'shaunak@classcue.app',     'FF5',  'ALL', 'theory'),
  (2, '10:30', '12:30', 'IMC-704', 'venkatesh@classcue.app',   'FF13', 'ALL', 'theory'),
  (2, '13:30', '17:30', 'IMC-703', 'dnyandev@classcue.app',    'FF13', 'B1',  'practical'),
  (2, '13:30', '17:30', 'IMC-701', 'tanmay@classcue.app',      'FF11', 'B2',  'practical'),
  (2, '10:30', '13:30', 'IMC-611', 'amogh@classcue.app',       'FF5',  'ALL', 'theory'),
  (2, '14:30', '16:30', 'IMC-717', 'saurabh@classcue.app',     'FF5',  'ALL', 'theory'),
  (3, '10:30', '12:30', 'IMC-716', 'madhusudhan@classcue.app', 'FF13', 'ALL', 'theory'),
  (3, '13:30', '15:30', 'IMC-701', 'tanmay@classcue.app',      'FF13', 'ALL', 'theory'),
  (3, '15:30', '17:30', 'IMC-702', 'teja@classcue.app',        'FF13', 'ALL', 'theory'),
  (3, '13:30', '15:30', 'IMC-911', 'shaunak@classcue.app',     'FF5',  'ALL', 'theory'),
  (3, '15:30', '17:30', 'IMC-717', 'saurabh@classcue.app',     'FF5',  'ALL', 'theory'),
  (4, '10:30', '12:30', 'IMC-703', 'dnyandev@classcue.app',    'FF13', 'ALL', 'theory'),
  (4, '13:30', '15:30', 'IMC-704', 'venkatesh@classcue.app',   'FF13', 'ALL', 'theory'),
  (4, '15:30', '17:30', 'IMC-702', 'teja@classcue.app',        'FF13', 'ALL', 'theory'),
  (4, '09:30', '11:30', 'IMC-911', 'shaunak@classcue.app',     'FF5',  'ALL', 'theory'),
  (4, '15:30', '17:30', 'IMC-717', 'saurabh@classcue.app',     'FF5',  'ALL', 'theory'),
  (5, '10:00', '12:00', 'IMC-716', 'madhusudhan@classcue.app', 'FF13', 'ALL', 'theory'),
  (5, '12:00', '13:00', 'IMC-701', 'tanmay@classcue.app',      'FF13', 'ALL', 'theory'),
  (5, '14:00', '15:00', 'IMC-701', 'tanmay@classcue.app',      'FF13', 'ALL', 'theory'),
  (5, '15:00', '17:00', 'IMC-703', 'dnyandev@classcue.app',    'FF13', 'ALL', 'theory'),
  (5, '12:00', '13:00', 'IMC-611', 'amogh@classcue.app',       'FF5',  'ALL', 'theory'),
  (5, '14:00', '16:00', 'IMC-611', 'amogh@classcue.app',       'FF5',  'ALL', 'theory')
) AS v(dow, st, et, course_code, email, room_num, batch, stype)
JOIN public.courses c ON c.code = v.course_code
JOIN public.profiles p ON p.email = v.email
JOIN public.rooms r ON r.room_number = v.room_num
WHERE NOT EXISTS (
  SELECT 1 FROM public.base_timetable bt
  WHERE bt.course_id = c.id
    AND bt.day_of_week = v.dow
    AND bt.start_time = v.st::TIME
    AND bt.batch = v.batch
    AND bt.effective_from = DATE '2026-09-25'
);

-- 8. Generate 3 weeks of dated sessions from Monday of the current IST week
SELECT public.generate_lecture_sessions(
  date_trunc('week', public.today_ist()::timestamp)::date,
  date_trunc('week', public.today_ist()::timestamp)::date + 20
) AS sessions_generated;

COMMIT;

-- 9. Summary: expect 2 | 13 | 7 | 8 | 25 | 75 on a fresh project
SELECT
  (SELECT count(*) FROM public.cohorts) AS cohorts,
  (SELECT count(*) FROM public.profiles) AS profiles,
  (SELECT count(*) FROM public.rooms) AS rooms,
  (SELECT count(*) FROM public.courses) AS courses,
  (SELECT count(*) FROM public.base_timetable) AS weekly_slots,
  (SELECT count(*) FROM public.lecture_sessions) AS dated_sessions;