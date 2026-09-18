/*
  Optional covering indexes for the do/ml header-line mismatch query.

  Check existing indexes first (section 1). PHC already clusters do and ml
  on their stamp PKs and often has a nonclustered index on ml.dostamp.
  Only create what is missing. Custom indexes on PHC tables can be dropped
  by product upgrades; recreate after a version update if needed.

  CREATE INDEX takes a schema lock. Prefer a quiet window. ONLINE = ON
  needs Enterprise / Developer edition; uncomment it if you have that.
*/

SET NOCOUNT ON;

/* -------------------------------------------------------------------------- */
/* 1) What is already there                                                   */
/* -------------------------------------------------------------------------- */
SELECT
    t.name AS table_name,
    i.name AS index_name,
    i.type_desc,
    i.is_unique,
    STUFF((
        SELECT N', ' + c.name + CASE WHEN ic.is_descending_key = 1 THEN N' DESC' ELSE N'' END
        FROM sys.index_columns AS ic
        INNER JOIN sys.columns AS c
            ON c.object_id = ic.object_id AND c.column_id = ic.column_id
        WHERE ic.object_id = i.object_id
          AND ic.index_id = i.index_id
          AND ic.is_included_column = 0
        ORDER BY ic.key_ordinal
        FOR XML PATH(''), TYPE
    ).value('.', 'nvarchar(max)'), 1, 2, N'') AS key_columns,
    STUFF((
        SELECT N', ' + c.name
        FROM sys.index_columns AS ic
        INNER JOIN sys.columns AS c
            ON c.object_id = ic.object_id AND c.column_id = ic.column_id
        WHERE ic.object_id = i.object_id
          AND ic.index_id = i.index_id
          AND ic.is_included_column = 1
        ORDER BY ic.index_column_id
        FOR XML PATH(''), TYPE
    ).value('.', 'nvarchar(max)'), 1, 2, N'') AS included_columns
FROM sys.indexes AS i
INNER JOIN sys.tables AS t ON t.object_id = i.object_id
WHERE t.name IN (N'do', N'ml')
  AND i.index_id > 0
ORDER BY t.name, i.index_id;

/* -------------------------------------------------------------------------- */
/* 2) do: seek on ano, cover the SELECT list (clustered PK already has stamp) */
/* -------------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.do', N'U') IS NOT NULL
   AND NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE object_id = OBJECT_ID(N'dbo.do')
          AND name = N'IX_do_ano_header_mismatch'
   )
BEGIN
    CREATE NONCLUSTERED INDEX IX_do_ano_header_mismatch
    ON dbo.do (ano)
    INCLUDE (data, dinome, dilno, docnome, adoc, edebfin, ecrefin)
    /* WITH (ONLINE = ON, MAXDOP = 4) */;
END;

/* -------------------------------------------------------------------------- */
/* 3) ml: seek on parent stamp, cover the two amounts (no key lookups)        */
/*    Skip this if an existing index on ml.dostamp already includes edeb/ecre */
/* -------------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.ml', N'U') IS NOT NULL
   AND NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE object_id = OBJECT_ID(N'dbo.ml')
          AND name = N'IX_ml_dostamp_edeb_ecre'
   )
BEGIN
    CREATE NONCLUSTERED INDEX IX_ml_dostamp_edeb_ecre
    ON dbo.ml (dostamp)
    INCLUDE (edeb, ecre)
    /* WITH (ONLINE = ON, MAXDOP = 4) */;
END;
