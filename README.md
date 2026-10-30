# DueToday

Paste a syllabus, get a prioritized assignment list, and push due dates to your phone's calendar without granting the app any calendar permissions.

| Part | Stack | Folder |
| --- | --- | --- |
| Mobile app | Flutter (Android, Material 3) | [`mobile/`](mobile) |
| API | Python 3.12, FastAPI | [`backend/`](backend) |
| Database | Supabase Postgres (SQLite locally) | [`backend/app/database.py`](backend/app/database.py) |
| CI | GitHub Actions → release `.aab` | [`.github/workflows/build.yml`](.github/workflows/build.yml) |

**Start with [AGENT_HANDOVER.md](AGENT_HANDOVER.md)**: it covers the architecture, the API contract, local setup, team assignments, and git rules.

For the live backend, use the root [Render Blueprint](render.yaml) and follow
[the deployment guide](backend/DEPLOYMENT.md) to connect Supabase and configure Android builds.

## Quick start

```bash
cd backend && python -m venv .venv && . .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

```bash
cd mobile && flutter pub get && flutter run
```
