"""Python spec of the VFP helpers in prg/fuelstar_impfs.prg.

Mirrors date/hour parsing, SQL literals, IVA buckets, payment accumulation,
ATCUD, document-type mapping and FI cost fields so the import can be tested
without Visual FoxPro / PHC / Chilkat.
"""

from __future__ import annotations

from datetime import date, time
from typing import Optional


ESC_RATE = 200.482


def format_date(value: Optional[str]) -> Optional[date]:
    """Mirror of func_formatDate. ISO ``YYYY-MM-DD…`` → date; invalid → None."""
    text = "" if value is None else str(value).strip()
    if len(text) < 10:
        return None
    try:
        year = int(text[0:4])
        month = int(text[5:7])
        day = int(text[8:10])
        return date(year, month, day)
    except ValueError:
        return None


def format_hour(value: Optional[str]) -> str:
    """Mirror of func_formatHour. ``…T12:34:56`` → ``12:34:56``."""
    text = "" if value is None else str(value).strip()
    pos = text.find("T")
    if pos < 0:
        return ""
    return text[pos + 1 : pos + 9]


def format_string(value: Optional[str]) -> str:
    """Mirror of func_formatString: apostrophe → acute, control chars, spaces."""
    text = "" if value is None else str(value)
    text = text.replace("'", "´").replace("\x02", " ").replace("\x01", " ")
    while "  " in text:
        text = text.replace("  ", " ")
    return text.strip()


def sql_lit(value: Optional[str]) -> str:
    """Mirror of func_sqlLit. Doubles single quotes for TEXTMERGE SQL."""
    text = "" if value is None else str(value).strip()
    return "'" + text.replace("'", "''") + "'"


def sql_num(value, decimals: int = 4) -> str:
    """Mirror of func_sqlNum (Adec_Tr-style decimal literal)."""
    if value is None:
        return "0"
    return f"{float(value):.{decimals}f}"


def get_tab_iva(taxa, table=None) -> int:
    """Mirror of func_getTabIva: PHC taxasiva.codigo for a given rate."""
    table = table if table is not None else {6: 1, 23: 2, 13: 3, 0: 4}
    try:
        key = int(round(float(taxa)))
    except (TypeError, ValueError):
        return 0
    return int(table.get(key, 0))


def iva_bucket(taxa: float) -> Optional[str]:
    """Header IVA columns used in func_prepDocs (PT rates → ivatx1..4)."""
    try:
        rate = int(round(float(taxa)))
    except (TypeError, ValueError):
        return None
    return {6: "iva1", 23: "iva2", 13: "iva3", 0: "iva4"}.get(rate)


def nif_from_xml(raw) -> str:
    """NIF as text (GetChildContent), not GetChildIntValue (drops letters/zeros)."""
    if raw is None:
        return ""
    return str(raw).strip()


def build_atcud(atcud: str, numero_serie: int) -> str:
    """Append ``-n`` when the XML ATCUD has no hyphen yet."""
    text = (atcud or "").strip()
    if not text:
        return str(numero_serie)
    if "-" in text:
        return text
    return f"{text}-{numero_serie}"


DOC_MAP = {
    "190": ("DC", True),
    "192": ("CI", True),
    "248": ("RS", True),
    "298": ("RS", False),
    "B": ("ND", True),
    "C": ("NC", True),
    "D": ("FT_tran", True),
    "F": ("FT_guia", True),
    "G": ("FR", True),
    "W": ("FS", True),
    "184": ("GT", True),
    "181": ("GR", False),
}


def doc_type(cod: str) -> str:
    """Mirror of func_docType: PHC tipo only when importPHC is true."""
    key = (cod or "").strip()
    info = DOC_MAP.get(key)
    if not info or not info[1]:
        return ""
    return info[0]


def serie_to_import(cod: str) -> int:
    """Mirror of func_serieToImport: 1=import, 2=mapped-but-skip, 0=unknown."""
    key = (cod or "").strip()
    info = DOC_MAP.get(key)
    if not info:
        return 0
    return 1 if info[1] else 2


def tipo_doc_width(value: str, width: int = 10) -> str:
    """crsDocCab.TipoDoc must fit FT_tran / FT_guia (original was C(2))."""
    return (value or "")[:width]


def accumulate_payment(totals: dict, codigo: int, valor: float, desc: str, sinal: int) -> dict:
    """Running payment totals WITHOUT Abs(running+new)*sinal (original NC bug)."""
    out = dict(totals)
    amt = abs(float(valor)) * int(sinal)
    if codigo == 1:
        out["numerario"] = out.get("numerario", 0.0) + amt
    elif codigo == 2:
        out["cheque"] = out.get("cheque", 0.0) + amt
    elif codigo == 3:
        out["multibanco"] = out.get("multibanco", 0.0) + amt
        out["mbterm"] = "OPT" if (desc or "").strip().endswith("OPT") else "AS"
    elif codigo == 4:
        out["trfbanc"] = out.get("trfbanc", 0.0) + amt
    return out


def accumulate_payment_original(totals: dict, codigo: int, valor: float, desc: str, sinal: int) -> dict:
    """Original: Abs(running + new) * sinal — breaks a second cash line on NC."""
    out = dict(totals)
    field = {1: "numerario", 2: "cheque", 3: "multibanco", 4: "trfbanc"}.get(codigo)
    if not field:
        return out
    out[field] = abs(out.get(field, 0.0) + float(valor)) * int(sinal)
    if codigo == 3:
        out["mbterm"] = "OPT" if (desc or "").strip().endswith("OPT") else "AS"
    return out


def line_unit_price(punit_iliq: float, desc_valor_total: float, quantidade: float) -> float:
    """PrecoUnitario = PUnitIliqIva - DescontoValor (per-unit discount)."""
    qtd = float(quantidade)
    desc_unit = 0.0 if qtd == 0 else round(float(desc_valor_total) / qtd, 2)
    return float(punit_iliq) - desc_unit


def line_valor_movimento(
    punit_iliq: float, desc1: float, desc2: float, quantidade: float, desc_valor_total: float
) -> float:
    """ValorLinha for Area=M (percent discounts then ValorTotalDesconto)."""
    return (
        float(punit_iliq)
        * (1 - float(desc1) / 100.0)
        * (1 - float(desc2) / 100.0)
        * float(quantidade)
        - float(desc_valor_total)
    )


def apply_nc_sign(valor: float, sinal: int) -> float:
    return abs(float(valor)) * int(sinal)


def fi_costs(pcusto: float, quantidade: float) -> dict:
    """FI custo/ecusto/pcp/epcp from the SE lot (original left them 0)."""
    qtd = float(quantidade)
    epcp = float(pcusto)
    ecusto = round(epcp * qtd, 4)
    return {
        "epcp": epcp,
        "pcp": round(epcp * ESC_RATE, 4),
        "ecusto": ecusto,
        "custo": round(ecusto * ESC_RATE, 4),
    }


def header_cost_totals(lines) -> dict:
    tot_qtt = sum(float(l["quantidade"]) for l in lines)
    tot_custo = sum(float(l["pcusto"]) * float(l["quantidade"]) for l in lines)
    return {
        "totqtt": round(tot_qtt, 4),
        "ecusto": round(tot_custo, 4),
        "custo": round(tot_custo * ESC_RATE, 4),
    }


def imported_name(fname: str) -> str:
    return fname + ".importado"


def should_mark_imported(docs_ok: int, docs_failed: int, errs_for_file: int) -> bool:
    """Do not rename the XML when any document of that file failed or was skipped."""
    return docs_ok > 0 and docs_failed == 0 and errs_for_file == 0


def warehouse(armazem: int) -> int:
    return 1 if not armazem else int(armazem)


def num_linha_base(xml_num: int) -> int:
    return int(xml_num) * 100


def split_line_numbers(base: int, parts: int) -> list:
    return [base + i for i in range(parts)]
