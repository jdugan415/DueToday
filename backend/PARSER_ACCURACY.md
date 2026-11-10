# Syllabus accuracy audit — 2026-11-10

This is a schedule-focused audit of five public university syllabi, not an
overall accuracy score or a claim that whole-document parsing is complete.
Three original PDFs were extracted with the app's `extract_pdf_text`; their
schedule pages were also rendered for visual inspection. Two HTML schedules
were read and converted to plain text. Parsing used `reference_date=2025-08-24`
to match the source semester. Source downloads and extracted text stayed in
temporary storage. Only invented reproductions are added to tests.

The repository's CSC3380 PDF identifies itself as a fictional sample and is
excluded from the five real sources.

## Sources and findings

| Source | Checked section | Findings |
| --- | --- | --- |
| [Columbia, Science of Psychology, Fall 2025](https://psychology.columbia.edu/sites/psychology.columbia.edu/files/content/Fall%202025%20Syllabus%20UN1001s2%20DeMoya%20The%20Science%20of%20Psychology.pdf) | Course Schedule, PDF pages 7–8 | Literal word-space tabs stripped exam numbers. Fixed: all four numbered exams keep their numbers and dates. The wrapped projected final-exam date remains unresolved. |
| [Ohio State, CHEM 1206, Autumn 2025](https://chemistry.osu.edu/sites/default/files/2026-01/1206%20Syllabus%20Ricciardo%208AM%20AU25.pdf) | Class Schedule and Exam Schedule, PDF page 10 | Weekly exam windows duplicated exact exam-table dates. Exact dates now supersede matching overview windows. Other windows retain their end date with confidence below 0.8. Final-exam time remains 08:00. |
| [Purdue, HIST 104, Fall 2025](https://cla.purdue.edu/academic/history/documents/syllabus-fall-documents/fall-2025/fall-2025-syllabus-accessible/history-104-stukey.html) | Weekly schedule through Week 15 | Explicit quiz, essay, and project deadlines retained their stated times. Week headers do not override explicit due dates. No new issue in these checked rows. The introductory quiz deadline conflicts with the schedule; human review is still needed. |
| [Southern Utah, BIOL 1610-01, Fall 2025](https://my.suu.edu/syllabus/202530/BIOL-1610-01/) | Course Outline | “No class” previously suppressed testing-center exam rows. Fixed: exams remain, their stated testing-window end wins over the meeting date, and confidence requests review. Added day-first month dates. The final's outline date conflicts with its availability window elsewhere in the document. |
| [UT Arlington, PSYC 1315-001, Fall 2025](https://cdn.prod.web.uta.edu/-/media/project/website/science/psychology/documents/degree-programs/course-syllabi/fall-2025/1315_001_hernandez_fall_2025.pdf) | Course Schedule, PDF pages 9–10 | Numbered plural assignment groups were dropped. They are now retained; ordinary plural policy headings remain excluded. Chapter ranges and time labels that wrap onto another line remain incomplete, as does the wrapped final-exam row. |

## Regression coverage

Run from `backend/`:

```bash
python -m pytest -q test_parser.py test_pdf.py
```

`test_parser.py` includes five synthetic schedule patterns with exact expected
titles, dates, and times, plus checks for testing-window review confidence,
day-first dates with points, plural-policy exclusions, and overview/exact-date
consolidation. `test_pdf.py` uploads a generated PDF with tab-encoded word
spaces through the real API and checks the returned exam title and date.
Existing weight, point, time, and confidence tests continue to run.

## Remaining work before claiming the original accuracy task complete

- Reconstruct wrapped PDF cells without joining unrelated rows or columns.
  Examples above include a month on one line and its day on the next, or an
  assignment's chapter range and due time split across lines.
- Broaden deliverable vocabulary: learning reflections and research
  participation are not consistently recognized by the current keyword parser.
- Reduce false positives from full-document policy prose and prevent stale
  schedule dates from attaching to policy fragments. The chemistry full-PDF
  run exposed these beyond the schedule-focused regression cases.
- Handle contradictory dates explicitly rather than silently choosing between
  policy prose, availability windows, and schedule tables.
- Collect additional student-provided syllabi from more departments, review
  every expected task, and record false positives and missed tasks per document.
  Do not commit classmates' originals or personal information.

This pass fixes the listed reproducible patterns. It does not close those
remaining audit findings or establish a universal parser accuracy percentage.
