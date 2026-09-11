#!/usr/bin/env python3
"""Replace Portuguese labels on a PHC Recibo PDF with English equivalents.

Data values (amounts, dates, names, ATCUD, certificate numbers) are left unchanged.
Requires PyMuPDF (pymupdf) and Liberation Sans (Arial-metric compatible).
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import pymupdf

FONT_REGULAR = "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf"
FONT_BOLD = "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"

# Exact span text → English. Longer keys first is not required because matching is exact.
SPAN_TRANSLATIONS: dict[str, str] = {
    "Recibo": "Receipt",
    "nº": "No.",
    "Serie:": "Series:",
    "2.ª Via": "Duplicate",
    "Exmo(a).Snr(a)": "To:",
    "Nº de Contribuinte:": "VAT No.:",
    "Data:": "Date:",
    "Observações:": "Remarks:",
    "Nesta data recebemos de V.Exas. o seguinte:": (
        "On this date we received from you the following:"
    ),
    "Documento": "Document",
    "Número": "Number",
    "Data": "Date",
    "Valor regularizado": "Amount settled",
    "N/Factura": "Our Invoice",
    "(Chamada para a rede fixa nacional)": "(Call to the national landline network)",
    "Num total de": "Total amount",
    "Desc.Fin.:": "Fin. disc.:",
    "São:": "Say:",
    "(Assinatura e Carimbo)": "(Signature and Stamp)",
    "Contribuinte Nº": "VAT No.",
    "Este documento so é válido após boa cobrança.": (
        "This document is only valid after cleared payment."
    ),
    "Desenvolvimento e fabrico de soluções inovadoras de automação, robótica e visão artificial": (
        "Development and manufacture of innovative automation, robotics and machine vision solutions"
    ),
    "Vinte e Sete Mil  Euros": "Twenty-Seven Thousand Euros",
    "Vinte e Sete Mil Euros": "Twenty-Seven Thousand Euros",
}

# Labels whose following same-line value should sit immediately after the English text.
JOIN_FOLLOWING_VALUE = {
    "Nº de Contribuinte:",
    "Contribuinte Nº",
}

CERT_PREFIX_PT = "Software PHC - Emitido por programa certificado nº "
CERT_PREFIX_EN = "PHC Software - Issued by certified program no. "

GRAY = (0.75, 0.75, 0.75)
WHITE = (1.0, 1.0, 1.0)
TEXT_FLAGS_BOLD = 16


def gray_rects(page: pymupdf.Page) -> list[pymupdf.Rect]:
    rects: list[pymupdf.Rect] = []
    for drawing in page.get_drawings():
        fill = drawing.get("fill")
        if fill and all(abs(c - 0.75) < 0.02 for c in fill[:3]):
            rects.append(pymupdf.Rect(drawing["rect"]))
    return rects


def fill_for_span(bbox: pymupdf.Rect, gray: list[pymupdf.Rect]) -> tuple[float, float, float]:
    center = pymupdf.Point((bbox.x0 + bbox.x1) / 2, (bbox.y0 + bbox.y1) / 2)
    for rect in gray:
        if rect.contains(center):
            return GRAY
    return WHITE


def translate_cert_line(text: str) -> str | None:
    if text.startswith(CERT_PREFIX_PT):
        return CERT_PREFIX_EN + text[len(CERT_PREFIX_PT) :]
    return None


def collect_spans(page: pymupdf.Page) -> list[dict]:
    spans: list[dict] = []
    for block in page.get_text("dict")["blocks"]:
        if block.get("type") != 0:
            continue
        for line in block.get("lines", []):
            for span in line.get("spans", []):
                spans.append(span)
    return spans


def same_baseline(a: dict, b: dict, tol: float = 1.5) -> bool:
    return abs(a["origin"][1] - b["origin"][1]) <= tol


def join_following_value(span: dict, spans: list[dict], used: set[int], start: int) -> tuple[str, pymupdf.Rect]:
    """Pull trailing same-line value spans into the replacement string."""
    joined = ""
    bbox = pymupdf.Rect(span["bbox"])
    for j in range(start + 1, len(spans)):
        if j in used:
            continue
        nxt = spans[j]
        nxt_text = nxt.get("text") or ""
        if not same_baseline(span, nxt):
            continue
        if nxt["origin"][0] < span["origin"][0] - 0.5:
            continue
        if SPAN_TRANSLATIONS.get(nxt_text) or translate_cert_line(nxt_text):
            break
        joined += nxt_text
        bbox |= pymupdf.Rect(nxt["bbox"])
        used.add(j)
    return joined, bbox


def translate_page(page: pymupdf.Page) -> list[str]:
    gray = gray_rects(page)
    replacements: list[dict] = []
    applied: list[str] = []
    spans = collect_spans(page)
    used: set[int] = set()

    for i, span in enumerate(spans):
        if i in used:
            continue
        text = span.get("text") or ""
        english = SPAN_TRANSLATIONS.get(text) or translate_cert_line(text)
        if not english or english == text:
            continue
        used.add(i)
        bbox = pymupdf.Rect(span["bbox"])
        if text in JOIN_FOLLOWING_VALUE:
            extra, extra_bbox = join_following_value(span, spans, used, i)
            extra = extra.strip()
            if extra:
                english = f"{english} {extra}".replace(":  ", ": ")
                bbox |= extra_bbox
        replacements.append(
            {
                "bbox": bbox,
                "origin": pymupdf.Point(span["origin"]),
                "size": float(span["size"]),
                "bold": bool(span.get("flags", 0) & TEXT_FLAGS_BOLD),
                "english": english,
                "portuguese": text,
                "fill": fill_for_span(bbox, gray),
            }
        )
        applied.append(f"{text!r} → {english!r}")

    for item in replacements:
        rect = pymupdf.Rect(item["bbox"])
        rect.x0 -= 0.6
        rect.y0 -= 0.4
        rect.x1 += 0.8
        rect.y1 += 0.6
        page.add_redact_annot(rect, fill=item["fill"])

    page.apply_redactions(images=pymupdf.PDF_REDACT_IMAGE_NONE)

    font_regular = pymupdf.Font(fontfile=FONT_REGULAR)
    font_bold = pymupdf.Font(fontfile=FONT_BOLD)
    writer = pymupdf.TextWriter(page.rect)
    for item in replacements:
        font = font_bold if item["bold"] else font_regular
        origin = item["origin"]
        if item["portuguese"] == "Contribuinte Nº":
            width = font.text_length(item["english"], fontsize=item["size"])
            origin = pymupdf.Point((43.5 + 535.5 - width) / 2, origin.y)
        writer.append(
            origin,
            item["english"],
            font=font,
            fontsize=item["size"],
        )
    writer.write_text(page)
    return applied


def translate_pdf(source: Path, dest: Path) -> list[str]:
    if not Path(FONT_REGULAR).is_file() or not Path(FONT_BOLD).is_file():
        raise SystemExit("Liberation Sans fonts not found (needed to match Arial metrics).")

    doc = pymupdf.open(source)
    applied: list[str] = []
    for page in doc:
        applied.extend(translate_page(page))
    dest.parent.mkdir(parents=True, exist_ok=True)
    doc.save(dest, garbage=4, deflate=True)
    doc.close()
    return applied


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Portuguese Recibo PDF")
    parser.add_argument("dest", type=Path, help="Output PDF with English labels")
    parser.add_argument(
        "--report",
        type=Path,
        help="Optional JSON file listing applied replacements",
    )
    args = parser.parse_args()
    applied = translate_pdf(args.source, args.dest)
    print(f"Wrote {args.dest} ({len(applied)} label replacements)")
    for line in applied:
        print(f"  {line}")
    if args.report:
        args.report.write_text(json.dumps(applied, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
