#!/usr/bin/env python3
"""Check that the English IDU letter PDF has translated labels and no Portuguese captions."""

from __future__ import annotations

import sys
from pathlib import Path

import pymupdf

ROOT = Path(__file__).resolve().parents[1]
EN_PDF = ROOT / "docs/idu-en/samples/IduReport_en.pdf"

REQUIRED_EN = [
    "Dear Sir(s):",
    "IRELAND",
    "Date:",
    "Subject: Outstanding documents",
    "Our best regards.",
    "Please be advised that the invoice(s) listed below is/are overdue.",
    "Please note that the credit terms previously agreed have been exceeded.",
    "Document",
    "Number",
    "Due date",
    "Issue amount",
    "Amount outstanding",
    "Age",
    "Our Invoice",
    "Our Credit Note",
    "Balance due",
    "Please make payment by bank transfer to our IBAN:",
    "quoting your name and customer number in the reference",
    "If this letter has crossed with your payment, please disregard it.",
    "Yours faithfully",
    "Yours sincerely",
]

FORBIDDEN_PT = [
    "Exmo.(s)",
    "IRLANDA",
    "Assunto:",
    "Documentos por regularizar",
    "melhores cumprimentos",
    "Vimos informar",
    "factura",
    "Vencimento",
    "Valor Emissão",
    "Valor por Regularizar",
    "Idade",
    "N/Factura",
    "N/Nt. Crédito",
    "Total em Falta",
    "Agradecemos o pagamento",
    "número de cliente",
    "não a considere",
    "Atentamente",
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
