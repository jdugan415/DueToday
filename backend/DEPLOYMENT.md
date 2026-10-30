# Deploy the DueToday API

The root `render.yaml` creates a Docker web service using `backend/` as its
build context and `/health` as its health check. The existing Docker command
runs `alembic upgrade head` before starting Uvicorn on Render's `$PORT`.

## Connect Supabase and Render

1. Create a Supabase project. In **Connect**, copy its **Transaction pooler**
   PostgreSQL URI (port `6543`). Replace the password placeholder with the
   database password, URL-encoding special characters in the password. Add
   `?sslmode=require` to require an encrypted database connection (or
   `&sslmode=require` if the URI already has a query string).
2. Push these files through a reviewed PR to the repository's `main` branch.
3. In Render, choose **New → Blueprint** and select this repository.
   Render reads `render.yaml` and prompts for `DATABASE_URL`. Paste the pooler
   URI there. Do not commit it or put it in the mobile app.
4. Deploy and check the logs for successful migrations and server startup.
   Copy the assigned HTTPS URL from Render; do not assume the service name
   guarantees a particular hostname.
5. Open `https://YOUR-SERVICE.onrender.com/health`. Expect
   `{"status":"ok","version":"0.1.0"}`. The first request after an idle
   period can take longer while the service starts.

Do not use SQLite for this deployment: the container filesystem is ephemeral
and shared courses would be lost when the container is replaced.

## Point Android builds at the deployed API

In GitHub, open **Settings → Secrets and variables → Actions → Variables**
and set the repository variable `API_BASE_URL` to the assigned HTTPS URL,
without a trailing slash. The existing build workflow passes this value to
Flutter using `--dart-define`; rerun the workflow after setting the variable.
It is a public URL, not a secret. Alternatively, from this repository:

```bash
gh variable set API_BASE_URL --body 'https://YOUR-SERVICE.onrender.com'
```

For local testing, from `mobile/`:

```bash
flutter run --dart-define=API_BASE_URL=https://YOUR-SERVICE.onrender.com
```

The emulator's local backend remains the default when no define is supplied.

## Verify before completing the Trello card

Use synthetic data in the deployed API's `/docs` page:

1. `POST /api/parse`: parse `CSC 4330\n11/12/2026 Homework 1 due 5pm` and
   confirm the task title and deadline.
2. `POST /api/parse-pdf`: upload a text-based sample PDF and confirm its tasks.
3. `POST /api/courses`: publish a sample course with a dated task; copy the
   returned share code.
4. `GET /api/courses/{code}`: confirm the same course and task are returned.
5. `GET /api/courses/{code}/calendar.ics`: confirm the feed contains a `VEVENT`
   with the expected title and local deadline.
6. On a real Android phone, repeat paste/PDF import, review/save, share/import,
   and opening the calendar feed. Repeat parsing after the backend has been
   idle to check the app's cold-start timeout handling.

Deployment is not complete until these live checks pass. `/health` confirms
the server is running; publishing/importing a course also checks database access.

Reference: [Render Blueprint specification](https://render.com/docs/blueprint-spec).
