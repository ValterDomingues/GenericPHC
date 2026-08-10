/*
  Optional: wrap the dynamic pivot in a stored procedure for easy calls
  from VFP (SQLEXEC) or other clients.

  Example:
    EXEC dbo.usp_ListObranosNaturcst
    EXEC dbo.usp_ListObranosNaturcst @Aggregate = 1
*/

CREATE OR ALTER PROCEDURE dbo.usp_ListObranosNaturcst
    @Aggregate bit = 0  -- 0 = detail rows (like original), 1 = SUM per obra
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @cols nvarchar(max);
    DECLARE @sql  nvarchar(max);

    IF @Aggregate = 1
    BEGIN
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
    END
    ELSE
    BEGIN
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
    END

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
      )';

    IF @Aggregate = 1
        SET @sql += N'
GROUP BY
    bo.nmdos,
    bo.obrano,
    bo.dataobra,
    bo.marca
ORDER BY
    bo.nmdos,
    bo.obrano;';
    ELSE
        SET @sql += N';';

    EXEC sys.sp_executesql @sql;
END;
GO
