/*
  Single-statement form of the header vs line mismatch check.

  Use this in PHC query slots that do not allow temp tables.
  Prefer sql/do_ml_header_line_mismatch.sql in SSMS on large years.

  Change the year in the docs CTE only.
*/

WITH docs AS (
    SELECT
        d.dostamp,
        d.data,
        d.dinome,
        d.dilno,
        d.docnome,
        d.adoc,
        d.edebfin,
        d.ecrefin
    FROM do AS d WITH (NOLOCK)
    WHERE d.ano = 2026
)
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
FROM docs AS d
INNER JOIN (
    SELECT
        ml.dostamp,
        SUM(ml.edeb) AS debito,
        SUM(ml.ecre) AS credito
    FROM ml WITH (NOLOCK)
    INNER JOIN docs AS d2 ON d2.dostamp = ml.dostamp
    GROUP BY ml.dostamp
) AS m ON m.dostamp = d.dostamp
WHERE d.edebfin <> m.debito
   OR d.ecrefin <> m.credito;
