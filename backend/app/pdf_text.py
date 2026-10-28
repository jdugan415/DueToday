"""Text extraction from uploaded syllabus PDFs.

Uses pypdf's *layout* mode, which keeps each table row on one line and
preserves the wide gaps between columns. The parser treats those gaps as
cell boundaries, so a schedule table parses like hand-pasted text.
"""

from __future__ import annotations

import io
import re

from pypdf import PdfReader
from pypdf.errors import PdfReadError

MAX_PDF_BYTES = 10 * 1024 * 1024
MAX_PAGES = 60  # syllabi are short; caps CPU time on pathological uploads
MIN_TEXT_CHARS = 20  # less than this is a scan, a cover image, or noise

SCANNED_MESSAGE = (
    "Could not extract text. If this is a scanned document, please copy and paste the text directly."
)
INVALID_MESSAGE = "That file isn't a readable PDF. Try exporting the syllabus to PDF again."
ENCRYPTED_MESSAGE = (
    "This PDF is password-protected. Open it, copy the schedule text, and paste it instead."
)


class PdfExtractionError(Exception):
    """Raised with a user-facing message when no usable text can be extracted."""


def looks_like_pdf(data: bytes) -> bool:
    # The header may follow a little junk; readers accept it within the first 1 KB.
    return b"%PDF-" in data[:1024]


def extract_pdf_text(data: bytes) -> str:
    try:
        reader = PdfReader(io.BytesIO(data))
        if reader.is_encrypted and not reader.decrypt(""):
            raise PdfExtractionError(ENCRYPTED_MESSAGE)
        pages = reader.pages[:MAX_PAGES]
        text = "\n".join(_page_text(page) for page in pages)
    except PdfExtractionError:
        raise
    except (PdfReadError, ValueError, KeyError, TypeError, OSError) as error:
        raise PdfExtractionError(INVALID_MESSAGE) from error
    except Exception as error:  # pypdf raises assorted errors on malformed files
        if "crypt" in str(error).lower():
            raise PdfExtractionError(ENCRYPTED_MESSAGE) from error
        raise PdfExtractionError(INVALID_MESSAGE) from error

    if sum(not c.isspace() for c in text) < MIN_TEXT_CHARS:
        raise PdfExtractionError(SCANNED_MESSAGE)
    return rejoin_hyphenated_cells(text)


_HYPHEN_BREAK_RE = re.compile(r"([A-Za-z]{2,})-(?=\s|$)")
_FRAGMENT_LINE_RE = re.compile(r"^\s*([a-z]{1,15})\s*$")


def rejoin_hyphenated_cells(text: str) -> str:
    """Undo words hyphenated across lines by narrow table cells.

    Layout extraction turns a wrapped cell like "Midterm Examina- / tion" into
    a row ending (or followed by a column gap) with "Examina-" and a next line
    holding only "tion". Merge the fragment back into the word and drop the
    leftover line.
    """
    lines = text.splitlines()
    out: list[str] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        fragment = _FRAGMENT_LINE_RE.match(lines[i + 1]) if i + 1 < len(lines) else None
        breaks = list(_HYPHEN_BREAK_RE.finditer(line))
        if fragment and len(breaks) == 1:
            start, end = breaks[0].span()
            line = line[:start] + breaks[0].group(1) + fragment.group(1) + line[end:]
            i += 1  # consume the fragment line
        out.append(line)
        i += 1
    return "\n".join(out)


def _page_text(page) -> str:
    try:
        return page.extract_text(extraction_mode="layout")
    except Exception:
        # Layout mode is stricter about odd fonts; plain mode still gets the words.
        return page.extract_text() or ""
