# GenericPHC

PHC / SQL Server utilities.

## do / ml header vs line totals

Documents whose `edebfin` / `ecrefin` do not match `SUM(ml.edeb)` / `SUM(ml.ecre)`
for a year. Faster than joining all lines then `GROUP BY` the display columns.

See `docs/do-ml-header-line-mismatch.md`.

- `sql/do_ml_header_line_mismatch.sql` — SSMS (temp table)
- `sql/do_ml_header_line_mismatch_select.sql` — single `SELECT` for PHC slots
- `sql/do_ml_header_line_mismatch_indexes.sql` — optional covering indexes
