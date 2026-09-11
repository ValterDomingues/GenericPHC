#!/usr/bin/env python3
"""Check that the English Recibo PDF has translated labels and no Portuguese captions."""

from __future__ import annotations

import sys
from pathlib import Path

import pymupdf

ROOT = Path(__file__).resolve().parents[1]
EN_PDF = ROOT / "docs/recibo-en/samples/Normal_n__195_en.pdf"

REQUIRED_EN = [
    "Receipt",
    "Duplicate",
    "To:",
    "VAT No.:",
    "Date:",
    "Remarks:",
    "On this date we received from you the following:",
    "Document",
    "Number",
    "Amount settled",
    "Our Invoice",
    "Total amount",
    "Fin. disc.:",
    "Say:",
    "Twenty-Seven Thousand Euros",
    "(Signature and Stamp)",
    "This document is only valid after cleared payment.",
    "PHC Software - Issued by certified program no. 0006/AT",
    "Development and manufacture of innovative automation, robotics and machine vision solutions",
    "(Call to the national landline network)",
]

FORBIDDEN_PT = [
    "Recibo",
    "Exmo(a).Snr(a)",
    "Nº de Contribuinte:",
    "Observações:",
    "Nesta data recebemos de V.Exas. o seguinte:",
    "Valor regularizado",
    "N/Factura",
    "Num total de",
    "Desc.Fin.:",
    "São:",
    "(Assinatura e Carimbo)",
    "Contribuinte Nº",
    "Este documento so é válido após boa cobrança.",
    "Emitido por programa certificado",
    "Chamada para a rede fixa nacional",
    "2.ª Via",
    "Vinte e Sete Mil",
]


def main() -> int:
    if not EN_PDF.is_file():
        print(f"missing {EN_PDF}", file=sys.stderr)
        return 1
    text = "\n".join(page.get_text("text") for page in pymupdf.open(EN_PDF))
    errors: list[str] = []
    for needle in REQUIRED_EN:
        if needle not in text:
            errors.append(f"missing English label: {needle!r}")
    for needle in FORBIDDEN_PT:
        if needle in text:
            errors.append(f"Portuguese label still present: {needle!r}")
    if errors:
        print("FAIL")
        for err in errors:
            print(f"  {err}")
        return 1
    print(f"OK — {len(REQUIRED_EN)} English labels present, Portuguese captions absent")
    return 0


if __name__ == "__main__":
    sys.exit(main())
