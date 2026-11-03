"""Build the Safeguard HTML/PDF references and self-contained UML SVGs.

Run with the dependencies in docs/requirements-docs.txt. This is documentation
tooling only; the application and tests do not require Python.
"""
from pathlib import Path
import html
import json
import math
from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, PageBreak, Table, TableStyle, Image, KeepTogether
from reportlab.graphics.shapes import Drawing, Rect, Line, String, Circle, Ellipse, Polygon
from reportlab.graphics import renderSVG

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
OUT = ROOT / "output" / "pdf"
OUT.mkdir(parents=True, exist_ok=True)
TEAL = colors.HexColor("#14665d")
INK = colors.HexColor("#172e34")
MUTED = colors.HexColor("#617672")
PALE = colors.HexColor("#edf4ee")
EDGE = colors.HexColor("#b9cdc4")


def text(d, x, y, lines, size=10, bold=False, anchor="middle", color=INK):
    for i, line in enumerate(lines.split("\n")):
        d.add(String(x, y - i * (size + 3), line, fontName="Helvetica-Bold" if bold else "Helvetica", fontSize=size, fillColor=color, textAnchor=anchor))


def box(d, x, y, w, h, title, lines="", stereotype=""):
    d.add(Rect(x, y, w, h, rx=5, ry=5, fillColor=PALE, strokeColor=EDGE, strokeWidth=0.8))
    top = y + h - 18
    if stereotype:
        text(d, x + w / 2, top, stereotype, 8, color=MUTED)
        top -= 15
    text(d, x + w / 2, top, title, 10, True)
    if lines:
        d.add(Line(x, top - 9, x + w, top - 9, strokeColor=EDGE, strokeWidth=0.6))
        text(d, x + 9, top - 25, lines, 8, anchor="start")


def arrow(d, x1, y1, x2, y2, label="", lx=None, ly=None, dashed=False):
    line = Line(x1, y1, x2, y2, strokeColor=TEAL, strokeWidth=0.9)
    if dashed:
        line.strokeDashArray = [3, 3]
    d.add(line)
    angle = math.atan2(y2 - y1, x2 - x1)
    points = [x2, y2, x2 - 6 * math.cos(angle - .45), y2 - 6 * math.sin(angle - .45), x2 - 6 * math.cos(angle + .45), y2 - 6 * math.sin(angle + .45)]
    d.add(Polygon(points, fillColor=TEAL, strokeColor=TEAL, strokeWidth=.4))
    if label:
        text(d, lx if lx is not None else (x1 + x2) / 2, ly if ly is not None else (y1 + y2) / 2 + 8, label, 8, color=MUTED)


def person(d, x, y, label):
    d.add(Circle(x, y + 16, 6, strokeColor=TEAL, fillColor=None))
    for x1, y1, x2, y2 in [(x, y + 10, x, y - 8), (x - 10, y + 4, x + 10, y + 4), (x, y - 8, x - 9, y - 19), (x, y - 8, x + 9, y - 19)]:
        d.add(Line(x1, y1, x2, y2, strokeColor=TEAL))
    text(d, x, y - 31, label, 8)


def use_cases():
    d = Drawing(480, 355)
    d.add(Rect(85, 10, 310, 335, rx=6, ry=6, strokeColor=EDGE, fillColor=colors.white))
    text(d, 240, 329, "Safeguard assurance boundary", 10, True)
    for y, label in [(290, "Create / revise candidate\nSubmit laboratory evidence"), (225, "Independent decisions\nand action closure"), (160, "Field evidence\nand safety concerns"), (95, "Role governance\nand escalation oversight"), (35, "Inspect / export history\nand overdue escalation")]:
        d.add(Ellipse(240, y, 128, 24, fillColor=PALE, strokeColor=EDGE))
        text(d, 240, y + 4, label, 9)
    for x, y, label in [(35, 290, "Engineer"), (35, 160, "Analyst"), (445, 225, "Reviewer"), (445, 95, "Safety lead"), (445, 35, "Observer")]:
        person(d, x, y, label)
        d.add(Line(x + 12 if x < 100 else x - 12, y, 112 if x < 100 else 368, y, strokeColor=TEAL, strokeWidth=.8))
    return d


def deployment():
    d = Drawing(480, 265)
    d.add(Rect(175, 10, 300, 245, rx=7, ry=7, fillColor=None, strokeColor=EDGE, strokeDashArray=[4, 3]))
    text(d, 325, 238, "Local Node.js process", 10, True)
    box(d, 5, 65, 145, 90, "Browser workspace", "Role-specific views\nEvidence and decisions", "<<device>>")
    box(d, 195, 65, 125, 90, "Signer service", "HTTP / ethers\nPrototype test keys", "<<component>>")
    box(d, 195, 175, 260, 45, "SafeguardAssurance.sol", stereotype="<<executionEnvironment>> Hardhat EVM")
    box(d, 350, 65, 110, 90, "Evidence files", "JSON / preimages\nReview exports", "<<artifact>>")
    arrow(d, 150, 110, 195, 110, "HTTP", ly=120)
    arrow(d, 257, 155, 257, 175)
    text(d, 330, 162, "Signed transactions / state / events", 8, color=MUTED)
    arrow(d, 320, 110, 350, 110)
    text(d, 335, 95, "hash / read", 7, color=MUTED)
    text(d, 240, 30, "Production: replace test signing, storage and local EVM with governed infrastructure.", 8, color=MUTED)
    return d


def classes():
    d = Drawing(480, 320)
    box(d, 0, 205, 145, 105, "SafeguardAssurance", "roles / contributors\nimmutable safetyLead\nconstant RULE_HASH")
    box(d, 170, 190, 145, 120, "Candidate", "engineer / buildHash\nscopeHash / stage\nbuildRevision\nevidenceRevision\nopenActions / limitedEver")
    box(d, 340, 205, 140, 105, "LabEvidence", "buildRevision / submitter\ntrials / successes\naccepted / digest")
    box(d, 0, 10, 145, 125, "Decision", "stage / reviewer\nbuild + evidence revision\nsnapshotHash\nrationaleHash\ndecidedAt / validUntil")
    box(d, 170, 10, 145, 125, "Action", "owner / reporter / closedBy\nopenedAt / dueAt\nreason / evidenceHash\nclosed / escalated\nresolution / rationale hash")
    box(d, 340, 10, 140, 125, "FieldEvidence", "buildRevision / submitter\nbaseline + post counts\nengaged miles\nquality + activation flags\ndigest")
    arrow(d, 145, 255, 170, 255)
    arrow(d, 315, 255, 340, 255)
    arrow(d, 170, 200, 90, 135, "1 / 0..*", lx=113, ly=174)
    arrow(d, 242, 190, 242, 135, "1 / 0..*", lx=276, ly=157)
    arrow(d, 315, 200, 405, 135, "1 / 0..8", lx=379, ly=174)
    return d


def sequence():
    d = Drawing(480, 340)
    lanes = [(35, "Engineer"), (135, "Reviewer"), (235, "Signer service"), (340, "Contract"), (445, "Analyst")]
    for x, label in lanes:
        d.add(Rect(x - 33, 310, 66, 25, fillColor=PALE, strokeColor=EDGE))
        text(d, x, 319, label, 8, True)
        d.add(Line(x, 20, x, 310, strokeColor=EDGE, strokeDashArray=[3, 3]))
    arrow(d, 35, 282, 235, 282, "Import laboratory evidence", ly=291)
    arrow(d, 235, 253, 340, 253, "recordLab x6", ly=262)
    arrow(d, 135, 224, 235, 224, "Rationale + expiry", ly=233)
    arrow(d, 235, 195, 340, 195, "approveLimited", ly=204)
    arrow(d, 445, 166, 340, 166, "Adverse field data", ly=175)
    arrow(d, 340, 137, 235, 137, "Reopen + action", ly=146, dashed=True)
    arrow(d, 445, 108, 340, 108, "Improved field data", ly=117)
    arrow(d, 135, 79, 340, 79, "closeAction via service", ly=88)
    arrow(d, 135, 42, 340, 42, "Separate approveExpansion via service", ly=51)
    return d


def states():
    d = Drawing(480, 270)
    for x, title in [(15, "Draft"), (185, "Limited"), (355, "Expanded")]:
        box(d, x, 195, 110, 40, title)
    box(d, 185, 35, 110, 55, "Reopened", "No current authority")
    d.add(Circle(25, 256, 4, fillColor=INK, strokeColor=INK))
    arrow(d, 25, 252, 55, 235)
    arrow(d, 125, 215, 185, 215, "lab + review", ly=227)
    arrow(d, 295, 215, 355, 215, "field + review", ly=227)
    arrow(d, 240, 195, 240, 90, "change / concern", lx=293, ly=150)
    arrow(d, 410, 195, 295, 90, "change / concern", lx=407, ly=137)
    d.add(Line(185, 62, 155, 62, strokeColor=TEAL))
    d.add(Line(155, 62, 155, 195, strokeColor=TEAL))
    arrow(d, 155, 195, 185, 195)
    text(d, 90, 118, "New limited\njudgment", 8, color=MUTED)
    d.add(Line(295, 62, 457, 62, strokeColor=TEAL))
    d.add(Line(457, 62, 457, 185, strokeColor=TEAL))
    arrow(d, 457, 185, 435, 195)
    text(d, 380, 36, "Separate expansion judgment\n[eligible evidence; actions closed]", 8, color=MUTED)
    return d


def activity():
    d = Drawing(480, 235)
    box(d, 140, 190, 200, 35, "Current-build field evidence")
    arrow(d, 240, 190, 240, 173)
    d.add(Polygon([240, 173, 310, 150, 240, 127, 170, 150], fillColor=PALE, strokeColor=EDGE))
    text(d, 240, 147, "Evaluate rules", 9, True)
    for x, label in [(5, "Failed"), (170, "Inconclusive"), (335, "Eligible for review")]:
        box(d, x, 65, 140, 35, label)
    d.add(Line(170, 150, 75, 150, strokeColor=TEAL))
    arrow(d, 75, 150, 75, 100)
    text(d, 75, 119, "serious / inactive / rate", 7, color=MUTED)
    arrow(d, 240, 127, 240, 100)
    text(d, 240, 110, "quality / exposure gap", 7, color=MUTED)
    d.add(Line(310, 150, 405, 150, strokeColor=TEAL))
    arrow(d, 405, 150, 405, 100)
    text(d, 405, 119, "all checks met", 7, color=MUTED)
    box(d, 60, 5, 260, 35, "Owned action / independent disposition")
    arrow(d, 75, 65, 140, 40)
    arrow(d, 240, 65, 240, 40)
    box(d, 340, 5, 135, 35, "Reviewer judgment")
    arrow(d, 405, 65, 405, 40)
    return d


DIAGRAMS = {"use-cases": use_cases(), "deployment": deployment(), "classes": classes(), "sequence": sequence(), "states": states(), "activity": activity()}
for name, drawing in DIAGRAMS.items():
    renderSVG.drawToFile(drawing, str(DOCS / "uml" / f"{name}.svg"))

styles = getSampleStyleSheet()
styles.add(ParagraphStyle("BodySafe", fontName="Helvetica", fontSize=9.6, leading=14.1, textColor=INK, spaceAfter=10, allowWidows=0, allowOrphans=0))
styles.add(ParagraphStyle("SectionSafe", fontName="Helvetica-Bold", fontSize=11, leading=15, textColor=TEAL, spaceBefore=7, spaceAfter=8, keepWithNext=True))
styles.add(ParagraphStyle("PageSafe", fontName="Helvetica-Bold", fontSize=22, leading=27, textColor=INK, spaceAfter=18, keepWithNext=True))
styles.add(ParagraphStyle("CellSafe", fontName="Helvetica", fontSize=8.4, leading=11.8, textColor=INK))
styles.add(ParagraphStyle("CaptionSafe", fontName="Helvetica", fontSize=8, leading=11, textColor=MUTED, spaceBefore=5, spaceAfter=13))
styles.add(ParagraphStyle("CodeSafe", fontName="Courier", fontSize=8.2, leading=12, textColor=TEAL, backColor=PALE, borderPadding=10, spaceBefore=6, spaceAfter=18))
styles.add(ParagraphStyle("NoteSafe", parent=styles["BodySafe"], fontSize=9, leading=13, textColor=TEAL, backColor=PALE, borderPadding=10, spaceBefore=7, spaceAfter=15))


def p(value, style="BodySafe"):
    return Paragraph(html.escape(value).replace("\n", "<br/>"), styles[style])


def pdf_block(block, width):
    kind = block["type"]
    if kind in {"p", "h", "code", "note"}:
        return [p(block["text"], {"p": "BodySafe", "h": "SectionSafe", "code": "CodeSafe", "note": "NoteSafe"}[kind])]
    if kind == "steps":
        return [p(f"{i}. {item}") for i, item in enumerate(block["items"], 1)]
    if kind == "table":
        rows = [[p(cell, "CellSafe") for cell in row] for row in block["rows"]]
        table = Table(rows, colWidths=[width * part for part in block["widths"]], repeatRows=1, hAlign="LEFT")
        table.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, 0), PALE), ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ("LINEBELOW", (0, 0), (-1, -1), .4, EDGE), ("LEFTPADDING", (0, 0), (-1, -1), 8),
            ("RIGHTPADDING", (0, 0), (-1, -1), 8), ("TOPPADDING", (0, 0), (-1, -1), 8), ("BOTTOMPADDING", (0, 0), (-1, -1), 8)]))
        return [table, Spacer(1, 13)]
    if kind == "diagram":
        d = DIAGRAMS[block["name"]]
        return [KeepTogether([d, p(block["caption"], "CaptionSafe")])]
    if kind == "image":
        source = ROOT / block["path"]
        if not source.exists():
            return [p("See the live workspace for this view. " + block["caption"], "CaptionSafe")]
        image = Image(str(source))
        image.drawHeight = min(160, width / image.imageWidth * image.imageHeight)
        image.drawWidth = image.drawHeight / image.imageHeight * image.imageWidth
        return [image, p(block["caption"], "CaptionSafe")]
    raise ValueError(kind)


def html_block(block):
    kind = block["type"]
    if kind in {"p", "h", "code", "note"}:
        tag = {"p": "p", "h": "h3", "code": "pre", "note": "aside"}[kind]
        return f"<{tag}>{html.escape(block['text'])}</{tag}>"
    if kind == "steps":
        return "<ol>" + "".join(f"<li>{html.escape(s)}</li>" for s in block["items"]) + "</ol>"
    if kind == "table":
        return "<table>" + "".join("<tr>" + "".join(f"<{'th' if i == 0 else 'td'}>{html.escape(s)}</{'th' if i == 0 else 'td'}>" for s in row) + "</tr>" for i, row in enumerate(block["rows"])) + "</table>"
    if kind == "diagram":
        return f'<figure><img src="uml/{block["name"]}.svg" alt="{html.escape(block["caption"])}"><figcaption>{html.escape(block["caption"])}</figcaption></figure>'
    if kind == "image":
        return f'<figure><img src="../{block["path"]}" alt="Workspace view"><figcaption>{html.escape(block["caption"])}</figcaption></figure>'
    raise ValueError(kind)


def footer(canvas, doc):
    canvas.saveState()
    w, h = A4
    canvas.setStrokeColor(EDGE)
    canvas.line(48, 42, w - 48, 42)
    canvas.setFont("Helvetica", 8)
    canvas.setFillColor(MUTED)
    canvas.drawString(48, 27, "SAFEGUARD  /  RELEASE GOVERNANCE")
    canvas.drawRightString(w - 48, 27, f"{doc.page}")
    canvas.setFont("Helvetica-Bold", 8)
    canvas.drawString(48, h - 30, "SAFEGUARD")
    canvas.restoreState()


content = json.loads((DOCS / "content.json").read_text(encoding="utf-8"))
for key, document in content.items():
    story = []
    sections = []
    for i, page in enumerate(document["pages"]):
        if i:
            story.append(PageBreak())
        else:
            story.extend([p(document["subtitle"], "SectionSafe"), p("Prototype reference | Version 1.0 | 3 November 2026", "CaptionSafe")])
        story.append(p(page["title"], "PageSafe"))
        for block in page["blocks"]:
            story.extend(pdf_block(block, A4[0] - 96))
        sections.append(f'<section id="section-{i + 1}"><span class="kicker">{i + 1:02d} / SAFEGUARD</span><h2>{html.escape(page["title"])}</h2>' + "".join(html_block(b) for b in page["blocks"]) + "</section>")
    pdf = SimpleDocTemplate(str(OUT / document["filename"]), pagesize=A4, leftMargin=48, rightMargin=48, topMargin=55, bottomMargin=60,
                            title=document["title"] + " - " + document["subtitle"], author="Safeguard")
    pdf.build(story, onFirstPage=footer, onLaterPages=footer)
    nav = "".join(f'<a href="#section-{i + 1}">{i + 1:02d}. {html.escape(page["title"])}</a>' for i, page in enumerate(document["pages"]))
    css = "body{margin:0;background:#f4f5f1;color:#172e34;font:15px/1.75 Segoe UI,Arial,sans-serif}header{background:#142e33;color:white;padding:38px max(5%,calc((100% - 1000px)/2))}header h1{font:46px Georgia,serif;margin:0}header p{margin:8px 0 0;color:#b9d5cd}main{max-width:1000px;padding:30px 5%;margin:auto}nav{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-bottom:30px}a{color:#14665d}section{padding:32px;background:white;border:1px solid #dce3df;border-radius:7px;margin:25px 0}h2{font:30px/1.25 Georgia,serif;margin:12px 0 24px}h3{font-size:17px;color:#14665d}.kicker{font-size:10px;letter-spacing:2px;color:#14665d}table{width:100%;border-collapse:collapse;font-size:13px;margin:24px 0}th,td{text-align:left;vertical-align:top;padding:13px;border-bottom:1px solid #dce3df}th{background:#edf4ee}aside,pre{padding:20px;background:#edf4ee;border-left:3px solid #14665d;margin:22px 0}pre{overflow:auto;font-size:13px}figure{margin:25px 0}figure img{width:100%;max-height:580px;object-fit:contain}figcaption{font-size:12px;color:#617672;margin-top:12px}li{margin-bottom:14px}@media(max-width:650px){nav{grid-template-columns:1fr}section{padding:20px}table{font-size:11px}td,th{padding:8px}}@media print{header,nav{display:none}body{background:white}section{break-before:page;border:none;padding:0}main{max-width:none;padding:0}}"
    html_out = f'<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Safeguard | {html.escape(document["subtitle"])}</title><style>{css}</style></head><body><header><h1>Safeguard</h1><p>{html.escape(document["subtitle"])}</p></header><main><nav>{nav}</nav>{"".join(sections)}</main></body></html>'
    (DOCS / ("solution.html" if key == "solution" else "user-guide.html")).write_text(html_out, encoding="utf-8")
    print(OUT / document["filename"])

# Export a page image of every PDF for required visual inspection.
import pymupdf
renders = ROOT / "tmp" / "pdfs" / "rendered"
renders.mkdir(parents=True, exist_ok=True)
for document in content.values():
    with pymupdf.open(OUT / document["filename"]) as pdf:
        print(document["filename"], "pages:", len(pdf))
        for i, page in enumerate(pdf):
            page.get_pixmap(matrix=pymupdf.Matrix(1.15, 1.15)).save(renders / f'{Path(document["filename"]).stem}-{i + 1:02d}.png')
