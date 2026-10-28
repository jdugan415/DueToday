"""Builds small, real PDFs for tests without extra dependencies.

``make_pdf`` places text with absolute coordinates, so tests can mimic how
syllabus schedules are laid out: a table whose columns (date, topic, due) are
separate text objects on the same baseline.
"""

from __future__ import annotations

Cell = tuple[float, float, str]  # (x, y, text) in PDF points; origin bottom-left


def _escape(text: str) -> str:
    return text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")


def make_pdf(pages: list[list[Cell]], *, font_size: int = 11) -> bytes:
    """Return the bytes of a PDF with one page per entry in ``pages``."""
    objects: list[bytes] = []

    def add(body: bytes) -> int:
        objects.append(body)
        return len(objects)

    catalog = add(b"")  # filled in once the page tree exists
    pages_id = add(b"")
    font = add(b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>")

    page_ids = []
    for cells in pages:
        ops = [f"BT /F1 {font_size} Tf 1 0 0 1 {x:g} {y:g} Tm ({_escape(t)}) Tj ET" for x, y, t in cells]
        stream = "\n".join(ops).encode("cp1252")
        content = add(b"<< /Length %d >>\nstream\n" % len(stream) + stream + b"\nendstream")
        page_ids.append(
            add(
                b"<< /Type /Page /Parent %d 0 R /MediaBox [0 0 612 792] "
                b"/Resources << /Font << /F1 %d 0 R >> >> /Contents %d 0 R >>" % (pages_id, font, content)
            )
        )

    kids = b" ".join(b"%d 0 R" % p for p in page_ids)
    objects[pages_id - 1] = b"<< /Type /Pages /Kids [%s] /Count %d >>" % (kids, len(page_ids))
    objects[catalog - 1] = b"<< /Type /Catalog /Pages %d 0 R >>" % pages_id

    out = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
    offsets = []
    for number, body in enumerate(objects, start=1):
        offsets.append(len(out))
        out += b"%d 0 obj\n" % number + body + b"\nendobj\n"
    xref = len(out)
    out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objects) + 1)
    out += b"".join(b"%010d 00000 n \n" % o for o in offsets)
    out += b"trailer\n<< /Size %d /Root %d 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objects) + 1, catalog, xref)
    return bytes(out)


def table_rows(rows: list[tuple[str, ...]], *, top: float = 720, columns=(72, 160, 400)) -> list[Cell]:
    """Lay out rows as a table: each column is its own text object."""
    cells: list[Cell] = []
    for i, row in enumerate(rows):
        y = top - i * 18
        cells += [(columns[c], y, text) for c, text in enumerate(row) if text]
    return cells


def blank_pdf(page_count: int = 1) -> bytes:
    """A PDF with pages but no text layer, like a scanned syllabus."""
    return make_pdf([[] for _ in range(page_count)])
