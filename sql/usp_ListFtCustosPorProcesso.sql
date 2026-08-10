/*
  Stored procedure wrapper for the full FT / orçamento / custos query
  with dynamic naturcst columns from dytable.

  Example:
    EXEC dbo.usp_ListFtCustosPorProcesso @mProcesso = N'ABC123'
*/

CREATE OR ALTER PROCEDURE dbo.usp_ListFtCustosPorProcesso
    @mProcesso varchar(50)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @colsIif nvarchar(max);
    DECLARE @colsSum nvarchar(max);
    DECLARE @sql     nvarchar(max);

    SELECT @colsIif = STUFF((
        SELECT
            N',' + N'IIF(stobs.u_naturcst = N' + QUOTENAME(campo, '''')
            + N', bi.ettdeb, 0) AS ' + QUOTENAME(campo)
        FROM dytable WITH (NOLOCK)
        WHERE entityname = N'Jorinf_st_naturcst'
          AND NULLIF(LTRIM(RTRIM(campo)), N'') IS NOT NULL
        ORDER BY campo
        FOR XML PATH(N''), TYPE
    ).value(N'.', N'nvarchar(max)'), 1, 1, N'');

    SELECT @colsSum = STUFF((
        SELECT
            N',' + N'SUM(mCustos.' + QUOTENAME(campo) + N') AS ' + QUOTENAME(campo)
        FROM dytable WITH (NOLOCK)
        WHERE entityname = N'Jorinf_st_naturcst'
          AND NULLIF(LTRIM(RTRIM(campo)), N'') IS NOT NULL
        ORDER BY campo
        FOR XML PATH(N''), TYPE
    ).value(N'.', N'nvarchar(max)'), 1, 1, N'');

    IF @colsIif IS NULL OR @colsIif = N'' OR @colsSum IS NULL OR @colsSum = N''
    BEGIN
        RAISERROR(N'No classifications found in dytable for entityname=Jorinf_st_naturcst.', 16, 1);
        RETURN;
    END;

    SET @sql = N'
SELECT
    ft.nmdoc,
    ft.fno,
    ft.fdata,
    ft.nome,
    ft.vendnm,
    ft.ettiliq - ft.efinv AS venda,
    mOrc.nmdos,
    mOrc.obrano,
    mOrc.dataobra,
    mOrc.u_dataadju AS adjudicacao,' + @colsSum + N'
FROM ft WITH (NOLOCK)
INNER JOIN ft2 WITH (NOLOCK)
    ON ft.ftstamp = ft2.ft2stamp
LEFT JOIN (
    SELECT
        processo,
        nmdos,
        obrano,
        dataobra,
        u_dataadju
    FROM bo WITH (NOLOCK)
    INNER JOIN bo2 WITH (NOLOCK)
        ON bo.bostamp = bo2.bo2stamp
    WHERE bo.ndos = 100
      AND bo2.adjudicado = 1
) mOrc
    ON ft2.processo = mOrc.processo
INNER JOIN (
    SELECT
        ftstamp,
        SUM(qtt * ecusto) AS custo
    FROM fi WITH (NOLOCK)
    WHERE composto = 0
    GROUP BY ftstamp
) mFI
    ON ft.ftstamp = mFI.ftstamp
LEFT JOIN (
    SELECT
        bo.nmdos,
        bo.obrano,
        bo.dataobra,
        bo.marca,' + @colsIif + N'
    FROM bo WITH (NOLOCK)
    INNER JOIN bi WITH (NOLOCK)
        ON bo.bostamp = bi.bostamp
    INNER JOIN stobs WITH (NOLOCK)
        ON bi.ref = stobs.ref
    WHERE bo.ndos IN (105, 116, 118, 131)
      AND bi.ettdeb <> 0
) mCustos
    ON CONVERT(varchar, ft.fno) = mCustos.marca
   AND ft.ftano = YEAR(mCustos.dataobra)
WHERE ft.anulado = 0
  AND ft.ndoc IN (1, 3, 14, 15, 16, 19, 21, 22)
  AND ft2.processo = @mProcesso
GROUP BY
    ft.nmdoc,
    ft.fno,
    ft.fdata,
    ft.nome,
    ft.vendnm,
    ft.ettiliq,
    ft.efinv,
    mOrc.nmdos,
    mOrc.obrano,
    mOrc.dataobra,
    mOrc.u_dataadju;
';

    EXEC sys.sp_executesql
        @sql,
        N'@mProcesso varchar(50)',
        @mProcesso = @mProcesso;
END;
GO
