#!/usr/bin/env python3
"""
scripts/generate_comprehensive_test_plan.py
Generates the authoritative Phase 5 Comprehensive SoC Verification Test Plan:
- Excel (.xlsx) with 13 mandatory columns + Traceability Matrix
- Formatted PDF (.pdf) for supervisor review
"""

import os
import sys
import zipfile
import subprocess
import shutil
import xml.sax.saxutils as saxutils

# Ensure local scripts dir is on sys.path
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

from test_plan_db import TEST_CASES

OUTPUT_DIR = "/home/student/Documents/090_honrors/CBP/test_plan_output"
XLSX_PATH = os.path.join(OUTPUT_DIR, "CBP_Comprehensive_Verification_Test_Plan.xlsx")
PDF_PATH = os.path.join(OUTPUT_DIR, "CBP_Comprehensive_Verification_Test_Plan.pdf")

os.makedirs(OUTPUT_DIR, exist_ok=True)

MANDATORY_HEADERS = [
    "Test Category and ID",
    "Test",
    "Test Description Detailed",
    "Checkpoints",
    "Internal or External",
    "Expected Path",
    "C Test Detailed Description",
    "C Test Expected Output",
    "SV Test Detailed Description",
    "SV Expected Output",
    "If External: Interface Needed",
    "Observable Input Signals for the Interface",
    "Observable Output Signals for the Interface"
]

TRACE_HEADERS = [
    "Test Category and ID",
    "Test Name",
    "Target RTL Module(s)",
    "Target Functional Feature",
    "Interface / Register / Address",
    "Verification Method (C / SV / Assertion)",
    "Coverage Target"
]

def col_idx_to_name(idx):
    """Convert 1-based index to Excel column name (A, B, ... Z, AA, AB...)."""
    name = ""
    while idx > 0:
        idx, rem = divmod(idx - 1, 26)
        name = chr(65 + rem) + name
    return name

def build_sheet_xml(headers, rows):
    """Build Sheet XML with inline strings, row styling, and column widths."""
    xml_parts = [
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n',
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" ',
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">\n',
        '  <cols>\n'
    ]
    # Set generous column widths
    for i in range(1, len(headers) + 1):
        w = 18 if i in [1, 2, 5, 11] else 38
        xml_parts.append(f'    <col min="{i}" max="{i}" width="{w}" customWidth="1"/>\n')
    xml_parts.append('  </cols>\n')
    xml_parts.append('  <sheetData>\n')

    # Row 1: Header
    xml_parts.append('    <row r="1" customHeight="1" ht="28">\n')
    for col_idx, h in enumerate(headers, 1):
        c_ref = f"{col_idx_to_name(col_idx)}1"
        esc_val = saxutils.escape(str(h))
        # s="1" is header style (bold, filled)
        xml_parts.append(f'      <c r="{c_ref}" t="inlineStr" s="1"><is><t>{esc_val}</t></is></c>\n')
    xml_parts.append('    </row>\n')

    # Data Rows
    for row_idx, r in enumerate(rows, 2):
        xml_parts.append(f'    <row r="{row_idx}">\n')
        for col_idx, val in enumerate(r, 1):
            c_ref = f"{col_idx_to_name(col_idx)}{row_idx}"
            esc_val = saxutils.escape(str(val))
            xml_parts.append(f'      <c r="{c_ref}" t="inlineStr" s="2"><is><t>{esc_val}</t></is></c>\n')
        xml_parts.append('    </row>\n')

    xml_parts.append('  </sheetData>\n')
    xml_parts.append('</worksheet>\n')
    return "".join(xml_parts)

def generate_xlsx(filepath):
    print(f"Generating Excel workbook: {filepath}")

    # Prepare sheet 1 rows
    sheet1_rows = []
    for tc in TEST_CASES:
        sheet1_rows.append([
            tc["cat_id"],
            tc["name"],
            tc["desc"],
            tc["checkpoints"],
            tc["scope"],
            tc["path"],
            tc["c_desc"],
            tc["c_out"],
            tc["sv_desc"],
            tc["sv_out"],
            tc["ext_if"],
            tc["ext_in"],
            tc["ext_out"]
        ])

    # Prepare sheet 2 rows (Traceability Matrix)
    sheet2_rows = []
    for tc in TEST_CASES:
        sheet2_rows.append([
            tc["cat_id"],
            tc["name"],
            tc["rtl_mod"],
            tc["feature"],
            tc["reg_addr"],
            tc["method"],
            tc["cov_target"]
        ])

    sheet1_xml = build_sheet_xml(MANDATORY_HEADERS, sheet1_rows)
    sheet2_xml = build_sheet_xml(TRACE_HEADERS, sheet2_rows)

    content_types = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
</Types>"""

    rels = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>"""

    wb_rels = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>"""

    workbook = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="Comprehensive Test Plan" sheetId="1" r:id="rId1"/>
    <sheet name="Traceability Matrix" sheetId="2" r:id="rId2"/>
  </sheets>
</workbook>"""

    styles = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="2">
    <font><sz val="11"/><name val="Calibri"/><color rgb="FF000000"/></font>
    <font><b/><sz val="11"/><name val="Calibri"/><color rgb="FFFFFFFF"/></font>
  </fonts>
  <fills count="3">
    <fill><patternFill patternType="none"/></fill>
    <fill><patternFill patternType="gray125"/></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FF1F497D"/><bgColor indexed="64"/></patternFill></fill>
  </fills>
  <borders count="2">
    <border><left/><right/><top/><bottom/><diagonal/></border>
    <border>
      <left style="thin"><color rgb="FFD9D9D9"/></left>
      <right style="thin"><color rgb="FFD9D9D9"/></right>
      <top style="thin"><color rgb="FFD9D9D9"/></top>
      <bottom style="thin"><color rgb="FFD9D9D9"/></bottom>
      <diagonal/>
    </border>
  </borders>
  <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
  <cellXfs count="3">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1">
      <alignment horizontal="center" vertical="center" wrapText="1"/>
    </xf>
    <xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1">
      <alignment horizontal="left" vertical="top" wrapText="1"/>
    </xf>
  </cellXfs>
</styleSheet>"""

    with zipfile.ZipFile(filepath, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", content_types)
        z.writestr("_rels/.rels", rels)
        z.writestr("xl/_rels/workbook.xml.rels", wb_rels)
        z.writestr("xl/workbook.xml", workbook)
        z.writestr("xl/styles.xml", styles)
        z.writestr("xl/worksheets/sheet1.xml", sheet1_xml)
        z.writestr("xl/worksheets/sheet2.xml", sheet2_xml)

    print(f"Successfully generated: {filepath}")

def generate_pdf(xlsx_path, pdf_path):
    print("Converting test plan to PDF format via LibreOffice headless...")
    cmd = [
        "soffice",
        "--headless",
        "--convert-to", "pdf",
        xlsx_path,
        "--outdir", os.path.dirname(pdf_path)
    ]
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
    if res.returncode != 0:
        print(f"Warning: soffice returned code {res.returncode}: {res.stderr}")
    else:
        print(f"Successfully generated: {pdf_path}")

def main():
    generate_xlsx(XLSX_PATH)
    # PDF generation is optional if soffice is installed
    if shutil.which("soffice"):
        generate_pdf(XLSX_PATH, PDF_PATH)

if __name__ == "__main__":
    main()
