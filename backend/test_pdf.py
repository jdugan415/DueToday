"""POST /api/parse-pdf: upload a syllabus PDF, get the same JSON as /api/parse."""

import io

import pytest
from fastapi.testclient import TestClient
from pypdf import PdfReader, PdfWriter

from app.main import app
from app.pdf_text import ENCRYPTED_MESSAGE, INVALID_MESSAGE, SCANNED_MESSAGE
from pdf_fixtures import blank_pdf, make_pdf, table_rows

SCHEDULE = [
    ("Date", "Topic", "Due"),
    ("Aug 26", "Intro, syllabus", ""),
    ("9/2", "Python review", "HW 1 due (5%)"),
    ("Sept 16", "Sorting", "Quiz 1 (10 pts)"),
    ("Oct 7", "Midterm Exam (20%)", ""),
    ("Oct 9", "Graph Search", "Project 2 Proposal"),
]


@pytest.fixture()
def client():
    return TestClient(app)


def upload(client, data: bytes, *, filename="syllabus.pdf", content_type="application/pdf", **form):
    form.setdefault("reference_date", "2026-08-24")
    return client.post("/api/parse-pdf", files={"file": (filename, data, content_type)}, data=form)


def syllabus_pdf() -> bytes:
    return make_pdf([[(72, 760, "CSC 4330 - Software Systems")] + table_rows(SCHEDULE)])


def test_parses_a_schedule_table(client):
    response = upload(client, syllabus_pdf())
    assert response.status_code == 200
    body = response.json()
    assert body["course_code"] == "CSC 4330"
    assert [(t["title"], t["due_date"]) for t in body["tasks"]] == [
        ("HW 1", "2026-09-02"),
        ("Quiz 1", "2026-09-16"),
        ("Midterm Exam", "2026-10-07"),
        ("Project 2 Proposal", "2026-10-09"),
    ]
    assert body["tasks"][0]["weight_percent"] == 5
    assert body["tasks"][1]["points"] == 10


def test_response_matches_text_endpoint(client):
    text = "CSC 4330\n9/28 Midterm Exam (20%)\nLab 4 due Tuesday by 5pm"
    from_pdf = upload(client, make_pdf([[(72, 700 - 20 * i, line) for i, line in enumerate(text.splitlines())]]))
    from_text = client.post("/api/parse", json={"raw_text": text, "reference_date": "2026-08-24"})
    assert from_pdf.status_code == from_text.status_code == 200
    pdf_body, text_body = from_pdf.json(), from_text.json()
    assert pdf_body.keys() == text_body.keys()
    strip = lambda tasks: [{k: v for k, v in t.items() if k != "source_line"} for t in tasks]  # noqa: E731
    assert strip(pdf_body["tasks"]) == strip(text_body["tasks"])


def test_multi_page_schedule_keeps_context(client):
    page1 = table_rows([("Week 5 (Sept 21)", "", "")])
    page2 = [(72, 720, "Discussion post due Friday"), (72, 700, "Lab 5")]
    body = upload(client, make_pdf([page1, page2])).json()
    by_title = {t["title"]: t["due_date"] for t in body["tasks"]}
    assert by_title == {"Discussion post": "2026-09-25", "Lab 5": "2026-09-21"}


def test_form_fields_are_honoured(client):
    body = upload(
        client, syllabus_pdf(), course_code="math 1550", reference_date="2026-12-10", default_due_time="08:00"
    ).json()
    assert body["course_code"] == "MATH 1550"
    assert body["reference_date"] == "2026-12-10"
    assert body["tasks"][0]["due_time"] == "08:00"


def test_scanned_pdf_returns_friendly_error(client):
    response = upload(client, blank_pdf(page_count=3))
    assert response.status_code == 422
    assert response.json() == {"detail": SCANNED_MESSAGE, "error": SCANNED_MESSAGE}


def test_password_protected_pdf(client):
    writer = PdfWriter(clone_from=PdfReader(io.BytesIO(syllabus_pdf())))
    writer.encrypt(user_password="secret", algorithm="RC4-128")
    buffer = io.BytesIO()
    writer.write(buffer)
    response = upload(client, buffer.getvalue())
    assert response.status_code == 422
    assert response.json()["error"] == ENCRYPTED_MESSAGE


def test_corrupt_pdf(client):
    response = upload(client, b"%PDF-1.7\n" + b"\x00garbage" * 200)
    assert response.status_code == 422
    assert response.json()["error"] == INVALID_MESSAGE


@pytest.mark.parametrize(
    ("data", "filename", "content_type"),
    [
        (b"Quiz 1 due 9/12", "schedule.pdf", "application/pdf"),  # named .pdf, isn't one
        (b"%PDF-1.4 ...", "syllabus.docx", "application/msword"),  # wrong type entirely
    ],
)
def test_rejects_non_pdfs(client, data, filename, content_type):
    response = upload(client, data, filename=filename, content_type=content_type)
    assert response.status_code == 415
    assert response.json()["error"]


def test_accepts_pdf_mime_type_without_extension(client):
    response = upload(client, syllabus_pdf(), filename="document", content_type="application/pdf")
    assert response.status_code == 200


def test_rejects_files_over_the_size_limit(client, monkeypatch):
    import app.main

    monkeypatch.setattr(app.main, "MAX_PDF_BYTES", 1024)
    response = upload(client, syllabus_pdf() + b"\n%" + b"x" * 2048)
    assert response.status_code == 413
    assert "10 MB" in response.json()["error"]


def test_hyphenated_table_cell_is_rejoined(client):
    # A narrow first column wraps "Midterm Examination" as "Midterm Examina-" / "tion".
    cells = [
        (72, 700, "Midterm Examina-"), (200, 700, "Oct. 15, 2026"), (330, 700, "9:00 AM"), (480, 700, "25%"),
        (72, 686, "tion"),
        (72, 672, "Final Examination"), (200, 672, "Dec. 7, 2026"), (480, 672, "35%"),
    ]
    body = upload(client, make_pdf([cells])).json()
    assert [(t["title"], t["due_datetime"], t["weight_percent"]) for t in body["tasks"]] == [
        ("Midterm Examination", "2026-10-15T09:00:00", 25.0),
        ("Final Examination", "2026-12-07T23:59:00", 35.0),
    ]


def test_rejoin_leaves_ordinary_hyphens_alone():
    from app.pdf_text import rejoin_hyphenated_cells

    text = "Lab 2 - Linked lists   9/14\nreview\nWell-known self-test   9/21"
    assert rejoin_hyphenated_cells(text) == text


def test_requires_a_file(client):
    assert client.post("/api/parse-pdf", data={"course_code": "CSC 4330"}).status_code == 422
