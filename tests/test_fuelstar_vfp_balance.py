"""Lightweight Visual FoxPro keyword-balance check for the FuelStar PRG."""

from __future__ import annotations

import re
from pathlib import Path


PRG = Path(__file__).resolve().parents[1] / "prg" / "fuelstar_impfs.prg"

PAIRS = [
    ("If", "EndIf"),
    ("Do While", "EndDo"),
    ("Do Case", "EndCase"),
    ("Scan", "EndScan"),
    ("Text", "EndText"),
    ("Function", "EndFunc"),
    ("Procedure", "EndProc"),
    ("Try", "EndTry"),
    ("For", "EndFor"),
]


_STRING = re.compile(r"'[^']*'|\[[^\]]*\]")
_LINE_COMMENT = re.compile(r"(\*!\*.*|\&&.*)$")


def _strip(line: str) -> str:
    s = line.strip()
    if s.startswith("*") and not s.upper().startswith("*IF"):
        return ""
    s = _LINE_COMMENT.sub("", s)
    s = _STRING.sub(" ", s)
    return s


def _without_text_blocks(body: str) -> str:
    """TEXTMERGE batches contain T-SQL IF/BEGIN; they are not VFP keywords."""
    return re.sub(r"(?is)\bText\b.*?\bEndText\b", " ", body)


def _leading(line: str, word: str) -> bool:
    """True when *word* starts the VFP statement (not 'Scan For' / 'Locate For')."""
    return re.match(r"(?i)^" + re.escape(word) + r"(?![A-Za-z0-9_])", line.strip()) is not None


def _count_leading(body: str, word: str) -> int:
    return sum(1 for line in body.splitlines() if _leading(line, word))


def test_prg_exists():
    assert PRG.is_file(), f"missing {PRG}"


def test_keyword_balance():
    text = PRG.read_text(encoding="utf-8", errors="replace")
    body = _without_text_blocks("\n".join(_strip(line) for line in text.splitlines()))
    errors = []
    for start, end in PAIRS:
        n_start = _count_leading(body, start)
        n_end = _count_leading(body, end)
        if start == "For":
            n_end += _count_leading(body, "Next")
        if n_start != n_end:
            errors.append(f"{start}/{end}: {n_start} vs {n_end}")
    assert not errors, "Unbalanced VFP keywords: " + "; ".join(errors)


def test_lote_fixes_present():
    text = PRG.read_text(encoding="utf-8", errors="replace")
    assert "func_distribLote" in text
    assert "func_assignLoteSaida" in text
    assert "func_sqlLit" in text
    assert "epcult" in text
    # original compile-breaking concatenation must not return
    assert "NumLinhaReplace" not in text
    # original invalid VFP UPDATE … FROM on crsLotes
    assert "Update crsLotes Set stock = crsLotesRef.stock" not in text
    # FI costs must come from the lot, not hardcoded 0,0 after tliquido
    assert "crsLinhas.PCusto" in text
    assert "Addbs(" in text
    assert "ReadWrite" in text
