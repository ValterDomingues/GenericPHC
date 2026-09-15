from datetime import date, timedelta


def last_two_business_day_range(today: date) -> tuple[date, date]:
    """Same CASE as sql/u_reccli_open_last_2_business_days.sql (0=Mon .. 6=Sun)."""
    dow = today.weekday()
    if dow == 0:
        start, end = today - timedelta(days=3), today
    elif dow == 5:
        start, end = today - timedelta(days=2), today - timedelta(days=1)
    elif dow == 6:
        start, end = today - timedelta(days=3), today - timedelta(days=2)
    else:
        start, end = today - timedelta(days=1), today
    return start, end


def test_weekday_pairs():
    # Mon 14 Sep 2026 -> Fri 11 + Mon 14
    assert last_two_business_day_range(date(2026, 9, 14)) == (
        date(2026, 9, 11),
        date(2026, 9, 14),
    )
    # Tue 15 Sep 2026 -> Mon 14 + Tue 15
    assert last_two_business_day_range(date(2026, 9, 15)) == (
        date(2026, 9, 14),
        date(2026, 9, 15),
    )
    # Wed 16 Sep 2026 -> Tue 15 + Wed 16
    assert last_two_business_day_range(date(2026, 9, 16)) == (
        date(2026, 9, 15),
        date(2026, 9, 16),
    )
    # Thu 17 Sep 2026 -> Wed 16 + Thu 17
    assert last_two_business_day_range(date(2026, 9, 17)) == (
        date(2026, 9, 16),
        date(2026, 9, 17),
    )
    # Fri 18 Sep 2026 -> Thu 17 + Fri 18
    assert last_two_business_day_range(date(2026, 9, 18)) == (
        date(2026, 9, 17),
        date(2026, 9, 18),
    )


def test_weekend_uses_thu_fri():
    # Sat 19 Sep 2026 -> Thu 17 + Fri 18
    assert last_two_business_day_range(date(2026, 9, 19)) == (
        date(2026, 9, 17),
        date(2026, 9, 18),
    )
    # Sun 20 Sep 2026 -> Thu 17 + Fri 18
    assert last_two_business_day_range(date(2026, 9, 20)) == (
        date(2026, 9, 17),
        date(2026, 9, 18),
    )


def test_sql_case_matches_python():
    sql = open("sql/u_reccli_open_last_2_business_days.sql", encoding="utf-8").read()
    assert "WHEN 0 THEN DATEADD(DAY, -3, @mToday)" in sql
    assert "WHEN 5 THEN DATEADD(DAY, -2, @mToday)" in sql
    assert "WHEN 6 THEN DATEADD(DAY, -3, @mToday)" in sql
    assert "AND CONVERT(DATE, u_reccli.data) >= @mFrom" in sql
    assert "AND CONVERT(DATE, u_reccli.data) <= @mTo" in sql
    assert "u_reccli.fechada=0" in sql


if __name__ == "__main__":
    test_weekday_pairs()
    test_weekend_uses_thu_fri()
    test_sql_case_matches_python()
    print("all passed")
