/*
  OCI costs by naturcst, with:
    - detail rows
    - a subtotal row per u_tipo (campo = 'Total')
    - a blank spacer row after each Total
    - a grand total row at the bottom (full sum of all valor)
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
        0 AS is_total,
        u_tipo AS sort_tipo,
        0 AS sort_block          -- normal groups
    FROM base

    UNION ALL

    -- Subtotal per u_tipo
    SELECT
        u_tipo,
        N'Total' AS campo,
        SUM(valor) AS valor,
        MAX(dytablestamp) AS dytablestamp,
        1 AS is_total,
        u_tipo AS sort_tipo,
        0 AS sort_block
    FROM base
    GROUP BY u_tipo

    UNION ALL

    -- Blank spacer row after each Total
    SELECT
        CAST(NULL AS varchar(50)) AS u_tipo,
        CAST(NULL AS nvarchar(100)) AS campo,
        CAST(NULL AS decimal(18, 2)) AS valor,
        CAST(NULL AS datetime) AS dytablestamp,
        2 AS is_total,
        u_tipo AS sort_tipo,
        0 AS sort_block
    FROM base
    GROUP BY u_tipo

    UNION ALL

    -- Grand total (full sum of all detail lines)
    SELECT
        N'Total Geral' AS u_tipo,
        N'Total Geral' AS campo,
        SUM(valor) AS valor,
        CAST(NULL AS datetime) AS dytablestamp,
        3 AS is_total,
        N'' AS sort_tipo,
        1 AS sort_block          -- force to bottom
    FROM base
) AS resultado
ORDER BY
    sort_block,        -- groups first, grand total last
    sort_tipo,
    is_total,          -- details, Total, blank
    dytablestamp;
