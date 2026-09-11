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

sys.path.insert(0, str(Path(__file__).resolve().parent))
from phc_pdf_label_map import LabelMap, translate_pdf

RECIBO_MAP = LabelMap(
    family="sans",
    translations={
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
    },
    join_following_value={"Nº de Contribuinte:", "Contribuinte Nº"},
    center_labels={"Contribuinte Nº"},
    prefixes=[
        (
            "Software PHC - Emitido por programa certificado nº ",
            "PHC Software - Issued by certified program no. ",
        ),
    ],
)


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
    applied = translate_pdf(args.source, args.dest, RECIBO_MAP)
    print(f"Wrote {args.dest} ({len(applied)} label replacements)")
    for line in applied:
        print(f"  {line}")
    if args.report:
        args.report.write_text(json.dumps(applied, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
