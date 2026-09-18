"""Equivalence checks for the do/ml header vs line mismatch rewrite."""

from collections import defaultdict
from decimal import Decimal
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL_TEMP = (ROOT / "sql" / "do_ml_header_line_mismatch.sql").read_text(encoding="utf-8")
SQL_SELECT = (ROOT / "sql" / "do_ml_header_line_mismatch_select.sql").read_text(
    encoding="utf-8"
)
SQL_INDEX = (ROOT / "sql" / "do_ml_header_line_mismatch_indexes.sql").read_text(
    encoding="utf-8"
)
DOC = (ROOT / "docs" / "do-ml-header-line-mismatch.md").read_text(encoding="utf-8")


def _d(value):
    return Decimal(str(value))


def sql_sum(values):
    """SQL SUM: skip NULLs; all-NULL or no non-null values -> None."""
    acc = None
    for value in values:
        if value is None:
            continue
        acc = _d(value) if acc is None else acc + _d(value)
    return acc


def sql_ne(left, right):
    """SQL `!=`: NULL compared to anything is UNKNOWN (False in HAVING)."""
    if left is None or right is None:
        return False
    return left != right


def original_query(docs, lines, ano=2026):
    """Join then GROUP BY display columns (original semantics)."""
    joined = [
        (doc, line)
        for doc in docs
        if doc["ano"] == ano
        for line in lines
        if line["dostamp"] == doc["dostamp"]
    ]
    groups = defaultdict(list)
    for doc, line in joined:
        key = (
            doc["data"],
            doc["dinome"],
            doc["dilno"],
            doc["docnome"],
            doc["adoc"],
            doc["edebfin"],
            doc["ecrefin"],
        )
        groups[key].append(line)

    out = []
    for key, group_lines in groups.items():
        debito = sql_sum(line["edeb"] for line in group_lines)
        credito = sql_sum(line["ecre"] for line in group_lines)
        edebfin, ecrefin = key[5], key[6]
        if sql_ne(edebfin, debito) or sql_ne(ecrefin, credito):
            out.append(key + (debito, credito))
    return sorted(out, key=lambda r: (str(r[0]), r[2], r[4], str(r[5]), str(r[6])))


def optimized_query(docs, lines, ano=2026):
    """Filter year, aggregate ml by dostamp, compare (rewrite semantics)."""
    year_docs = [doc for doc in docs if doc["ano"] == ano]
    by_stamp = defaultdict(list)
    stamps = {doc["dostamp"] for doc in year_docs}
    for line in lines:
        if line["dostamp"] in stamps:
            by_stamp[line["dostamp"]].append(line)

    out = []
    for doc in year_docs:
        group_lines = by_stamp.get(doc["dostamp"])
        if not group_lines:
            continue
        debito = sql_sum(line["edeb"] for line in group_lines)
        credito = sql_sum(line["ecre"] for line in group_lines)
        if sql_ne(doc["edebfin"], debito) or sql_ne(doc["ecrefin"], credito):
            out.append(
                (
                    doc["data"],
                    doc["dinome"],
                    doc["dilno"],
                    doc["docnome"],
                    doc["adoc"],
                    doc["edebfin"],
                    doc["ecrefin"],
                    debito,
                    credito,
                )
            )
    return sorted(out, key=lambda r: (str(r[0]), r[2], r[4], str(r[5]), str(r[6])))


def _doc(stamp, ano, data, adoc, debit, credit, dinome="Diario", dilno=1, docnome="Pag"):
    return {
        "dostamp": stamp,
        "ano": ano,
        "data": data,
        "dinome": dinome,
        "dilno": dilno,
        "docnome": docnome,
        "adoc": adoc,
        "edebfin": debit,
        "ecrefin": credit,
    }


def test_mismatch_debit_or_credit():
    docs = [_doc("X", 2026, "2026-04-01", 1, Decimal("10.00"), Decimal("10.00"))]
    lines = [
        {"dostamp": "X", "edeb": Decimal("7.00"), "ecre": Decimal("0.00")},
        {"dostamp": "X", "edeb": Decimal("0.00"), "ecre": Decimal("10.00")},
    ]
    orig = original_query(docs, lines)
    opt = optimized_query(docs, lines)
    assert orig == opt
    assert orig[0][7] == Decimal("7.00")
    assert orig[0][8] == Decimal("10.00")


def test_balanced_document_omitted():
    docs = [_doc("Y", 2026, "2026-04-02", 2, Decimal("15.00"), Decimal("15.00"))]
    lines = [
        {"dostamp": "Y", "edeb": Decimal("15.00"), "ecre": Decimal("0.00")},
        {"dostamp": "Y", "edeb": Decimal("0.00"), "ecre": Decimal("15.00")},
    ]
    assert original_query(docs, lines) == []
    assert optimized_query(docs, lines) == []


def test_other_years_ignored():
    docs = [_doc("Z", 2025, "2025-01-01", 3, Decimal("1.00"), Decimal("0.00"))]
    lines = [{"dostamp": "Z", "edeb": Decimal("9.00"), "ecre": Decimal("0.00")}]
    assert original_query(docs, lines, ano=2026) == []
    assert optimized_query(docs, lines, ano=2026) == []
    assert original_query(docs, lines, ano=2025)
    assert optimized_query(docs, lines, ano=2025)


def test_documents_without_lines_excluded():
    docs = [_doc("EMPTY", 2026, "2026-05-01", 4, Decimal("1.00"), Decimal("0.00"))]
    assert original_query(docs, []) == []
    assert optimized_query(docs, []) == []


def test_original_and_optimized_match_when_headers_unique():
    docs = [
        _doc("A", 2026, "2026-01-10", 10, Decimal("100.00"), Decimal("100.00")),
        _doc("B", 2026, "2026-02-01", 11, Decimal("50.00"), Decimal("40.00")),
        _doc("C", 2025, "2025-12-31", 99, Decimal("9.00"), Decimal("1.00")),
        _doc("D", 2026, "2026-03-01", 1, Decimal("20.00"), Decimal("0.00"), dilno=2),
    ]
    lines = [
        {"dostamp": "A", "edeb": Decimal("60.00"), "ecre": Decimal("0.00")},
        {"dostamp": "A", "edeb": Decimal("40.00"), "ecre": Decimal("100.00")},
        {"dostamp": "B", "edeb": Decimal("50.00"), "ecre": Decimal("0.00")},
        {"dostamp": "B", "edeb": Decimal("0.00"), "ecre": Decimal("50.00")},
        {"dostamp": "C", "edeb": Decimal("9.00"), "ecre": Decimal("0.00")},
        {"dostamp": "D", "edeb": Decimal("20.00"), "ecre": Decimal("20.00")},
    ]
    orig = original_query(docs, lines)
    opt = optimized_query(docs, lines)
    assert orig == opt
    assert {row[4] for row in opt} == {11, 1}


def test_grouping_by_dostamp_does_not_merge_duplicate_headers():
    """Original GROUP BY display columns can merge two documents; rewrite does not."""
    docs = [
        _doc("P", 2026, "2026-06-01", 8, Decimal("10.00"), Decimal("10.00")),
        _doc("Q", 2026, "2026-06-01", 8, Decimal("10.00"), Decimal("10.00")),
    ]
    lines = [
        {"dostamp": "P", "edeb": Decimal("10.00"), "ecre": Decimal("10.00")},
        {"dostamp": "Q", "edeb": Decimal("4.00"), "ecre": Decimal("4.00")},
    ]
    orig = original_query(docs, lines)
    opt = optimized_query(docs, lines)
    assert len(orig) == 1
    assert orig[0][7] == Decimal("14.00")
    assert len(opt) == 1
    assert opt[0][7] == Decimal("4.00")


def test_null_header_follows_sql_unknown_comparison():
    docs = [_doc("N", 2026, "2026-07-01", 5, None, Decimal("3.00"))]
    lines = [{"dostamp": "N", "edeb": Decimal("1.00"), "ecre": Decimal("3.00")}]
    orig = original_query(docs, lines)
    opt = optimized_query(docs, lines)
    assert orig == opt == []


def test_all_null_line_amounts_sum_to_null():
    docs = [_doc("N", 2026, "2026-07-02", 6, Decimal("1.00"), Decimal("0.00"))]
    lines = [{"dostamp": "N", "edeb": None, "ecre": None}]
    orig = original_query(docs, lines)
    opt = optimized_query(docs, lines)
    assert orig == opt == []


def test_sql_temp_table_shape():
    assert "DECLARE @ano INT = 2026" in SQL_TEMP
    assert "INTO #docs" in SQL_TEMP
    assert "CREATE UNIQUE CLUSTERED INDEX PK_docs ON #docs (dostamp)" in SQL_TEMP
    assert "GROUP BY ml.dostamp" in SQL_TEMP
    assert "d.edebfin <> m.debito" in SQL_TEMP
    assert "d.ecrefin <> m.credito" in SQL_TEMP
    live = SQL_TEMP.split("SET NOCOUNT ON;")[1]
    assert "GROUP BY do.data" not in live
    assert "HAVING" not in live


def test_sql_select_is_single_statement_form():
    assert "WHERE d.ano = 2026" in SQL_SELECT
    assert "WITH docs AS" in SQL_SELECT
    assert "GROUP BY ml.dostamp" in SQL_SELECT
    assert "#docs" not in SQL_SELECT
    assert "SUM(ml.edeb) AS debito" in SQL_SELECT
    assert "SUM(ml.ecre) AS credito" in SQL_SELECT
    live = SQL_SELECT.split("Change the year")[1]
    assert live.count("2026") == 1


def test_index_script_covers_seek_columns():
    assert "ON dbo.do (ano)" in SQL_INDEX
    assert "INCLUDE (data, dinome, dilno, docnome, adoc, edebfin, ecrefin)" in SQL_INDEX
    assert "ON dbo.ml (dostamp)" in SQL_INDEX
    assert "INCLUDE (edeb, ecre)" in SQL_INDEX
    assert "IX_do_ano_header_mismatch" in SQL_INDEX
    assert "IX_ml_dostamp_edeb_ecre" in SQL_INDEX


def test_docs_explain_rewrite():
    assert "wide" in DOC.lower()
    assert "dostamp" in DOC
    assert "do_ml_header_line_mismatch.sql" in DOC
    assert "SET STATISTICS IO" in DOC


if __name__ == "__main__":
    tests = [
        test_mismatch_debit_or_credit,
        test_balanced_document_omitted,
        test_other_years_ignored,
        test_documents_without_lines_excluded,
        test_original_and_optimized_match_when_headers_unique,
        test_grouping_by_dostamp_does_not_merge_duplicate_headers,
        test_null_header_follows_sql_unknown_comparison,
        test_all_null_line_amounts_sum_to_null,
        test_sql_temp_table_shape,
        test_sql_select_is_single_statement_form,
        test_index_script_covers_seek_columns,
        test_docs_explain_rewrite,
    ]
    for fn in tests:
        fn()
        print("ok", fn.__name__)
    print("all passed")
