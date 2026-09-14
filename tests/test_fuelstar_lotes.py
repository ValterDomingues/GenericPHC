"""FIFO SE-lot allocation — the core FuelStar → FI/BI behaviour."""

from copy import deepcopy

from fuelstar_lotes import (
    Line,
    Lot,
    assign_return,
    distribute_documents,
    distribute_line,
    fix_last_totals_original_bug,
    revert_stock_original_bug,
)


def _diesel(*stocks):
    lots = []
    for i, stock in enumerate(stocks, start=1):
        lots.append(
            Lot(ref="GASOLEO", lote=f"L{i}", stock=stock, epcult=1.0 + i / 100.0, data=f"2026-01-{i:02d}")
        )
    return lots


def test_single_lot_enough_stock():
    lots = _diesel(100)
    line = Line(1, 100, "GASOLEO", 40, 80.0)
    out = distribute_line(lots, line)
    assert len(out) == 1
    assert out[0].lote == "L1"
    assert out[0].pcusto == 1.01
    assert out[0].quantidade == 40
    assert lots[0].stock == 60


def test_split_across_two_lots_fifo():
    lots = _diesel(30, 80)
    line = Line(1, 100, "GASOLEO", 50, 100.0, desc_valor_total=10.0)
    out = distribute_line(lots, line)
    assert [p.lote for p in out] == ["L1", "L2"]
    assert [p.quantidade for p in out] == [30, 20]
    assert [p.num_linha for p in out] == [100, 101]
    assert [p.pcusto for p in out] == [1.01, 1.02]
    assert sum(p.valor_linha for p in out) == 100.0
    assert sum(p.desc_valor_total for p in out) == 10.0
    assert lots[0].stock == 0
    assert lots[1].stock == 60


def test_rounding_remainder_only_on_last_slice():
    lots = _diesel(1, 1, 1)
    line = Line(1, 100, "GASOLEO", 3, 10.00)  # 3.33 + 3.33 + 3.33 = 9.99
    out = distribute_line(lots, line)
    assert [p.valor_linha for p in out] == [3.33, 3.33, 3.34]
    assert sum(p.valor_linha for p in out) == 10.00

    buggy = deepcopy(out)
    # restore pre-fix values then apply the original ALL replace
    for p in buggy:
        p.valor_linha = 3.33
    orig = Line(1, 100, "GASOLEO", 3, 10.00)
    fix_last_totals_original_bug(buggy, orig)
    assert sum(p.valor_linha for p in buggy) != 10.00


def test_no_lot_leaves_empty_lote_does_not_invent_star():
    lots = _diesel()  # no stock rows
    lots = []
    line = Line(1, 100, "GASOLEO", 10, 20.0)
    out = distribute_line(lots, line)
    assert out[0].lote == ""
    assert out[0].quantidade == 10


def test_partial_stock_remainder_without_lote():
    lots = _diesel(4)
    line = Line(1, 100, "GASOLEO", 10, 20.0)
    out = distribute_line(lots, line)
    assert out[0].lote == "L1" and out[0].quantidade == 4
    assert out[1].lote == "" and out[1].quantidade == 6
    assert lots[0].stock == 0


def test_second_line_does_not_reuse_consumed_litres():
    lots = _diesel(50)
    l1 = Line(1, 100, "GASOLEO", 40, 80.0)
    l2 = Line(2, 100, "GASOLEO", 40, 80.0)
    out = distribute_documents(lots, [l1, l2])
    assert out[0].lote == "L1" and out[0].quantidade == 40
    assert out[1].lote == "L1" and out[1].quantidade == 10
    assert out[2].lote == "" and out[2].quantidade == 30
    assert lots[0].stock == 0


def test_original_revert_bug_would_double_allocate():
    lots = _diesel(50)
    snapshot = deepcopy(lots)
    l1 = Line(1, 100, "GASOLEO", 40, 80.0)
    distribute_line(lots, l1)
    assert lots[0].stock == 10
    revert_stock_original_bug(lots, snapshot)
    assert lots[0].stock == 50  # consumption undone — next line sees 50 again


def test_warehouse_isolation():
    lots = [
        Lot("GASOLEO", "A", 100, 1.10, armazem=1),
        Lot("GASOLEO", "B", 100, 1.20, armazem=2),
    ]
    line = Line(1, 100, "GASOLEO", 10, 20.0, armazem=2)
    out = distribute_line(lots, line)
    assert out[0].lote == "B"
    assert lots[0].stock == 100
    assert lots[1].stock == 90


def test_credit_note_adds_stock_does_not_consume():
    lots = _diesel(10, 5)
    line = Line(1, 100, "GASOLEO", 8, -16.0, sinal=-1)
    out = assign_return(lots, line)
    assert out.lote == "L2"  # newest
    assert lots[0].stock == 10
    assert lots[1].stock == 13


def test_skip_existing_and_cancelled():
    lots = _diesel(100)
    skip_ex = Line(1, 100, "GASOLEO", 10, 20.0, existe=True)
    skip_an = Line(2, 100, "GASOLEO", 10, 20.0, anulado=True)
    out = distribute_documents(lots, [skip_ex, skip_an])
    assert out[0].lote == "" and out[1].lote == ""
    assert lots[0].stock == 100


def test_already_filled_lote_left_alone():
    lots = _diesel(100)
    line = Line(1, 100, "GASOLEO", 10, 20.0, lote="KEEP")
    out = distribute_line(lots, line)
    assert out[0].lote == "KEEP"
    assert lots[0].stock == 100


def test_fifo_order_is_oldest_first():
    lots = _diesel(5, 5, 5)
    line = Line(1, 200, "GASOLEO", 12, 24.0)
    out = distribute_line(lots, line)
    assert [p.lote for p in out] == ["L1", "L2", "L3"]
    assert [p.quantidade for p in out] == [5, 5, 2]
