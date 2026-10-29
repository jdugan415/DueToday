"""FastAPI entrypoint.

Run locally:  uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
"""

from __future__ import annotations

import json
import os
import re
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from datetime import date

from fastapi import Depends, FastAPI, File, Form, HTTPException, Response, UploadFile, status
from fastapi.concurrency import run_in_threadpool
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session
from pydantic import ValidationError

from . import __version__
from .database import CourseRecord, create_course, get_course_by_share_code, get_db, init_db
from .ics import build_calendar
from .models import SHARE_CODE_PATTERN, CourseCreate, CourseOut, ParseRequest, ParseResponse
from .parser import parse_syllabus
from .pdf_text import MAX_PDF_BYTES, PdfExtractionError, extract_pdf_text, looks_like_pdf
from .ratelimit import lookup_limiter, parse_limiter, share_limiter


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    init_db()
    yield


app = FastAPI(title="DueToday API", version=__version__, lifespan=lifespan)

# The Android app does not need CORS; this is for the docs UI and any web client.
_origins = [o.strip() for o in os.getenv("ALLOWED_ORIGINS", "*").split(",") if o.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=_origins,
    allow_credentials=False,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["*"],
)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "version": __version__}


@app.post("/api/parse", response_model=ParseResponse, dependencies=[Depends(parse_limiter)])
def parse(request: ParseRequest) -> ParseResponse:
    return parse_syllabus(
        request.raw_text,
        course_code=request.course_code,
        reference_date=request.reference_date or date.today(),
        default_due_time=request.default_due_time,
        class_days=request.class_days,
    )


_PDF_ERROR_RESPONSES = {
    413: {"description": "File is larger than 10 MB"},
    415: {"description": "File is not a PDF"},
    422: {"description": "No usable text (scanned, password-protected, or corrupt PDF)"},
}


@app.post(
    "/api/parse-pdf",
    response_model=ParseResponse,
    dependencies=[Depends(parse_limiter)],
    responses=_PDF_ERROR_RESPONSES,
)
async def parse_pdf_endpoint(
    file: UploadFile = File(...),
    class_days: str | None = Form(default=None),
    course_code: str | None = Form(default=None, max_length=20),
    reference_date: date | None = Form(default=None),
    default_due_time: str = Form(default="23:59", pattern=r"^([01]\d|2[0-3]):[0-5]\d$"),
) -> ParseResponse | JSONResponse:
    """Same as POST /api/parse, but the schedule comes from an uploaded PDF."""
    try:
        days = ParseRequest(raw_text="validation", class_days=json.loads(class_days) if class_days else None).class_days
    except (ValueError, ValidationError):
        return _pdf_error(422, "Choose two distinct weekdays (Monday=0 through Sunday=6).")
    named_pdf = (file.filename or "").lower().endswith(".pdf")
    if not named_pdf and file.content_type != "application/pdf":
        return _pdf_error(415, "Please choose a .pdf file.")

    data = await file.read(MAX_PDF_BYTES + 1)
    if len(data) > MAX_PDF_BYTES:
        return _pdf_error(413, "That PDF is larger than 10 MB. Try exporting just the schedule pages.")
    if not looks_like_pdf(data):
        return _pdf_error(415, "That file isn't a PDF.")

    try:
        text = await run_in_threadpool(extract_pdf_text, data)
    except PdfExtractionError as error:
        return _pdf_error(422, str(error))

    return parse_syllabus(
        text,
        course_code=course_code,
        reference_date=reference_date or date.today(),
        default_due_time=default_due_time,
        class_days=days,
    )


def _pdf_error(status_code: int, message: str) -> JSONResponse:
    # "detail" matches every other error in the API (the app shows it);
    # "error" is the field the PDF upload spec asks for.
    return JSONResponse(status_code=status_code, content={"detail": message, "error": message})


@app.post(
    "/api/courses",
    response_model=CourseOut,
    status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(share_limiter)],
)
def share_course(payload: CourseCreate, db: Session = Depends(get_db)) -> CourseOut:
    return CourseOut.model_validate(create_course(db, payload))


@app.get("/api/courses/{share_code}", response_model=CourseOut, dependencies=[Depends(lookup_limiter)])
def import_course(share_code: str, db: Session = Depends(get_db)) -> CourseOut:
    return CourseOut.model_validate(_find_course(db, share_code))


@app.get(
    "/api/courses/{share_code}/calendar.ics",
    response_class=Response,
    dependencies=[Depends(lookup_limiter)],
    responses={200: {"content": {"text/calendar": {}}, "description": "iCalendar feed"}},
)
def course_calendar(share_code: str, db: Session = Depends(get_db)) -> Response:
    course = _find_course(db, share_code)
    return Response(
        content=build_calendar(course),
        media_type="text/calendar; charset=utf-8",
        headers={
            "Content-Disposition": f'inline; filename="{course.share_code}.ics"',
            "Cache-Control": "public, max-age=900",
        },
    )


def _find_course(db: Session, share_code: str) -> CourseRecord:
    code = share_code.strip().upper()
    if not re.fullmatch(SHARE_CODE_PATTERN, code):
        raise HTTPException(422, "Share codes are 5 letters/digits")
    course = get_course_by_share_code(db, code)
    if course is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, f"No course found for code {code}")
    return course
