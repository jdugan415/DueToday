# AGENT_HANDOVER.md: DueToday

> **For AI coding agents and teammates.** Read this whole file before changing code. It is the source of truth for architecture, the API contract, and who owns what. If your PR changes anything described here, update this file in the same PR.

- **Project:** DueToday, a mobile syllabus parser, priority assignment tracker, and zero-permission calendar sync for college students.
- **Timeline:** 4-week senior capstone, 4 people (bootstrap landed 2026-10-27).
- **Repo layout:** `backend/` (FastAPI), `mobile/` (Flutter, Android), `.github/workflows/build.yml` (CI).

---

## 0. Non-negotiable rules (read first)

1. **Zero-permission rule.** The merged Android manifest may hold only `android.permission.INTERNET`. Never add `READ_CALENDAR`, `WRITE_CALENDAR`, storage, notification, contacts, or any other dangerous permission. CI fails the build if one appears (step "Verify zero-permission manifest").
2. **Calendar writes go through Intents only.** `CalendarService` uses `add_2_calendar`, which fires `Intent.ACTION_INSERT` on `CalendarContract.Events`. Never insert into the Calendar ContentProvider directly, and never add `device_calendar` or a similar plugin.
3. **The device is the source of truth.** Assignments live in SharedPreferences on the phone. The backend is stateless except for opt-in class-code sharing.
4. **The API contract (§3) is shared.** Changing a field name or type means updating `backend/app/models.py`, `mobile/lib/services/api_service.dart`, the model `fromJson`/`toJson` code, tests on both sides, and §3, all in one PR.
5. **Datetimes are naive local wall-clock time** (`2026-09-28T23:59:00`, no `Z`, no offset), both in the API and in storage. Don't convert to UTC.
6. **Keep `main` green.** Every PR must pass both CI jobs (backend pytest; Flutter analyze + test + AAB build + permission check).

---

## 1. Architecture & philosophy

```
┌────────────────────── Android device ──────────────────────┐
│  PasteView ──► StagingView ──► AssignmentStore ◄── Dashboard│
│      │  (edit/delete)            │  (ChangeNotifier)   │      │
│      │                           ▼                     │      │
│      │                    StorageService          AssignmentCard
│      │                  (SharedPreferences)            │      │
│      │                                                 ▼      │
│      │                                   CalendarService      │
│      │                         Intent.ACTION_INSERT ──► Google/Samsung
│      ▼                                                 Calendar app
│  ApiService ─── HTTPS ───────────────────────────┐            │
└──────────────────────────────────────────────────┼────────────┘
                                                   ▼
                       FastAPI (Render / Fly.io free tier)
                       ├─ POST /api/parse       → parser.py (stateless, deterministic regex)
                       ├─ POST /api/courses     → database.py → Supabase Postgres
                       └─ GET  /api/courses/{c} → database.py
```

### Zero-permission intent pattern
The app never reads or writes the calendar itself. Tapping the calendar icon on an `AssignmentCard` calls `CalendarService.addAssignmentToDeviceCalendar`, which builds an `Event` titled `[COURSE] Title` (start = due time, end = +1 h) and hands it to the system's calendar app in a pre-filled "new event" screen. The user taps Save there. Because the OS-provided app does the writing, DueToday needs no runtime permission prompt and passes Play review with no sensitive-permission declaration.

- `Add2Calendar.addEvent2Cal` returns `true` when the calendar app opened, not when the user saved. We mark `addedToCalendar = true` on launch; the icon changes to `event_available`.
- The manifest `<queries>` block for `android.intent.action.INSERT` + `vnd.android.cursor.item/event` is required on Android 11+ for package visibility. It is not a permission.
- `tools:node="remove"` entries for the calendar permissions are a safety net in case a dependency ever merges them in.

### Offline-first state strategy
- `AssignmentStore` (`lib/state/assignment_store.dart`, a `ChangeNotifier` exposed with `provider`) holds every `Assignment` and `Course`. Every mutation calls `_persist()`, which notifies listeners and writes JSON to SharedPreferences (`assignments_v1`, `courses_v1`).
- The network is needed only to **parse** new text and to **share/import** class codes. Everything else (dashboard, completing, deleting, calendar export) works in airplane mode.
- `addAll` upserts by `id`. Parser IDs are a stable hash of `course|title|date`, so re-parsing the same syllabus updates items instead of duplicating them.
- Storage keys are versioned (`_v1`). If you change the persisted shape incompatibly, bump to `_v2` and write a migration in `StorageService`. Don't silently break existing installs.

### Parser strategy (backend/app/parser.py)
Deterministic regex plus heuristics, with no ML and no external calls, so it's free to host and fully unit-testable. Per line it:
1. Strips bullets and skips holiday / "no class" / office-hours lines.
2. Finds explicit dates: `MM/DD`, `MM/DD/YY(YY)`, ISO `YYYY-MM-DD`, `Sept 28`, `Sep. 28`, `October 4th`, `Nov 1st, 2026`. Ranges like `Oct 12 – Oct 16` use the end date.
3. Finds relative dates: `Tuesday`, `next Fri`, `today`, `tomorrow`. Weekdays resolve to the first matching day on or after an anchor: the line's own date, else the last header row (e.g. `Week 5 (Sept 21)`), else `reference_date`. `next` adds 7 days.
4. Resolves year-less dates to the occurrence **nearest** `reference_date`, so a December paste of `1/15 Exam` lands in January of the next year.
5. Finds times (`11:59 PM`, `5pm`, `5 p.m.`, `14:30`, `noon`, `midnight`), percentages (`20%`) and points (`50 pts`). When no time is given, it falls back to `default_due_time` (23:59) with `time_specified: false`.
6. Finds task keywords: Final Exam, Midterm, Exam, Homework/HW, Quiz, Project, Lab, Discussion, Essay, Assignment, Presentation. It skips announcements ("Exam 1 review", "HW 3 assigned", "grades posted", "study for the midterm") and merges compound titles ("Final Project presentation").
7. Assigns each task its own date, time, and weight when several share a line, using two styles: *leading* (`9/12 Quiz 1, 9/14 HW 2`) and *trailing* (`Quiz 2 due 9/12; HW 3 due 9/14`). An explicit `due <date>` in a task's segment always wins.
8. Scores `priority` (importance: exams/midterms, ≥15 %, or ≥100 pts → high; projects/essays/presentations, ≥5 %, or ≥50 pts → medium; else low) and `confidence` (lower for relative dates, inherited context dates, and default times). The app flags items with confidence < 0.8 or no date in StagingView.

Add a pytest case to `backend/test_parser.py` for every parser change or bug report. That file is the parser's spec.

---

## 2. Current system state

> Last verified 2026-10-27 with Flutter 3.47.2 / Dart 3.13.2: `flutter analyze` reports no issues, all 43 Flutter tests pass, `flutter build appbundle --release` succeeds, and the merged release manifest holds only `INTERNET` (plus AndroidX's app-private `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`). Backend: 110 pytest cases pass. On a Pixel 9 Pro emulator against a local backend, the full PDF flow worked with a real syllabus: system picker (no permission prompt) → upload → review (on Oct 27: 14 upcoming items shown, 12 past items left out behind a switch) → save → dashboard with no Overdue flood. It has not been tested on a physical phone.
>
> **2026-10-27 updates:**
> - The Agent 2 (backend), Agent 3 (UX), and Agent 4 (export) items from §5 have been implemented. §5 now lists what is left for each.
> - **PDF syllabus upload** is complete: `POST /api/parse-pdf` and the "Or upload syllabus PDF" card on the paste screen. The real Dart client was verified against the real server with generated PDFs.

### ✅ Implemented

| Area | File(s) | Notes |
| --- | --- | --- |
| Parse API | `backend/app/main.py`, `parser.py`, `models.py` | Full algorithm in §1. 87 parser edge-case tests. Tabs and runs of 3+ spaces are treated as table-cell boundaries, so a "Topic" column never leaks into a title. **Prose filtering** (tuned on a real 2026 LSU syllabus): plural keywords ("Quizzes", "Labs") are categories, not items; a keyword followed within two words by a policy word ("accounts for", "should", "contributes", "policy", "weight", "schedule"...) or starting a lowercase list is a sentence; a bare "Final" must stand alone ("Final date to drop" is skipped); context dates flow only into short schedule lines (≤ 8 words, no weight, not a bare heading); undated grading-table rows merge their weight into the dated item with the same title; sentence-style duplicates of a dated item are dropped. |
| PDF parse API | `backend/app/pdf_text.py`, `main.py` | `POST /api/parse-pdf` (multipart): pypdf **layout-mode** extraction (keeps table rows on one line, column gaps intact), first 60 pages, 10 MB cap. Clear errors for scanned/no-text (422), password-protected (422), corrupt (422), non-PDF (415), and too-large (413) files. Same rate limit as `/api/parse`. Words hyphenated across a wrapped table cell ("Examina-" / "tion") are rejoined. Tested in `test_pdf.py` (14 tests) with real PDFs built by `pdf_fixtures.py` (no extra deps). **Real-world check:** a 4-page assessment-schedule PDF yields 26 items, all genuine (6 labs, 5 quizzes, 5 HWs with 2% each, project milestones, midterm with time, final with 35%). A policy-heavy full syllabus yields 1 item instead of 66. |
| Share / import API | `main.py`, `database.py` | 5-char codes from a 31-char unambiguous alphabet (no 0/O/1/I/L). Collision retry. |
| `.ics` calendar feed | `backend/app/ics.py`, `main.py` | `GET /api/courses/{code}/calendar.ics`: RFC 5545, floating local times, escaped text, 75-octet line folding, stable UIDs, 6 h refresh hint. Undated tasks are skipped. |
| Rate limiting | `backend/app/ratelimit.py` | In-memory sliding window per client IP → `429` + `Retry-After`. Defaults: parse 30/min, share 20/h, lookups (JSON + .ics) 60/min. Env-tunable. |
| DB connector | `database.py` | `DATABASE_URL` → Postgres via psycopg 3 (Supabase-pooler-safe: `prepare_threshold=None`); fallback `sqlite:///./duetoday.db`. |
| Migrations | `backend/alembic.ini`, `backend/migrations/` | Alembic baseline `0001` = current schema. The Docker image runs `alembic upgrade head` before starting. `create_all` runs only for SQLite. `test_migrations.py` fails if models and migrations drift. |
| API tests | `backend/test_api.py`, `conftest.py` | In-memory SQLite via dependency override; rate limiters reset between tests. |
| Docker | `backend/Dockerfile` | Python 3.12-slim, non-root, honours `$PORT`, trusts proxy headers so rate limits see real client IPs. |
| Models | `mobile/lib/models/*.dart` | `Assignment`, `Course`, `ShareCode`, `DashboardBuckets` (Overdue / Due Today / This Week / Later / No Date / Completed). |
| API client | `lib/services/api_service.dart` | 60 s timeout for free-tier cold starts; FastAPI `detail` surfaced as `ApiException.message`. Sends the device's date as `reference_date`. |
| Calendar | `lib/services/calendar_service.dart` | Intent delegation as specified; `buildEvent` is unit-tested. |
| Storage | `lib/services/storage_service.dart` | SharedPreferences JSON; corrupt cache → empty list + `debugPrint`. |
| State | `lib/state/assignment_store.dart` | Upsert, update, remove, toggle complete, calendar flag, share code. Injectable clock for tests. |
| PDF upload | `lib/views/paste_view.dart`, `lib/services/api_service.dart` | "Or upload syllabus PDF" card → system document picker (`file_picker` 13 / `android_file_picker` 2.1, Storage Access Framework, **no storage permission**) → `ApiService.parseSyllabusPdf` (multipart, 120 s timeout, 10 MB client-side check) → same review screen as pasted text. A `LinearProgressIndicator` plus a "Reading <file>…" status show during upload. `PasteView(pickPdf: …)` is injectable for tests. |
| Past items on import | `lib/views/staging_view.dart` | Items already due when the review screen opens are **left out by default**, so a mid-semester import doesn't flood Overdue. A banner ("12 items are already past due") has a switch to include them; included ones are marked "Past due". The past set is fixed when the screen opens, so editing a date never makes an item vanish. Undated items always stay. If *everything* is past (an old syllabus), they're included by default. Tested in `test/staging_view_test.dart`. |
| Screens | `lib/views/paste_view.dart`, `staging_view.dart`, `dashboard_view.dart`, `edit_assignment_view.dart` | Paste (clipboard button, sample schedule, PDF upload) → staging (edit title, date/time pickers, swipe to delete, review warnings, course code/name) → dashboard → edit screen (title, date/time/clear, priority, notes, delete with Undo, original syllabus line). |
| Dashboard | `lib/views/dashboard_view.dart` | Course filter chips (shown with ≥ 2 courses; long-press or ⚙ opens course settings), export menu, share, import. Animated cross-fade on filter change. |
| Widgets | `lib/widgets/assignment_card.dart`, `share_dialog.dart`, `course_sheet.dart` | Card: swipe right = complete/un-complete, swipe left = delete, both with Undo; tap = container-transform into the editor; checkbox; animated strike-through and calendar icon. Share dialog: generate/copy code **and** copy the `.ics` feed link. Course sheet: rename, pick badge color, delete course + its assignments. |
| Export | `lib/services/export_service.dart` | Markdown checklist and Notion-ready CSV (RFC 4180) for all courses or the filtered one, sent through the Android share sheet via `share_plus` (private FileProvider in the cache dir, no storage permission). |
| **Design system** | `lib/theme/app_theme.dart` | Linear/Things-style look: slate neutrals (light bg `#F8FAFC`, surface `#FFFFFF`, border `#E2E8F0`, text `#0F172A`/`#64748B`; dark bg `#090D16`, surface `#131B2E`, border `#1E293B`), iris accent `#4F46E5` / `#818CF8`, urgent `#EF4444`, warning `#F59E0B`, success `#10B981`. Semantic colors live in the `AppColors` ThemeExtension. Read them with `context.colors`, never hard-code hex in widgets. Cards are 16px radius with a 1px hairline (`outlineVariant` at 50%) and **no shadows**; sheets have a 24px top radius; fields are soft-filled with no border until focus; buttons are pills; the app bar is transparent with elevation 0. **Font:** Plus Jakarta Sans 400–800 is bundled in `assets/fonts` (OFL license registered in `main.dart`) as a normal pubspec family. `google_fonts` was evaluated and dropped: v9 builds on the separate `material_ui` TextTheme type, runtime fetching breaks offline-first, and its one-family-per-weight scheme ignores later `fontWeight` changes. Course tags are tinted from a stable FNV hash of the course code (`courseColorIndexFor`); users can still recolor them. |
| Countdown labels | `lib/models/due_label.dart` | "Due in 4h" / "Due in 20m" (< 24 h, rose), "Tomorrow", weekday, "Nov 12", "Overdue 2d", with urgency levels that drive the card's left accent strip and badge color. Unit-tested in `test/due_label_test.dart`. |
| Haptics | card, share sheet, import | `HapticFeedback.lightImpact` (calendar, copy), `mediumImpact` (complete). These use the view's haptic feedback, so **no VIBRATE permission** is needed; verified in the merged manifest. |
| Android | `mobile/android/**` | Kotlin DSL Gradle matching the Flutter 3.47 template (AGP 9.1.0, Kotlin 2.4.0, Gradle 9.3.1, Java 17 bytecode), `minSdk 26`, `targetSdk ≥ 34`, cleartext HTTP only to `10.0.2.2`/`localhost`, adaptive vector launcher icon, key.properties-based release signing with debug fallback. |
| CI | `.github/workflows/build.yml` | Backend pytest; Flutter pub get → analyze → test → `appbundle` → merged-manifest permission audit → upload `.aab` artifact. |
| Flutter tests | `mobile/test/*.dart` | Model JSON, buckets, share codes, calendar event, API client (MockClient), export golden strings, PDF upload (`pdf_upload_test.dart`: multipart body, errors, size limit, upload → review, cancel, scanned message), and 8 dashboard widget tests (empty state, completing, swipe complete/delete + Undo, editor save, course filter, course sheet rename/delete, navigation). |

### ⚠️ Not yet done / known limitations

| Item | Owner | Detail |
| --- | --- | --- |
| End-to-end run on a device | anyone | Boot the backend, `flutter run` on an emulator, and walk paste → staging → dashboard → calendar → share/import. File bugs for anything broken. |
| Play signing & upload | Agent 1 | CI signs with the debug key until secrets exist. |
| Backend deployment | Agent 1 | No `render.yaml` / `fly.toml` yet. Set `vars.API_BASE_URL` in GitHub once deployed. Until then, release builds point at `http://10.0.2.2:8000` (emulator only). |
| Rate limits across instances | Agent 2 | Limits are in-memory per process: fine on one free instance, but not shared if the API scales out. |
| Store listing assets | Agent 3 | Screenshots, feature graphic (1024×500), 512×512 icon PNG for the Play listing. The UI redesign (2026-10-27) is done, so screenshots can be taken now in light and dark mode. |
| Scanned-PDF OCR | stretch | Image-only PDFs return the "copy and paste" message. OCR (e.g. Tesseract on the server, or on-device ML Kit text recognition) would need either a bigger server image or a new plugin; check its manifest against the zero-permission rule first. |
| Offline parsing | stretch | Parsing requires the backend. A Dart port of the parser would make paste work offline. |
| Shared-course sync | stretch | Importing a code copies a snapshot; later changes by the sharer don't propagate. |
| Auth / rate limiting | stretch | Share codes are public and unauthenticated; anyone with a code can read that course. Don't store personal data in `notes`. |
| iOS | out of scope | No `ios/` folder. `add_2_calendar` would need `NSCalendarsUsageDescription` there. |
| Placeholder branding | Agent 3 | Launcher icon is a simple vector; package id is `com.duetoday.app`. |

---

## 3. API contract reference

Base URL: `http://localhost:8000` locally (`http://10.0.2.2:8000` from the Android emulator). Interactive docs: `/docs`. Errors use FastAPI's shape: `{"detail": "message"}` (or a list of validation errors for 422).

### `GET /health`
`200 {"status": "ok", "version": "0.1.0"}`

### `POST /api/parse`
Request:
```json
{
  "raw_text": "CSC 4330\n9/28 Midterm Exam (20%)\nLab 4 due Tuesday by 5pm",
  "course_code": null,
  "reference_date": "2026-08-24",
  "default_due_time": "23:59"
}
```
| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `raw_text` | string, 1–100 000 chars | yes | |
| `course_code` | string ≤ 20 \| null | no | Overrides auto-detection (`CSC 4330`-style codes). Normalized to upper case. |
| `reference_date` | `YYYY-MM-DD` \| null | no | Client's local today. Defaults to server date. **The app always sends it.** |
| `default_due_time` | `HH:MM` 24 h | no | Default `23:59`. |

Response `200`:
```json
{
  "course_code": "CSC 4330",
  "reference_date": "2026-08-24",
  "tasks": [
    {
      "id": "23edf8506d5c",
      "title": "Lab 4",
      "task_type": "lab",
      "due_date": "2026-08-25",
      "due_time": "17:00",
      "due_datetime": "2026-08-25T17:00:00",
      "time_specified": true,
      "weight_percent": null,
      "points": null,
      "priority": "low",
      "confidence": 0.8,
      "source_line": "Lab 4 due Tuesday by 5pm"
    },
    {
      "id": "f305cf8b3c03",
      "title": "Midterm Exam",
      "task_type": "midterm",
      "due_date": "2026-09-28",
      "due_time": "23:59",
      "due_datetime": "2026-09-28T23:59:00",
      "time_specified": false,
      "weight_percent": 20.0,
      "points": null,
      "priority": "high",
      "confidence": 0.95,
      "source_line": "9/28 Midterm Exam (20%)"
    }
  ],
  "warnings": []
}
```
- `task_type` ∈ `exam | midterm | homework | quiz | project | lab | discussion | essay | assignment | presentation | other`
- `priority` ∈ `high | medium | low`
- `due_date` / `due_datetime` are `null` when no date was found; a matching entry is added to `warnings`.
- `tasks` are sorted by `due_datetime` (undated last), deduplicated by `(title, due_date)`.
- `id` is a 12-hex-char stable hash of `course_code|title|due_date`.

### `POST /api/parse-pdf`: parse an uploaded syllabus PDF
`multipart/form-data`:
| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `file` | PDF file ≤ 10 MB | yes | Accepted if the name ends in `.pdf` **or** the part's content type is `application/pdf`, and the bytes start with `%PDF-`. |
| `course_code` | text ≤ 20 | no | Same as `/api/parse`. |
| `reference_date` | `YYYY-MM-DD` | no | Same as `/api/parse`. The app always sends it. |
| `default_due_time` | `HH:MM` | no | Default `23:59`. |

Response `200`: **identical shape to `POST /api/parse`** (`course_code`, `reference_date`, `tasks[]`, `warnings[]`). `source_line` holds the extracted PDF line, which may contain column padding.

Errors carry both `detail` (like every other endpoint) and `error` (same text):
| Status | When | Message |
| --- | --- | --- |
| `413` | > 10 MB | "That PDF is larger than 10 MB. Try exporting just the schedule pages." |
| `415` | not a PDF | "Please choose a .pdf file." / "That file isn't a PDF." |
| `422` | no text layer (scanned) | "Could not extract text. If this is a scanned document, please copy and paste the text directly." |
| `422` | password-protected | "This PDF is password-protected. Open it, copy the schedule text, and paste it instead." |
| `422` | corrupt | "That file isn't a readable PDF. Try exporting the syllabus to PDF again." |
| `422` | missing `file` / bad form field | FastAPI validation error list in `detail` (no `error` key). |

Try it: `curl -F file=@syllabus.pdf -F reference_date=2026-08-24 http://localhost:8000/api/parse-pdf`

### `POST /api/courses`: publish a course, get a class code
Request:
```json
{
  "course_code": "CSC 4330",
  "course_name": "Software Systems",
  "tasks": [
    {
      "title": "Midterm Exam",
      "task_type": "midterm",
      "due_datetime": "2026-09-28T23:59:00",
      "weight_percent": 20,
      "points": null,
      "priority": "high",
      "notes": null
    }
  ]
}
```
| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `course_code` | string 1–20 | yes | Normalized to upper case, single spaces. |
| `course_name` | string ≤ 120 \| null | no | |
| `tasks[]` | ≤ 500 items | no | `title` (1–200) required; `task_type` default `other`; `due_datetime` naive ISO or null; `weight_percent` 0–100; `points` ≥ 0; `priority` default `medium`; `notes` ≤ 2000. |

Response `201`:
```json
{
  "share_code": "H4PSD",
  "course_code": "CSC 4330",
  "course_name": "Software Systems",
  "created_at": "2026-10-27T21:05:15.522574",
  "tasks": [
    {
      "id": 1,
      "title": "Midterm Exam",
      "task_type": "midterm",
      "due_datetime": "2026-09-28T23:59:00",
      "weight_percent": 20.0,
      "points": null,
      "priority": "high",
      "notes": null
    }
  ]
}
```
`share_code` matches `^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{5}$`. `created_at` is UTC (timezone-aware on Postgres; SQLite drops the offset).

### `GET /api/courses/{code}`: import a class code
- Case-insensitive (`h4psd` works).
- `200`: same body as the `POST /api/courses` response.
- `404 {"detail": "No course found for code H4PSD"}`
- `422 {"detail": "Share codes are 5 letters/digits"}` for malformed codes.

The app turns imported tasks into local assignments with id `shared-<CODE>-<task id>`, so re-importing the same code updates instead of duplicating.

### `GET /api/courses/{code}/calendar.ics`: subscribable calendar feed
- `200`, `Content-Type: text/calendar; charset=utf-8`, CRLF line endings. Same 404/422 rules as above.
- One `VEVENT` per **dated** task: `UID:task-<id>-<CODE>@duetoday`, floating `DTSTART` = due, `DTEND` = due + 1 h, `SUMMARY:[COURSE] Title`, `DESCRIPTION` with type/priority/weight/points/notes, `CATEGORIES` = task type.
- The app's share dialog copies this URL. Google Calendar: **Other calendars → + → From URL** (the API must be reachable over public HTTPS).

### Rate limits (all endpoints above)
`429 {"detail": "Too many requests. Please wait a moment and try again."}` with a `Retry-After: <seconds>` header. The app shows `detail` in a snackbar.

---

## 4. Local development

### Backend (Python 3.12 recommended; 3.14 also works)
```bash
cd backend
python -m venv .venv
source .venv/bin/activate          # Windows PowerShell: .venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
# → http://localhost:8000/docs
pytest -q                          # parser + API tests
```
Optional environment variables:
| Var | Default | Purpose |
| --- | --- | --- |
| `DATABASE_URL` | `sqlite:///./duetoday.db` | Supabase: Project → Connect → *Transaction pooler* URI (`postgresql://…:6543/postgres`). `postgres://` / `postgresql://` are rewritten to `postgresql+psycopg://`. |
| `ALLOWED_ORIGINS` | `*` | Comma-separated CORS origins (only matters for web clients and the docs UI). |
| `PORT` | `8000` | Used by the Docker image. |
| `RATE_LIMIT_PARSE_PER_MINUTE` | `30` | Per client IP. `0` disables. |
| `RATE_LIMIT_SHARE_PER_HOUR` | `20` | `POST /api/courses`. |
| `RATE_LIMIT_LOOKUP_PER_MINUTE` | `60` | `GET /api/courses/{code}` and `.ics`. |

Migrations (Postgres; SQLite dev databases are created automatically):
```bash
alembic upgrade head                                  # apply
alembic revision --autogenerate -m "add expires_at"   # after editing app/database.py, then review the file
pytest -q test_migrations.py                          # proves models == migrations
```
On Windows, if pytest can't create its temp folder, add `--basetemp=.pytest-tmp`.

Docker:
```bash
cd backend
docker build -t duetoday-api .
docker run -p 8000:8000 -e DATABASE_URL="postgresql://..." duetoday-api
```

### Mobile (Flutter stable ≥ 3.47; JDK 17–25; Android SDK 35)
Android Studio users: Flutter uses Android Studio's bundled JDK (Java 25 in recent releases). Gradle 9.3.1 supports it, so don't downgrade the Gradle wrapper below 9.1, or the build fails with a Java/Gradle incompatibility error. `mobile/pubspec.lock` is committed, so run `flutter pub get` rather than `flutter pub upgrade` unless you mean to bump dependencies.

```bash
cd mobile
flutter pub get
flutter analyze
flutter test
flutter emulators --launch <emulator_id>     # or start one from Android Studio
flutter run                                   # talks to http://10.0.2.2:8000 by default
flutter run --dart-define=API_BASE_URL=https://<your-api>.onrender.com
flutter build appbundle --release             # → build/app/outputs/bundle/release/app-release.aab
```
- **Physical phone + local backend:** `adb reverse tcp:8000 tcp:8000`, then `flutter run --dart-define=API_BASE_URL=http://localhost:8000`.
- Cleartext HTTP is allowed only for `10.0.2.2`, `localhost` and `127.0.0.1` (`res/xml/network_security_config.xml`). Deployed backends must use HTTPS.
- The Gradle wrapper scripts (`gradlew`, wrapper jar) are git-ignored; the Flutter tool generates them on first build.
- To check the zero-permission rule locally after a release build:
  `grep uses-permission build/app/intermediates/merged_manifest/release/*/AndroidManifest.xml`

---

## 5. Team work breakdown (agent next actions)

Each agent works on its own branch (§6). Coordinate through PRs; don't edit another area's files without tagging its owner.

### Agent 1: DevOps
Owns: `.github/`, `mobile/android/app/build.gradle.kts` (signing), deployment config.
1. Generate an upload keystore (`keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`). **Never commit it.**
2. Add repo secrets: `ANDROID_KEYSTORE_BASE64` (`base64 -w0 upload-keystore.jks`), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`. CI already consumes them (step "Configure release signing").
3. Deploy the backend (Render web service from `backend/Dockerfile`, or `fly launch`), connect Supabase with `DATABASE_URL`, then set the repo **variable** `API_BASE_URL` to the HTTPS URL.
4. Create the Play Console app (`com.duetoday.app`), enroll in Play App Signing, and upload the first CI `.aab` to the **Internal testing** track. Add the team as testers.
5. Optional: add a job that uploads to the internal track automatically on `main` (e.g. `r0adkll/upload-google-play` with a service-account JSON secret).
6. Data safety form: no data collected on device; share codes send course/assignment titles to our server.

### Agent 2: Backend
Owns: `backend/`.
✅ Done: Alembic migrations, `.ics` feed, rate limiting, PDF upload, prose filtering from one real syllabus (see §2). Remaining:
1. Collect 5–10 more real syllabi from classmates (different departments and formats), upload each PDF at `/docs` → `POST /api/parse-pdf`, and turn every wrong or missed item into a failing pytest case **using made-up text in the same shape** (never commit someone's real syllabus) before fixing the parser. This is still the highest-value backend work left.
2. Optional `expires_at` on `courses` (e.g. end of semester + 30 days) with a cleanup job. Write it as a new Alembic revision, never by editing `0001`.
3. If the API ever runs more than one instance, move rate limits to Redis or the proxy.
4. Any contract change: update §3 and tell Agents 3/4.

### Agent 3: Frontend UX
Owns: `mobile/lib/views/`, `mobile/lib/widgets/`, `mobile/lib/theme.dart`.
✅ Done: swipe-to-complete/delete with Undo, edit screen with container transform, course filter chips + color/name/delete sheet, shared-axis transitions, animated completion (see §2). Remaining:
1. Real launcher icon and Play listing graphics (512×512 icon, 1024×500 feature graphic, 4–8 phone screenshots).
2. Run the app on an emulator and a real phone: check dark mode, large font sizes (Settings → Display → Font size), TalkBack, and small screens (the dashboard card row is the tightest layout).
3. Optional: `AnimatedList` so cards slide between buckets instead of re-rendering; onboarding tip on first launch.
4. Keep `mobile/test/widget_test.dart` passing. Note that `OpenContainer` draws the closed card with no `Material` ancestor during its transition, so keep the `Material(type: transparency)` wrapper in `AssignmentCard`. Also, a `tooltip` on the course chips would claim long-press and break the course sheet.

### Agent 4: Export & integrations
Owns: `mobile/lib/services/export_service.dart` and its UI entry points (coordinate with Agent 3).

✅ Done: Markdown checklist and Notion CSV (`Name,Course,Type,Due,Weight,Points,Priority,Status,Notes`), shared through `share_plus`, exported from the dashboard's download menu (all courses or the filtered course), with golden-string tests. `share_plus` 13.3.1 was confirmed to add no permissions. Remaining:
1. Import the CSV into a real Notion database and the Markdown into Notion/Obsidian on a phone, and adjust column formats if anything maps wrong.
2. Optional: a "Save to Files" option via the Storage Access Framework (`ACTION_CREATE_DOCUMENT`, still no storage permission). After adding any plugin, run a release build and confirm the CI permission check still passes.

---

## 6. Git hygiene rules

- **Never push directly to `main`.** All changes land through PRs with ≥ 1 teammate approval and green CI.
- **Branch names:** `<type>/<short-kebab-description>`
  - `feat/` new functionality (`feat/ics-export`, `feat/swipe-to-complete`)
  - `fix/` bug fixes (`fix/parser-ordinal-dates`)
  - `docs/` documentation only (`docs/handover-api-update`)
  - Also allowed when they fit better: `chore/` (deps, config), `ci/` (workflow changes), `test/` (tests only), `refactor/` (no behaviour change).
- **Commits:** imperative mood, ≤ 72-char subject, optional body explaining *why* (`Add .ics endpoint for shared courses`). Small, focused commits; no "wip" commits on `main`.
- **PRs:**
  - Title follows the commit style; description says what changed, why, how it was tested, and links the issue if any.
  - One concern per PR; keep it reviewable (< ~400 changed lines when possible).
  - Rebase on or merge `main` before requesting review; resolve conflicts on your branch.
  - Squash-merge into `main`; delete the branch after merge.
  - Contract changes (§3) or new Android dependencies call this out at the top of the PR description.
- **Never commit:** keystores (`*.jks`, `*.keystore`), `key.properties`, `.env`, real `DATABASE_URL`s, `*.db` files, `build/` output. `.gitignore` covers these; double-check `git status` before committing.
- **Agents specifically:** before starting, `git pull` `main`, re-read this file, and run both test suites. Before opening a PR, run `pytest -q` (backend) and `flutter analyze && flutter test` (mobile), and update §2 "Current system state" to reflect what you finished.
