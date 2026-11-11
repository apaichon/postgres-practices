#!/usr/bin/env python3
"""Add running headers/page numbers without changing Chromium's Thai shaping."""
import io
from pathlib import Path
import sys
from pypdf import PdfReader, PdfWriter
from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor

source, target = map(Path, sys.argv[1:3])
reader = PdfReader(source)
writer = PdfWriter()
writer.clone_document_from_reader(reader)
total = len(writer.pages)
for index, page in enumerate(writer.pages):
    if index == 0:
        continue
    width, height = float(page.mediabox.width), float(page.mediabox.height)
    buffer = io.BytesIO()
    stamp = canvas.Canvas(buffer, pagesize=(width, height))
    stamp.setFillColor(HexColor('#50697d'))
    stamp.setFont('Helvetica', 7.5)
    stamp.drawString(48, height - 29, 'CLAIMSURE ACADEMY | SUPABASE SELF-HOSTED')
    stamp.setStrokeColor(HexColor('#cfdfec'))
    stamp.setLineWidth(0.5)
    stamp.line(48, height - 35, width - 48, height - 35)
    stamp.line(48, 36, width - 48, 36)
    stamp.drawString(48, 23, 'User Guide | Version 1.0 | 2026-11-09')
    stamp.drawRightString(width - 48, 23, f'{index + 1} / {total}')
    stamp.save()
    buffer.seek(0)
    page.merge_page(PdfReader(buffer).pages[0])
writer.add_metadata({'/Title': 'คู่มือใช้งาน Supabase Self-hosted สำหรับ ClaimSure',
                     '/Author': 'ClaimSure Academy', '/Subject': 'Studio, Auth, RLS, Data API, Storage and operations'})
with target.open('wb') as file:
    writer.write(file)
print(f'Created {target} ({total} pages)')
