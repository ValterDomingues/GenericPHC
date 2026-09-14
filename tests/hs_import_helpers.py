"""Python spec of the VFP helpers in prg/hs_import_timecontrol.prg.

These functions mirror func_parseHoras, func_parseData, func_sqlLit and
func_codTipoFich so the payroll-critical parsing can be unit-tested without
Visual FoxPro / Excel / PHC.
"""

from __future__ import annotations

from datetime import date, datetime, timedelta
from typing import Any, Optional


def parse_horas_original(text: str) -> float:
    """Original VFP logic (buggy when the value has no ':').

    mHorasTxt = VAL(horas)
    mMinTxt   = VAL(Right(horas, Len(horas) - At(':', horas)))
    result    = mHorasTxt + Round(mMinTxt / 60, 2)
    """
    s = "" if text is None else str(text).strip()
    horas = _vfp_val(s)
    colon = s.find(":")
    # VFP At() is 1-based; At=0 when missing. Right(s, Len-0) = whole string.
    minutes = _vfp_val(s[colon + 1 :] if colon >= 0 else s)
    return horas + round(minutes / 60.0, 2)


def parse_horas(value: Any, tipo: int = 1) -> float:
    """Mirror of func_parseHoras."""
    if value is None:
        return 0.0
    if isinstance(value, datetime):
        return round(value.hour + value.minute / 60.0 + value.second / 3600.0, 2)
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if tipo != 3 and 0 < float(value) < 1:
            return round(float(value) * 24, 2)
        return round(float(value), 2)

    text = str(value).strip().replace(" ", "").replace(",", ".")
    if text in ("", "."):
        return 0.0
    if ":" in text:
        parts = text.split(":")
        hours = _vfp_val(parts[0] if parts else "0")
        mins = _vfp_val(parts[1] if len(parts) > 1 else "0")
        secs = _vfp_val(parts[2] if len(parts) > 2 else "0")
        return round(hours + mins / 60.0 + secs / 3600.0, 2)
    return round(_vfp_val(text), 2)


def parse_data(value: Any) -> Optional[date]:
    """Mirror of func_parseData. Empty / invalid → None (VFP empty date)."""
    if value is None:
        return None
    if isinstance(value, datetime):
        return value.date()
    if isinstance(value, date):
        return value
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if value < 1:
            return None
        try:
            return (datetime(1899, 12, 30) + timedelta(days=int(value))).date()
        except OverflowError:
            return None

    text = str(value).strip()
    if not text:
        return None

    normalized = text.replace(".", "/").replace("-", "/").replace(" ", "")
    if normalized.count("/") != 2:
        return None
    p1, p2, p3 = normalized.split("/")
    try:
        n1, n2, n3 = int(float(p1)), int(float(p2)), int(float(p3))
    except ValueError:
        return None
    if n1 > 31:
        year, month, day = n1, n2, n3
    else:
        day, month, year = n1, n2, n3
    if 0 < year < 100:
        year = year + (2000 if year < 50 else 1900)
    if not (1 <= month <= 12 and 1 <= day <= 31 and 1990 <= year <= 2100):
        return None
    try:
        return date(year, month, day)
    except ValueError:
        return None


def sql_lit(value: Optional[str]) -> str:
    """Mirror of func_sqlLit."""
    text = "" if value is None else str(value).strip()
    return "'" + text.replace("'", "''") + "'"


def cod_tipo_fich(tipo: Optional[str]) -> int:
    """Mirror of func_codTipoFich (exact match, independent of SET EXACT)."""
    text = "" if tipo is None else str(tipo).strip()
    upper = text.upper()
    if text == "Horas Extraordinárias" or upper[:11] == "HORAS EXTRA":
        return 1
    if upper == "FALTAS":
        return 2
    if text == "Sub.Refeição" or "refei" in text.lower():
        return 3
    return 0


def _vfp_val(text: str) -> float:
    """VFP VAL(): parse a leading number, stop at the first non-numeric."""
    if text is None:
        return 0.0
    s = str(text).strip().replace(",", ".")
    out = []
    for i, ch in enumerate(s):
        if ch in "0123456789":
            out.append(ch)
        elif ch == "." and "." not in out:
            out.append(ch)
        elif ch in "+-" and i == 0:
            out.append(ch)
        else:
            break
    if not out or out in (["+"], ["-"], ["."], ["+."], ["-."]):
        return 0.0
    try:
        return float("".join(out))
    except ValueError:
        return 0.0
