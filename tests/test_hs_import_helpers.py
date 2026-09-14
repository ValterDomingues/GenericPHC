"""Unit tests for the hs import parsers (Python spec of the VFP helpers)."""

from datetime import date, datetime

from hs_import_helpers import (
    cod_tipo_fich,
    parse_data,
    parse_horas,
    parse_horas_original,
    sql_lit,
)


def test_original_hours_bug_quantity_one():
    """Subsídio de refeição '1' became 1.02 because minutes reused the whole string."""
    assert parse_horas_original("1") == 1.02
    assert parse_horas("1", tipo=3) == 1.0


def test_hours_hhmm():
    assert parse_horas("8:30") == 8.5
    assert parse_horas("8:30:00") == 8.5
    assert parse_horas("0:45") == 0.75
    assert parse_horas("1:15") == 1.25
    assert parse_horas_original("8:30") == 8.5


def test_hours_decimal_and_comma():
    assert parse_horas("1.5") == 1.5
    assert parse_horas("1,5") == 1.5
    assert parse_horas(2.0, tipo=3) == 2.0


def test_hours_excel_time_fraction_overtime_not_meals():
    # 08:30 as Excel day-fraction
    frac = 8.5 / 24.0
    assert parse_horas(frac, tipo=1) == 8.5
    # meal quantity 0.5 must stay 0.5, not 12 hours
    assert parse_horas(0.5, tipo=3) == 0.5


def test_hours_datetime():
    assert parse_horas(datetime(1899, 12, 31, 8, 30, 0), tipo=1) == 8.5


def test_hours_empty():
    assert parse_horas("") == 0.0
    assert parse_horas(None) == 0.0


def test_dates_pt_iso_and_serial():
    assert parse_data("14/09/2026") == date(2026, 9, 14)
    assert parse_data("2026-09-14") == date(2026, 9, 14)
    assert parse_data("14-09-2026") == date(2026, 9, 14)
    assert parse_data(date(2026, 9, 14)) == date(2026, 9, 14)
    assert parse_data(datetime(2026, 9, 14, 8, 30)) == date(2026, 9, 14)
    serial = (date(2026, 9, 14) - date(1899, 12, 30)).days
    assert parse_data(serial) == date(2026, 9, 14)


def test_dates_invalid():
    assert parse_data("") is None
    assert parse_data(None) is None
    assert parse_data("31/02/2026") is None
    assert parse_data("abc") is None


def test_sql_lit_escapes_apostrophe():
    assert sql_lit("D'Almeida") == "'D''Almeida'"
    assert sql_lit("  Ana  ") == "'Ana'"
    assert sql_lit(None) == "''"


def test_tipo_ficheiro_exact_and_prefix():
    assert cod_tipo_fich("Horas Extraordinárias") == 1
    assert cod_tipo_fich("Horas Extra") == 1
    assert cod_tipo_fich("Faltas") == 2
    assert cod_tipo_fich("faltas") == 2
    assert cod_tipo_fich("Sub.Refeição") == 3
    assert cod_tipo_fich("") == 0
    assert cod_tipo_fich("Outro") == 0
    # Must not depend on SET EXACT OFF prefix tricks for unrelated values
    assert cod_tipo_fich("Horas") == 0
