/*
  OCI costs by naturcst, with a subtotal row per u_tipo:
    u_tipo = same as the group
    campo  = 'Total'
    valor  = sum of valor for that u_tipo
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
),
base AS (
    SELECT
        dytable.u_tipo,
        dytable.campo,
        ISNULL(custOci.valor, 0) AS valor,
        dytable.dytablestamp
    FROM dytable WITH (NOLOCK)
    LEFT JOIN custOci
        ON dytable.campo = custOci.u_naturcst
    WHERE dytable.entityname = N'Jorinf_st_naturcst'
)
SELECT
    u_tipo,
    campo,
    valor
FROM (
    -- Detail lines
    SELECT
        u_tipo,
        campo,
        valor,
        dytablestamp,
        0 AS is_total
    FROM base

    UNION ALL

    -- Subtotal per u_tipo
    SELECT
        u_tipo,
        N'Total' AS campo,
        SUM(valor) AS valor,
        MAX(dytablestamp) AS dytablestamp,
        1 AS is_total
    FROM base
    GROUP BY u_tipo
) AS resultado
ORDER BY
    u_tipo,
    is_total,          -- details first, then Total
    dytablestamp;
