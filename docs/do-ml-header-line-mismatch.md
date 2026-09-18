# Faster do / ml header vs line mismatch query

PHC stores treasury/accounting documents in `do` and their posting lines in
`ml` (`ml.dostamp = do.dostamp`). `do.edebfin` / `do.ecrefin` are the header
totals; `ml.edeb` / `ml.ecre` are the line amounts. This query lists documents
in one year whose header totals do not match the sum of the lines.

## Original (slow)

```sql
SELECT do.data, do.dinome, do.dilno, do.docnome, do.adoc, do.edebfin, do.ecrefin,
    SUM(ml.edeb) debito, SUM(ml.ecre) credito
FROM do (NOLOCK)
INNER JOIN ml (NOLOCK) ON do.dostamp = ml.dostamp
WHERE do.ano = 2026
GROUP BY do.data, do.dinome, do.dilno, do.docnome, do.adoc, do.edebfin, do.ecrefin
HAVING do.edebfin != SUM(ml.edeb) OR do.ecrefin != SUM(ml.ecre)
```

Typical plan: join every `ml` line to its document, then hash-aggregate a
**wide** key (`dinome`, `docnome`, dates, amounts). On a busy year that is
hundreds of thousands of `do` rows times several `ml` lines each.

`do.ano = 2026` is already sargable (good). The cost is the join + the GROUP BY.

## What changed

| Change | Effect |
| --- | --- |
| Filter `do` by `ano` into `#docs` first | One year of headers, clustered on `dostamp` |
| Aggregate `ml` by `dostamp` only, joined to `#docs` | Reads line rows for that year only; narrow hash key |
| Compare with `WHERE` after the aggregate | No `HAVING` on the exploded join |
| Group by `dostamp`, not the display columns | One row per document; two docs with identical headers are not merged |

Result columns are the same. Documents with no `ml` rows stay excluded
(`INNER JOIN`), matching the original.

## Which script

| File | Use |
| --- | --- |
| `sql/do_ml_header_line_mismatch.sql` | SSMS / jobs (temp table; best plan on large years) |
| `sql/do_ml_header_line_mismatch_select.sql` | PHC query slot that must be a single `SELECT` |
| `sql/do_ml_header_line_mismatch_indexes.sql` | Optional covering indexes (check what exists first) |

Change `@ano` in the temp-table script, or the `2026` literal in the CTE of the
single-statement form.

## Indexes

PHC clustered PKs are `do.dostamp` and `ml.mlstamp`. A nonclustered index on
`ml.dostamp` is common. The optional script adds:

- `do (ano) INCLUDE (data, dinome, dilno, docnome, adoc, edebfin, ecrefin)`
- `ml (dostamp) INCLUDE (edeb, ecre)`

Skip either if a similar index already exists. Recreate after a PHC upgrade if
the product dropped them.

## How to compare

In SSMS:

```sql
SET STATISTICS IO, TIME ON;
-- original, then the rewrite
```

Look at logical reads on `do` and `ml`, and elapsed time. The rewrite should
avoid a worktable/hash on the full joined rowset.

`NOLOCK` is kept for the usual PHC reporting pattern (dirty reads). Do not use
it if you need a consistent snapshot of a year that is still being posted.
