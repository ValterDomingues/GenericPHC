#!/usr/bin/env python3
"""Replace Portuguese labels on a PHC 'Documentos por regularizar' letter with English."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from phc_pdf_label_map import LabelMap, translate_pdf

IDU_MAP = LabelMap(
    family="serif",
    translations={
        "Documento": "Document",
        "Número": "Number",
        "Data": "Date",
        "Data:": "Date:",
        "Vencimento": "Due date",
        "Valor Emissão": "Issue amount",
        "Valor por Regularizar": "Amount outstanding",
        "Idade": "Age",
        "Exmo.(s) Sr.(s):": "Dear Sir(s):",
        "Exmo.(s) Sr(s):": "Dear Sir(s):",
        "Assunto:Documentos por regularizar": "Subject: Outstanding documents",
        "Os n/ melhores cumprimentos.": "Our best regards.",
        "Vimos informar que se encontra (m) vencida (s) a (s) nossa (s) factura (s) abaixo indicada (s).": (
            "Please be advised that the invoice(s) listed below is/are overdue."
        ),
        "Lembramos que as condições de crédito oportunamente  acordadas se encontram ultrapassadas.": (
            "Please note that the credit terms previously agreed have been exceeded."
        ),
        "N/Factura": "Our Invoice",
        "N/Nt. Crédito": "Our Credit Note",
        "Total em Falta": "Balance due",
        "(CGD), indicando no campo referência o seu nome e número de cliente ou em alternativa envio de cheque": (
            "(CGD), quoting your name and customer number in the reference, or alternatively by cheque"
        ),
        "Se esta carta se tiver cruzado com o vosso pagamento, por favor não a considere.": (
            "If this letter has crossed with your payment, please disregard it."
        ),
        "Com os melhores cumprimentos": "Yours faithfully",
        "Atentamente": "Yours sincerely",
        "0000-000  IRLANDA": "0000-000  IRELAND",
    },
    prefixes=[
        (
            "Agradecemos o pagamento por transferência bancária para o nosso IBAN: ",
            "Please make payment by bank transfer to our IBAN: ",
        ),
    ],
)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Portuguese IDU letter PDF")
    parser.add_argument("dest", type=Path, help="Output PDF with English labels")
    parser.add_argument(
        "--report",
        type=Path,
        help="Optional JSON file listing applied replacements",
    )
    args = parser.parse_args()
    applied = translate_pdf(args.source, args.dest, IDU_MAP)
    print(f"Wrote {args.dest} ({len(applied)} label replacements)")
    for line in applied:
        print(f"  {line}")
    if args.report:
        args.report.write_text(json.dumps(applied, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
