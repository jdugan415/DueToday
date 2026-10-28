"""HTTP contract tests against an in-memory SQLite database."""

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.database import get_db, init_db
from app.main import app


@pytest.fixture()
def client():
    engine = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
    )
    init_db(engine)
    TestSession = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)

    def override_get_db():
        db = TestSession()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override_get_db
    yield TestClient(app)
    app.dependency_overrides.clear()


def test_health(client):
    assert client.get("/health").json()["status"] == "ok"


def test_parse_endpoint(client):
    response = client.post(
        "/api/parse",
        json={
            "raw_text": "CSC 4330\n9/28 Midterm Exam (20%)\nHW 2 due Tuesday by 5pm",
            "reference_date": "2026-08-24",
        },
    )
    assert response.status_code == 200
    body = response.json()
    assert body["course_code"] == "CSC 4330"
    assert body["reference_date"] == "2026-08-24"
    hw, midterm = body["tasks"]
    assert hw["due_datetime"] == "2026-08-25T17:00:00"
    assert midterm == {
        **midterm,
        "title": "Midterm Exam",
        "task_type": "midterm",
        "due_date": "2026-09-28",
        "due_time": "23:59",
        "time_specified": False,
        "weight_percent": 20.0,
        "priority": "high",
    }


def test_parse_rejects_empty_text(client):
    assert client.post("/api/parse", json={"raw_text": ""}).status_code == 422


def test_share_and_import_course(client):
    created = client.post(
        "/api/courses",
        json={
            "course_code": "csc 4330",
            "course_name": "Software Systems",
            "tasks": [
                {"title": "Midterm Exam", "task_type": "midterm",
                 "due_datetime": "2026-09-28T23:59:00", "weight_percent": 20, "priority": "high"},
                {"title": "Lab 5"},
            ],
        },
    )
    assert created.status_code == 201
    body = created.json()
    code = body["share_code"]
    assert len(code) == 5 and code.isupper()
    assert body["course_code"] == "CSC 4330"

    fetched = client.get(f"/api/courses/{code.lower()}")
    assert fetched.status_code == 200
    tasks = fetched.json()["tasks"]
    assert {t["title"] for t in tasks} == {"Midterm Exam", "Lab 5"}
    assert all(isinstance(t["id"], int) for t in tasks)


def test_import_unknown_and_malformed_codes(client):
    assert client.get("/api/courses/ABCDE").status_code == 404
    assert client.get("/api/courses/AB0").status_code == 422
