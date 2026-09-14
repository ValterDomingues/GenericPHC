"""FIFO lot (SE) allocation for FuelStar → PHC document lines (FI/BI).

Mirrors func_assignLoteSaida / func_distribLote / func_assignLoteDevolucao
in prg/fuelstar_impfs.prg.

SE (crsLotes) is the working stock. Assignment writes Lote + PCusto on the
line; the PHC trigger on FI.lote then updates the real SE table. Virtual
stock in this planner must not be reverted, or later lines reuse the same
litres.
"""

from __future__ import annotations

from copy import deepcopy
from dataclasses import dataclass, field
from typing import List, Optional


QTY_EPS = 0.0001


@dataclass
class Lot:
    ref: str
    lote: str
    stock: float
    epcult: float
    data: str = "2026-01-01"
    armazem: int = 1


@dataclass
class Line:
    id_import: int
    num_linha: int
    ref: str
    quantidade: float
    valor_linha: float
    lote: str = ""
    pcusto: float = 0.0
    desc_valor_total: float = 0.0
    usalote: bool = True
    area: str = "D"
    sinal: int = 1
    armazem: int = 1
    anulado: bool = False
    existe: bool = False


def _lots_for(lots: List[Lot], ref: str, armazem: int, require_stock: bool) -> List[Lot]:
    out = []
    for lot in lots:
        if lot.ref.strip() != ref.strip():
            continue
        if lot.armazem != armazem:
            continue
        if require_stock and lot.stock <= QTY_EPS:
            continue
        out.append(lot)
    return out


def _prorate(line: Line, take: float) -> Line:
    ratio = take / line.quantidade if line.quantidade else 0.0
    return Line(
        id_import=line.id_import,
        num_linha=line.num_linha,
        ref=line.ref,
        quantidade=take,
        valor_linha=round(line.valor_linha * ratio, 2),
        lote=line.lote,
        pcusto=line.pcusto,
        desc_valor_total=round(line.desc_valor_total * ratio, 2),
        usalote=line.usalote,
        area=line.area,
        sinal=line.sinal,
        armazem=line.armazem,
        anulado=line.anulado,
        existe=line.existe,
    )


def _fix_last_totals(parts: List[Line], original: Line) -> None:
    """Apply rounding remainder on the LAST slice only (not REPLACE … ALL)."""
    if not parts:
        return
    delta_val = round(original.valor_linha - sum(p.valor_linha for p in parts), 2)
    delta_desc = round(original.desc_valor_total - sum(p.desc_valor_total for p in parts), 2)
    parts[-1].valor_linha = round(parts[-1].valor_linha + delta_val, 2)
    parts[-1].desc_valor_total = round(parts[-1].desc_valor_total + delta_desc, 2)


def fix_last_totals_original_bug(parts: List[Line], original: Line) -> None:
    """Original: REPLACE ValorLinha WITH ValorLinha+(mVal-mTotalLin) ALL."""
    if not parts:
        return
    delta_val = round(original.valor_linha - sum(p.valor_linha for p in parts), 2)
    for p in parts:
        p.valor_linha = round(p.valor_linha + delta_val, 2)


def distribute_line(lots: List[Lot], line: Line) -> List[Line]:
    """Assign FIFO lots to one outbound line; split when one lot is not enough."""
    if line.existe or line.anulado or not line.usalote or line.lote.strip():
        return [deepcopy(line)]

    if line.sinal < 0:
        return [assign_return(lots, line)]

    available = _lots_for(lots, line.ref, line.armazem, require_stock=True)
    if not available:
        out = deepcopy(line)
        out.lote = ""
        return [out]

    remaining = line.quantidade
    parts: List[Line] = []
    extra = 0
    while remaining > QTY_EPS:
        available = _lots_for(lots, line.ref, line.armazem, require_stock=True)
        if not available:
            stub = _prorate(line, remaining)
            stub.num_linha = line.num_linha + extra
            stub.lote = ""
            parts.append(stub)
            break
        lot = available[0]
        take = min(lot.stock, remaining)
        if remaining - take < QTY_EPS:
            take = remaining
        slice_line = _prorate(line, take)
        slice_line.num_linha = line.num_linha + extra
        slice_line.lote = lot.lote.strip()
        slice_line.pcusto = lot.epcult
        lot.stock = round(lot.stock - take, 4)
        parts.append(slice_line)
        remaining = round(remaining - take, 5)
        extra += 1

    _fix_last_totals(parts, line)
    return parts or [deepcopy(line)]


def assign_return(lots: List[Lot], line: Line) -> Line:
    """Credit note / return: do not consume; add qty back onto the newest lot."""
    out = deepcopy(line)
    candidates = _lots_for(lots, line.ref, line.armazem, require_stock=False)
    if not candidates:
        out.lote = ""
        return out
    lot = candidates[-1]  # newest in FIFO date order
    out.lote = lot.lote.strip()
    out.pcusto = lot.epcult
    lot.stock = round(lot.stock + line.quantidade, 4)
    return out


def distribute_documents(lots: List[Lot], lines: List[Line]) -> List[Line]:
    """Process lines in given order (caller sorts by DataDoc, IDImport, NumLinha)."""
    result: List[Line] = []
    for line in lines:
        result.extend(distribute_line(lots, line))
    return result


def revert_stock_original_bug(lots: List[Lot], snapshot: List[Lot]) -> None:
    """Original UPDATE crsLotes FROM crsLotesRef after func_distribLote.

    crsLotesRef still held the pre-split stocks, so FIFO consumption was undone
    and the next document line reused the same litres.
    """
    by_key = {(s.ref, s.lote, s.armazem): s.stock for s in snapshot}
    for lot in lots:
        key = (lot.ref, lot.lote, lot.armazem)
        if key in by_key:
            lot.stock = by_key[key]
