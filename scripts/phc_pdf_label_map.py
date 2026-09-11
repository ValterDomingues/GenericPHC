"""Replace Portuguese captions on a PHC PDF with English, keeping data values."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

import pymupdf

FONT_FILES = {
    "sans": {
        "regular": "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
        "bold": "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
        "italic": "/usr/share/fonts/truetype/liberation/LiberationSans-Italic.ttf",
        "bolditalic": "/usr/share/fonts/truetype/liberation/LiberationSans-BoldItalic.ttf",
    },
    "serif": {
        "regular": "/usr/share/fonts/truetype/liberation/LiberationSerif-Regular.ttf",
        "bold": "/usr/share/fonts/truetype/liberation/LiberationSerif-Bold.ttf",
        "italic": "/usr/share/fonts/truetype/liberation/LiberationSerif-Italic.ttf",
        "bolditalic": "/usr/share/fonts/truetype/liberation/LiberationSerif-BoldItalic.ttf",
    },
}

GRAY = (0.75, 0.75, 0.75)
WHITE = (1.0, 1.0, 1.0)
TEXT_FLAGS_ITALIC = 2
TEXT_FLAGS_BOLD = 16


@dataclass
class LabelMap:
    translations: dict[str, str]
    family: str = "sans"
    join_following_value: set[str] = field(default_factory=set)
    center_labels: set[str] = field(default_factory=set)
    center_x0: float = 43.5
    center_x1: float = 535.5
    prefixes: list[tuple[str, str]] = field(default_factory=list)


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


def collect_spans(page: pymupdf.Page) -> list[dict]:
    spans: list[dict] = []
    for block in page.get_text("dict")["blocks"]:
        if block.get("type") != 0:
            continue
        for line in block.get("lines", []):
            spans.extend(line.get("spans", []))
    return spans


def same_baseline(a: dict, b: dict, tol: float = 1.5) -> bool:
    return abs(a["origin"][1] - b["origin"][1]) <= tol


def span_style(span: dict) -> str:
    name = span.get("font") or ""
    flags = int(span.get("flags") or 0)
    bold = bool(flags & TEXT_FLAGS_BOLD) or "Bold" in name
    italic = bool(flags & TEXT_FLAGS_ITALIC) or "Italic" in name
    if bold and italic:
        return "bolditalic"
    if bold:
        return "bold"
    if italic:
        return "italic"
    return "regular"


def english_for(text: str, label_map: LabelMap) -> str | None:
    if text in label_map.translations:
        return label_map.translations[text]
    for pt_prefix, en_prefix in label_map.prefixes:
        if text.startswith(pt_prefix):
            return en_prefix + text[len(pt_prefix) :]
    return None


def join_following_value(
    span: dict,
    spans: list[dict],
    used: set[int],
    start: int,
    label_map: LabelMap,
) -> tuple[str, pymupdf.Rect]:
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
        if english_for(nxt_text, label_map):
            break
        joined += nxt_text
        bbox |= pymupdf.Rect(nxt["bbox"])
        used.add(j)
    return joined, bbox


def translate_page(page: pymupdf.Page, label_map: LabelMap) -> list[str]:
    files = FONT_FILES[label_map.family]
    missing = [path for path in files.values() if not Path(path).is_file()]
    if missing:
        raise SystemExit(f"Font files not found: {missing}")

    gray = gray_rects(page)
    replacements: list[dict] = []
    applied: list[str] = []
    spans = collect_spans(page)
    used: set[int] = set()

    for i, span in enumerate(spans):
        if i in used:
            continue
        text = span.get("text") or ""
        english = english_for(text, label_map)
        if not english or english == text:
            continue
        used.add(i)
        bbox = pymupdf.Rect(span["bbox"])
        if text in label_map.join_following_value:
            extra, extra_bbox = join_following_value(span, spans, used, i, label_map)
            extra = extra.strip()
            if extra:
                english = f"{english} {extra}".replace(":  ", ": ")
                bbox |= extra_bbox
        replacements.append(
            {
                "bbox": bbox,
                "origin": pymupdf.Point(span["origin"]),
                "size": float(span["size"]),
                "style": span_style(span),
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

    fonts = {style: pymupdf.Font(fontfile=path) for style, path in files.items()}
    writer = pymupdf.TextWriter(page.rect)
    for item in replacements:
        font = fonts[item["style"]]
        origin = item["origin"]
        if item["portuguese"] in label_map.center_labels:
            width = font.text_length(item["english"], fontsize=item["size"])
            origin = pymupdf.Point(
                (label_map.center_x0 + label_map.center_x1 - width) / 2,
                origin.y,
            )
        writer.append(origin, item["english"], font=font, fontsize=item["size"])
    writer.write_text(page)
    return applied


def translate_pdf(source: Path, dest: Path, label_map: LabelMap) -> list[str]:
    doc = pymupdf.open(source)
    applied: list[str] = []
    for page in doc:
        applied.extend(translate_page(page, label_map))
    dest.parent.mkdir(parents=True, exist_ok=True)
    doc.save(dest, garbage=4, deflate=True)
    doc.close()
    return applied
