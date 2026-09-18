/*
  Documents (do) whose header debit/credit totals do not match the sum of
  accounting lines (ml) for a given year.

  Same result columns as:

    SELECT do.data, do.dinome, do.dilno, do.docnome, do.adoc,
           do.edebfin, do.ecrefin, SUM(ml.edeb) debito, SUM(ml.ecre) credito
    FROM do (NOLOCK)
    INNER JOIN ml (NOLOCK) ON do.dostamp = ml.dostamp
    WHERE do.ano = 2026
    GROUP BY do.data, do.dinome, do.dilno, do.docnome, do.adoc,
             do.edebfin, do.ecrefin
    HAVING do.edebfin != SUM(ml.edeb) OR do.ecrefin != SUM(ml.ecre)

  Why this is faster
  ------------------
  The original join explodes to one row per ml line, then hashes a wide
  GROUP BY of display columns. This rewrite:

  1. Restricts do to @ano first (sargable; uses IX_do_ano_* if present).
  2. Aggregates ml by dostamp only (the parent key), for those documents.
  3. Compares header vs line totals after the aggregate (WHERE, not HAVING
     on the exploded join).
  4. Groups by dostamp so two documents that happen to share the same
     displayed fields are not merged (the original GROUP BY could).

  Optional indexes: sql/do_ml_header_line_mismatch_indexes.sql
  Background:       docs/do-ml-header-line-mismatch.md
*/

SET NOCOUNT ON;

DECLARE @ano INT = 2026;

IF OBJECT_ID('tempdb..#docs') IS NOT NULL
    DROP TABLE #docs;

SELECT
    d.dostamp,
    d.data,
    d.dinome,
    d.dilno,
    d.docnome,
    d.adoc,
    d.edebfin,
    d.ecrefin
INTO #docs
FROM do AS d WITH (NOLOCK)
WHERE d.ano = @ano;

CREATE UNIQUE CLUSTERED INDEX PK_docs ON #docs (dostamp);

SELECT
    d.data,
    d.dinome,
    d.dilno,
    d.docnome,
    d.adoc,
    d.edebfin,
    d.ecrefin,
    m.debito,
    m.credito
FROM #docs AS d
INNER JOIN (
    SELECT
        ml.dostamp,
        SUM(ml.edeb) AS debito,
        SUM(ml.ecre) AS credito
    FROM ml WITH (NOLOCK)
    INNER JOIN #docs AS d2 ON d2.dostamp = ml.dostamp
    GROUP BY ml.dostamp
) AS m ON m.dostamp = d.dostamp
WHERE d.edebfin <> m.debito
   OR d.ecrefin <> m.credito;
