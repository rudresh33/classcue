# ClassCue — by KYUJUSAN 93

**Real-time lecture status, conflict-free rescheduling, faculty coverage opt-in, and anonymous replacement-slot polling for Goa Business School, Goa University.**

> Built for **IMC-704: Design Thinking for Data-Driven App Development** (MSc Integrated Data Science, Goa Business School, Goa University).

---

## 1. Problem Statement & How Might We (HMW)

### Problem Statement
Commuting students, Class Representatives (CRs), and permanent/visiting/contributory faculty at Goa Business School currently rely on fragmented WhatsApp forwards and ad-hoc verbal messages whenever a lecture is cancelled, moved to another room, split across B1/B2 lab batches, or rescheduled. Students frequently commute to campus for cancelled lectures, CRs spend hours manually collecting poll preferences across noisy chat groups, and faculty risk double-booking classrooms, cohorts, or shared cross-semester electives (such as `IMC-716 Internet of Things`).

### How Might We (HMW) Question
> *How might we provide Goa Business School students, CRs, and faculty with a single, privacy-preserving, conflict-free source of truth for real-time lecture status and rescheduling—eliminating wasted commutes and informal WhatsApp chaos?*

---

## 2. EDIPT Design Thinking Traceability (Paper Prototype v1.0 → App v1.1)

| EDIPT / Nielsen Heuristic | Paper Prototype v1.0 Testing Feedback | ClassCue v1.1 Implementation |
| --- | --- | --- |
| **Visibility of System Status (Nielsen #1)** — *Aarav & Nisha (Commuter Personas)* | Commuters needed immediate clarity at the top of the screen before leaving home, plus clear distinction between original and updated timings/rooms. | **Today's Commute Snapshot** card on Student/CR home; color-coded semantic chips (`Scheduled`, `Cancelled`, `Rescheduling Pending`, `Rescheduled`, `Covered`); strikethrough original date/time/room beside highlighted new slot; `Temporary` vs `Permanent` and `Room Changed` pills; `B1`/`B2` and `Shared · Sem VII & IX` badges. |
| **Error Prevention (Nielsen #5)** — *Prototype User 2* | One-tap toggles on faculty cards caused accidental cancellations/notifications. | Zero direct toggles on cards. Tapping opens a structured **Update / Reschedule Bottom Sheet** with live `check_slot_conflicts` verification (Cohort, Faculty, Room + tappable Free Room chips) and a mandatory **Pre-Publish Confirmation Dialog**. |
| **User Control & Freedom (Nielsen #3)** — *Prototype User 6* | Faculty wanted an immediate way to revert mistakes after notifying students. | Immediate **Undo Snackbar** right after publishing + **Undo Last Change** action in Lecture Details backed by atomic `undo_last_lecture_change()` (reverts session, permanent `base_timetable` splits, shifted future sessions, and poll confirmations). |
| **Recognition Rather Than Recall (Nielsen #6)** — *Faculty Interviews* | Visiting and permanent faculty feared forgetting unusual rescheduled or covered lecture slots. | Pinned **Non-Routine Lecture Reminder** banner at the top of the Faculty dashboard surfacing upcoming `rescheduled`, `covered`, or room-changed classes in the next 48 hours. |
| **Match with Real World & Privacy Boundaries (Nielsen #2)** — *CR & Faculty Personas* | Faculty insisted private calendars stay hidden; CRs wanted structured voting instead of chaotic chats, with a fallback if no slot works. | Strict RLS scoping (`profile_directory` view exposes only faculty names/codes), anonymous majority voting via `get_poll_results()`, explicit `Cancelled (Fallback)` closure, and faculty-only confirmation via `confirm_poll_option()`. |

---

## 3. System Architecture & Backend Highlights

- **Frontend:** Mobile-first **Flutter** (Material 3, `provider`, `go_router`, `supabase_flutter`, `intl`) developed locally in Chrome Web (with a centered 480px mobile preview shell on viewports > 520px and edge-to-edge layout on mobile) and packaged as an Android APK via GitHub Actions.
- **Backend:** **Supabase PostgreSQL 16**
  - Production project `classcue` — Oceania (Sydney, `ap-southeast-2`)
  - Sandbox project `test` — Northeast Asia (Tokyo, `ap-northeast-1`)
- **Database Hardening & Concurrency:**
  - **14 RLS-protected tables** + `profile_directory` view, **25 RLS policies**, **16 triggers**, and **8 `SECURITY DEFINER` RPCs**.
  - **Least-privilege column grants:** Direct client `UPDATE`/`DELETE` on `lecture_sessions` is revoked; `profiles` allows updating only `full_name`; `notifications` allows updating only `is_read`; `poll_votes` uses strict `.insert()` / `.update({'option_id': ...})` (never `.upsert()`).
  - **Strict B1/B2 Lab Batch Separation:** Students only see `ALL` or their exact `lab_batch` (`B1` or `B2`) across timetables, sessions, polls, and notifications.
  - **Unified Advisory Lock (`pg_advisory_xact_lock(704000, 1)`):** Eliminates race conditions and deadlocks across `base_timetable`, `lecture_sessions`, permanent updates, coverage opt-ins, poll confirmations, and atomic undos.
  - **Campus IST Clock (`Asia/Kolkata`, `UTC+05:30`):** Consistent past-date validation and IST timestamp formatting.
  - **Live Realtime Sync:** Subscribed to `lecture_sessions`, `notifications`, `reschedule_polls`, and `base_timetable`.

---

## 4. Teammate Setup Guide (Web-Only: VS Code + Chrome)

> Quick-start guide for **Mohal** & **Omkar** (no Android emulator required for local development).

1. **Clone the repository and switch to `dev`:**
   ```bash
   git clone <REPO_URL>
   cd classcue
   git checkout dev
   ```
2. **Create your local `env.json` (NEVER commit this file):**
   ```bash
   cp env.json.example env.json
   ```
   Open `env.json` and paste the team's `SUPABASE_URL` and `SUPABASE_ANON_KEY` (shared privately—never push credentials to Git).
3. **Install Flutter packages:**
   ```bash
   flutter pub get
   ```
4. **Launch ClassCue locally in Chrome:**
   ```bash
   flutter run -d chrome --dart-define-from-file=env.json
   ```
   On desktop Chrome (> 520px wide), ClassCue automatically renders inside a centered 480px mobile phone frame so you can preview the mobile UX directly.

---

## 5. Seeded Timetable & Demo Accounts

Seeded from **MSc IDS Sem VII & Sem IX Term I Timetable (Version 8, effective 25 Sep 2026)** — 2 cohorts, 8 courses (including shared cross-cohort elective `IMC-716 IoT`), 7 GBS classrooms/labs, 25 weekly base slots, and 3 rolling weeks of materialized sessions.

> **Security Note:** Passwords are NEVER stored in code or documentation. Use the login screen's collapsible **Quick Demo Accounts** picker to pre-fill an email, then enter the demo password provided separately.

| Role | Name | Cohort / Scope | Email |
| --- | --- | --- | --- |
| **Student** | Aarav Naik | MSc IDS Sem VII · Batch `B1` | `student.b1@classcue.app` |
| **Student** | Priya Naik | MSc IDS Sem VII · Batch `B2` | `student.b2@classcue.app` |
| **Student** | Nisha Kamat | MSc IDS Sem IX · Batch `B1` | `student.sem9@classcue.app` |
| **CR** | Meera Desai | MSc IDS Sem VII · `ALL` | `cr.sem7@classcue.app` |
| **Faculty** | Mr. Dnyandev Khadapkar (`DK`) | Permanent · `IMC-703 Deep Learning` | `dnyandev@classcue.app` |
| **Faculty** | Mr. Tanmay Parab (`TN`) | Permanent · `IMC-701 AI Search` | `tanmay@classcue.app` |
| **Faculty** | Dr. Teja Khandolkar (`TK`) | Permanent · `IMC-702 Research Methodology` | `teja@classcue.app` |
| **Faculty** | Mr. Venkatesh Prabhu (`VP`) | Visiting · `IMC-704 Design Thinking` | `venkatesh@classcue.app` |
| **Faculty** | Dr. Madhusudhan Lanjewar (`ML`) | Contributory · `IMC-716 IoT` (Shared Sem VII & IX) | `madhusudhan@classcue.app` |
| **Faculty** | Mr. Saurabh Borkar (`SB`) | Visiting · `IMC-717 Numerical Methods` | `saurabh@classcue.app` |
| **Faculty** | Mr. Shaunak Perni (`SP`) | Visiting · `IMC-911 Sequential Decision Making` | `shaunak@classcue.app` |
| **Faculty** | Mr. Amogh Parwatkar (`AP`) | Visiting · `IMC-611 Cloud Computing` | `amogh@classcue.app` |
| **Admin** | GBS Programme Admin | Full Campus Scope | `admin@classcue.app` |

---

## 6. GitHub Branching & Review Workflow

1. **Always branch from `dev`:**
   ```bash
   git checkout dev
   git pull origin dev
   git checkout -b feat/<short-feature-name>
   ```
2. **Verify locally before pushing:**
   ```bash
   dart format .
   flutter analyze
   flutter test
   ```
3. **Open a Pull Request into `dev`:** Request review from a teammate and ensure CI checks pass.
4. **Release to `main`:** Once verified on `dev`, merge `dev` → `main` to trigger the production release / Android APK build workflow.
5. **Never commit `env.json`** or edit audited files inside `supabase/` without team review.
