/*
  Dynamic naturcst columns from dytable (replaces hardcoded IIF list).

  Source of classifications:
    SELECT campo FROM dytable (NOLOCK) WHERE entityname = 'Jorinf_st_naturcst'

  Builds expressions like:
    IIF(bi2.u_naturcst = N'Materiais', bi.ettdeb, 0) AS [Materiais],
    IIF(bi2.u_naturcst = N'Serviços Externos', bi.ettdeb, 0) AS [Serviços Externos],
    ...

  Uses FOR XML PATH to concatenate the column list safely (TYPE/.value keeps accents).
*/

SET NOCOUNT ON;

DECLARE @cols nvarchar(max);
DECLARE @sql  nvarchar(max);

-- Build dynamic IIF column list from dytable
SELECT @cols = STUFF((
    SELECT
        N',' + N'IIF(bi2.u_naturcst = N' + QUOTENAME(campo, '''')
        + N', bi.ettdeb, 0) AS ' + QUOTENAME(campo)
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

-- Same grain as the original query: one row per bi line
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
      );
';

-- Uncomment to inspect the generated statement:
-- PRINT @sql;

EXEC sys.sp_executesql @sql;
