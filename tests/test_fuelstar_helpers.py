"""Unit tests for FuelStar → PHC helper parsing / mapping."""

from datetime import date

from fuelstar_helpers import (
    ESC_RATE,
    accumulate_payment,
    accumulate_payment_original,
    apply_nc_sign,
    build_atcud,
    doc_type,
    fi_costs,
    format_date,
    format_hour,
    format_string,
    get_tab_iva,
    header_cost_totals,
    imported_name,
    iva_bucket,
    line_unit_price,
    line_valor_movimento,
    nif_from_xml,
    num_linha_base,
    serie_to_import,
    should_mark_imported,
    split_line_numbers,
    sql_lit,
    tipo_doc_width,
    warehouse,
)


def test_format_date_iso():
    assert format_date("2025-11-28T08:15:00") == date(2025, 11, 28)
    assert format_date("") is None
    assert format_date("2025-13-40") is None


def test_format_hour():
    assert format_hour("2025-11-28T08:15:32") == "08:15:32"
    assert format_hour("2025-11-28") == ""


def test_format_string_apostrophe_and_controls():
    assert format_string("D'Almeida") == "D´Almeida"
    assert format_string("A\x01 \x02  B") == "A B"


def test_sql_lit_escapes_quotes():
    assert sql_lit("O'Brien") == "'O''Brien'"
    assert sql_lit(None) == "''"


def test_iva_mapping():
    assert get_tab_iva(23) == 2
    assert get_tab_iva(6) == 1
    assert get_tab_iva(13) == 3
    assert get_tab_iva(0) == 4
    assert get_tab_iva(99) == 0
    assert iva_bucket(23) == "iva2"
    assert iva_bucket(6) == "iva1"


def test_nif_keeps_letters_and_zeros():
    assert nif_from_xml("012345678") == "012345678"
    assert nif_from_xml("PT123456789") == "PT123456789"
    assert int("012345678") == 12345678  # original GetChildIntValue would drop the zero


def test_atcud():
    assert build_atcud("ABCDEF", 12) == "ABCDEF-12"
    assert build_atcud("ABCDEF-12", 12) == "ABCDEF-12"


def test_doc_type_map():
    assert doc_type("W") == "FS"
    assert doc_type("G") == "FR"
    assert doc_type("C") == "NC"
    assert doc_type("190") == "DC"
    assert doc_type("181") == ""  # importPHC=.F.
    assert doc_type("298") == ""
    assert serie_to_import("W") == 1
    assert serie_to_import("181") == 2
    assert serie_to_import("ZZ") == 0


def test_tipo_doc_not_truncated():
    assert tipo_doc_width("FT_tran", 2) == "FT"  # original C(2)
    assert tipo_doc_width("FT_tran", 10) == "FT_tran"
    assert tipo_doc_width("FT_guia", 10) == "FT_guia"


def test_payment_nc_two_cash_lines():
    orig = {}
    orig = accumulate_payment_original(orig, 1, 10, "", -1)
    orig = accumulate_payment_original(orig, 1, 20, "", -1)
    assert orig["numerario"] == -10  # Abs(-10+20)*-1

    fixed = {}
    fixed = accumulate_payment(fixed, 1, 10, "", -1)
    fixed = accumulate_payment(fixed, 1, 20, "", -1)
    assert fixed["numerario"] == -30


def test_payment_mb_opt():
    t = accumulate_payment({}, 3, 15.5, "MB OPT", 1)
    assert t["multibanco"] == 15.5
    assert t["mbterm"] == "OPT"


def test_line_prices():
    assert line_unit_price(1.50, 10.00, 10) == 0.50
    assert round(line_valor_movimento(1.50, 10, 0, 10, 1.00), 2) == 12.50


def test_nc_sign():
    assert apply_nc_sign(12.34, -1) == -12.34


def test_fi_costs_from_lot():
    c = fi_costs(1.2345, 100)
    assert c["epcp"] == 1.2345
    assert c["ecusto"] == 123.45
    assert c["custo"] == round(123.45 * ESC_RATE, 4)
    tot = header_cost_totals(
        [{"quantidade": 100, "pcusto": 1.2345}, {"quantidade": 50, "pcusto": 1.10}]
    )
    assert tot["totqtt"] == 150
    assert tot["ecusto"] == round(123.45 + 55.0, 4)


def test_file_imported_gate():
    assert imported_name("dia.xml") == "dia.xml.importado"
    assert should_mark_imported(3, 0, 0) is True
    assert should_mark_imported(3, 1, 0) is False
    assert should_mark_imported(0, 0, 0) is False
    assert should_mark_imported(2, 0, 1) is False


def test_warehouse_and_line_numbers():
    assert warehouse(0) == 1
    assert warehouse(2) == 2
    assert num_linha_base(3) == 300
    assert split_line_numbers(300, 3) == [300, 301, 302]
