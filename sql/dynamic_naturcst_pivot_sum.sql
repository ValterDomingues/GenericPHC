/*
  Aggregated variant: one row per obra (nmdos/obrano/dataobra/marca)
  with SUM() per dynamic classification column.

  Prefer this for reports/email summaries.
*/

SET NOCOUNT ON;

DECLARE @cols     nvarchar(max);
DECLARE @colsSum  nvarchar(max);
DECLARE @sql      nvarchar(max);

SELECT @cols = STUFF((
    SELECT
        N',' + N'SUM(IIF(bi2.u_naturcst = N' + QUOTENAME(campo, '''')
        + N', bi.ettdeb, 0)) AS ' + QUOTENAME(campo)
    FROM dytable WITH (NOLOCK)
    WHERE entityname = N'Jorinf_st_naturcst'
      AND NULLIF(LTRIM(RTRIM(campo)), N'') IS NOT NULL
    ORDER BY campo
    FOR XML PATH(N''), TYPE
).value(N'.', N'nvarchar(max)'), 1, 1, N'');

IF @cols IS NULL OR @cols = N''
BEGIN
    RAISERROR(N'No classifications found in dytable for entityname=Jorinf_st_naturcst.', 16, 1);
    RETURN;
END;

SET @sql = N'
SELECT
    bo.nmdos,
    bo.obrano,
    bo.dataobra,
    bo.marca,' + @cols + N'
FROM bo WITH (NOLOCK)
INNER JOIN bi WITH (NOLOCK)
    ON bo.bostamp = bi.bostamp
INNER JOIN bi2 WITH (NOLOCK)
    ON bi.bistamp = bi2.bi2stamp
WHERE bo.ndos IN (105, 116, 118, 131)
  AND bi.ettdeb <> 0
  AND bi2.u_naturcst IN (
        SELECT campo
        FROM dytable WITH (NOLOCK)
        WHERE entityname = N''Jorinf_st_naturcst''
      )
GROUP BY
    bo.nmdos,
    bo.obrano,
    bo.dataobra,
    bo.marca
ORDER BY
    bo.nmdos,
    bo.obrano;
';

-- PRINT @sql;
EXEC sys.sp_executesql @sql;
