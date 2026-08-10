/*
  Corrected: OCI costs by u_naturcst, aligned to dytable classifications.

  Fixes vs original:
  1) NOLOCK cannot be applied to a CTE alias (custOci) — only to base tables.
  2) SUM(...) OVER(PARTITION BY u_tipo ORDER BY ...) was a running total;
     drop ORDER BY to get the total per u_tipo (column name: totais).
  3) Filter dytable by entityname so only naturcst classifications are listed.
  4) Removed unused bo2 join from the CTE.
*/

;WITH custOci AS (
    SELECT
        oci.u_naturcst,
        ROUND(
            SUM(
                IIF(oci.qtttotal > 0, oci.qtttotal, oci.qtt)
                * IIF(oci.u_horas <> 0, oci.u_horas, 1)
                * IIF(oci.u_tecnicos <> 0, oci.u_tecnicos, 1)
                * oci.epcusto
            ),
            2
        ) AS valor
    FROM bo WITH (NOLOCK)
    INNER JOIN oci WITH (NOLOCK)
        ON bo.bostamp = oci.bostamp
    WHERE bo.bostamp = 'JDA25120259594,660000001'
    GROUP BY oci.u_naturcst
)
SELECT
    dytable.u_tipo,
    dytable.campo,
    ISNULL(custOci.valor, 0) AS valor,
    SUM(ISNULL(custOci.valor, 0)) OVER (
        PARTITION BY dytable.u_tipo
    ) AS totais
FROM dytable WITH (NOLOCK)
LEFT JOIN custOci
    ON dytable.campo = custOci.u_naturcst
WHERE dytable.entityname = N'Jorinf_st_naturcst'
ORDER BY
    dytable.u_tipo,
    dytable.dytablestamp;
