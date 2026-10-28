"""FastAPI entrypoint.

Run locally:  uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
"""

from __future__ import annotations

import os
import re
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from datetime import date

from fastapi import Depends, FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session

from . import __version__
from .database import create_course, get_course_by_share_code, get_db, init_db
from .models import SHARE_CODE_PATTERN, CourseCreate, CourseOut, ParseRequest, ParseResponse
from .parser import parse_syllabus


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


@app.post("/api/parse", response_model=ParseResponse)
def parse(request: ParseRequest) -> ParseResponse:
    return parse_syllabus(
        request.raw_text,
        course_code=request.course_code,
        reference_date=request.reference_date or date.today(),
        default_due_time=request.default_due_time,
    )


@app.post("/api/courses", response_model=CourseOut, status_code=status.HTTP_201_CREATED)
def share_course(payload: CourseCreate, db: Session = Depends(get_db)) -> CourseOut:
    return CourseOut.model_validate(create_course(db, payload))


@app.get("/api/courses/{share_code}", response_model=CourseOut)
def import_course(share_code: str, db: Session = Depends(get_db)) -> CourseOut:
    code = share_code.strip().upper()
    if not re.fullmatch(SHARE_CODE_PATTERN, code):
        raise HTTPException(422, "Share codes are 5 letters/digits")
    course = get_course_by_share_code(db, code)
    if course is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, f"No course found for code {code}")
    return CourseOut.model_validate(course)
