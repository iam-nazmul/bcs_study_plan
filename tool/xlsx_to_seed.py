"""Convert the BCS study-plan workbook into assets/study_plan.json.

Usage: python tool/xlsx_to_seed.py ../ForeignAffairs_Cadre_BCS_120_Days_StudyPlan.xlsx
Requires: pip install openpyxl

Header cells such as "6-7" were auto-converted to dates by Excel, so slot
columns are mapped by position: column C is 06:00, column S is 22:00.
"""
import datetime
import json
import pathlib
import sys

import openpyxl

FIRST_SLOT_COL = 2  # zero-based index of column C
FIRST_HOUR = 6
SLOT_COUNT = 17  # 06:00 .. 23:00
COMMENT_COL = FIRST_SLOT_COL + SLOT_COUNT

workbook = openpyxl.load_workbook(sys.argv[1])
subjects = {}
days = []
for sheet in workbook:
    for row in sheet.iter_rows(min_row=2, values_only=True):
        if row[COMMENT_COL + 2] and row[COMMENT_COL + 3]:
            subjects[row[COMMENT_COL + 2]] = row[COMMENT_COL + 3]
        if not isinstance(row[0], datetime.datetime):
            continue
        slots = [
            {"hour": FIRST_HOUR + i, "subject": value.strip()}
            for i, value in enumerate(row[FIRST_SLOT_COL:FIRST_SLOT_COL + SLOT_COUNT])
            if value
        ]
        days.append({
            "date": row[0].date().isoformat(),
            "comment": row[COMMENT_COL] or "",
            "slots": slots,
        })

out = pathlib.Path(__file__).resolve().parent.parent / "assets" / "study_plan.json"
out.parent.mkdir(exist_ok=True)
out.write_text(json.dumps({"subjects": subjects, "days": days}, indent=1))
print(f"Wrote {len(days)} days, {sum(len(d['slots']) for d in days)} slots, subjects={subjects}")
