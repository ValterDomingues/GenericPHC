#!/usr/bin/env python3
"""
Periodically query the database and email the results as a list.

Usage:
  # Send once (e.g. from cron):
  python send_periodic_email.py

  # Keep running and send on an interval (see SEND_INTERVAL_MINUTES):
  python send_periodic_email.py --loop

Copy .env.example to .env and fill in your settings before running.
"""

from __future__ import annotations

import argparse
import os
import smtplib
import sys
import time
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from typing import Any, Sequence

from dotenv import load_dotenv

try:
    import schedule
except ImportError:  # optional unless --loop is used
    schedule = None


# =============================================================================
# >>> INSERT YOUR SQL QUERY HERE <<<
# -----------------------------------------------------------------------------
# Replace the placeholder below with the SELECT you want to run.
# Each row from the result set becomes one item in the email body list.
# Column values in a row are joined with " | ".
# =============================================================================
# Detail rows (like the original IIF query). Use @Aggregate = 1 for SUM per obra.
# Requires dbo.usp_ListObranosNaturcst (see sql/usp_ListObranosNaturcst.sql).
# Or paste the batch from sql/dynamic_naturcst_pivot.sql if you prefer inline SQL.
SQL_QUERY = """
EXEC dbo.usp_ListObranosNaturcst @Aggregate = 0;
"""
# =============================================================================
# End of SQL query section
# =============================================================================


def get_db_connection():
    """Open a DB connection based on DB_ENGINE (postgresql | mysql | sqlite)."""
    engine = os.getenv("DB_ENGINE", "postgresql").lower().strip()

    if engine == "postgresql":
        import psycopg2

        return psycopg2.connect(
            host=os.getenv("DB_HOST", "localhost"),
            port=int(os.getenv("DB_PORT", "5432")),
            dbname=os.getenv("DB_NAME"),
            user=os.getenv("DB_USER"),
            password=os.getenv("DB_PASSWORD"),
        )

    if engine == "mysql":
        import pymysql

        return pymysql.connect(
            host=os.getenv("DB_HOST", "localhost"),
            port=int(os.getenv("DB_PORT", "3306")),
            database=os.getenv("DB_NAME"),
            user=os.getenv("DB_USER"),
            password=os.getenv("DB_PASSWORD"),
            cursorclass=pymysql.cursors.Cursor,
        )

    if engine == "sqlite":
        import sqlite3

        path = os.getenv("DB_PATH", "./data.db")
        return sqlite3.connect(path)

    raise ValueError(f"Unsupported DB_ENGINE: {engine!r} (use postgresql, mysql, or sqlite)")


def fetch_rows(query: str) -> tuple[Sequence[str], list[tuple[Any, ...]]]:
    """Run the SQL query and return (column_names, rows)."""
    conn = get_db_connection()
    try:
        cursor = conn.cursor()
        cursor.execute(query)
        rows = cursor.fetchall()
        columns = [desc[0] for desc in (cursor.description or [])]
        cursor.close()
        return columns, list(rows)
    finally:
        conn.close()


def format_rows_as_list(columns: Sequence[str], rows: list[tuple[Any, ...]]) -> str:
    """Turn query rows into a plain-text bullet list for the email body."""
    if not rows:
        return "No results found."

    lines: list[str] = []
    for row in rows:
        # Prefer "column: value" pairs when column names are available
        if columns and len(columns) == len(row):
            parts = [f"{col}: {val}" for col, val in zip(columns, row)]
            item = " | ".join(parts)
        else:
            item = " | ".join(str(val) for val in row)
        lines.append(f"- {item}")

    return "\n".join(lines)


def build_email_body(columns: Sequence[str], rows: list[tuple[Any, ...]]) -> str:
    header = "Periodic database report\n"
    header += f"Rows returned: {len(rows)}\n\n"
    return header + format_rows_as_list(columns, rows)


def send_email(body: str) -> None:
    """Send the report via SMTP using settings from the environment."""
    smtp_host = os.environ["SMTP_HOST"]
    smtp_port = int(os.getenv("SMTP_PORT", "587"))
    smtp_user = os.getenv("SMTP_USER", "")
    smtp_password = os.getenv("SMTP_PASSWORD", "")
    use_tls = os.getenv("SMTP_USE_TLS", "true").lower() in {"1", "true", "yes"}
    email_from = os.environ["EMAIL_FROM"]
    email_to = os.environ["EMAIL_TO"]
    subject = os.getenv("EMAIL_SUBJECT", "Periodic database report")

    recipients = [addr.strip() for addr in email_to.split(",") if addr.strip()]
    if not recipients:
        raise ValueError("EMAIL_TO must contain at least one address")

    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = email_from
    msg["To"] = ", ".join(recipients)
    msg.attach(MIMEText(body, "plain", "utf-8"))

    with smtplib.SMTP(smtp_host, smtp_port, timeout=60) as server:
        if use_tls:
            server.starttls()
        if smtp_user:
            server.login(smtp_user, smtp_password)
        server.sendmail(email_from, recipients, msg.as_string())


def run_once() -> None:
    """Fetch DB rows with SQL_QUERY and email them as a list."""
    print("Running SQL query…")
    columns, rows = fetch_rows(SQL_QUERY)
    print(f"Fetched {len(rows)} row(s).")

    body = build_email_body(columns, rows)
    print("Sending email…")
    send_email(body)
    print("Email sent successfully.")


def run_loop(interval_minutes: int) -> None:
    """Send on a fixed interval until interrupted."""
    if schedule is None:
        raise SystemExit(
            "The 'schedule' package is required for --loop. "
            "Install dependencies with: pip install -r requirements.txt"
        )

    print(f"Scheduler started: sending every {interval_minutes} minute(s). Ctrl+C to stop.")
    schedule.every(interval_minutes).minutes.do(run_once)
    run_once()  # send immediately on start
    while True:
        schedule.run_pending()
        time.sleep(1)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Query the database and email the results as a list."
    )
    parser.add_argument(
        "--loop",
        action="store_true",
        help="Keep running and send periodically (see SEND_INTERVAL_MINUTES).",
    )
    return parser.parse_args()


def main() -> int:
    load_dotenv()
    args = parse_args()

    try:
        if args.loop:
            interval = int(os.getenv("SEND_INTERVAL_MINUTES", "60"))
            run_loop(interval)
        else:
            run_once()
    except KeyboardInterrupt:
        print("\nStopped.")
        return 0
    except Exception as exc:  # noqa: BLE001 — top-level CLI error reporting
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
