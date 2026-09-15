/*
  Real RAM used by THIS SQL Server instance.

  Why Task Manager is wrong
  --------------------------
  Task Manager shows the process Working Set. When the SQL Server service
  account has "Lock pages in memory" (LPIM), most of the buffer pool is
  allocated with AWE APIs and is NOT counted in the Working Set. The
  sqlservr.exe row can look almost empty while the instance is using tens
  of GB.

  physical_memory_in_use_kb (result set 1) is the figure to trust. It is
  the OS working set PLUS locked/large pages.

  Run once per instance in SSMS (connect to that instance), or use
  ps1/Get-SqlInstanceMemory.ps1 to query every instance on the box.

  Requires VIEW SERVER STATE (VIEW SERVER PERFORMANCE STATE on SQL 2022+).
  Compatible with SQL Server 2012 and later.
*/

SET NOCOUNT ON;

IF CAST(LEFT(CAST(SERVERPROPERTY('ProductVersion') AS varchar(32)), 2) AS int) < 11
BEGIN
    RAISERROR('This script needs SQL Server 2012 or later (physical_memory_kb / pages_kb).', 16, 1);
    RETURN;
END;

/* -------------------------------------------------------------------------- */
/* 1) Headline: this instance vs max server memory vs the OS                  */
/* -------------------------------------------------------------------------- */
DECLARE @max_server_memory_mb bigint =
    (
        SELECT CAST(value_in_use AS bigint)
        FROM sys.configurations
        WHERE name = N'max server memory (MB)'
    );

SELECT
    CAST(SERVERPROPERTY('MachineName') AS nvarchar(128)) AS host_name,
    CAST(ISNULL(SERVERPROPERTY('InstanceName'), N'MSSQLSERVER') AS nvarchar(128)) AS instance_name,
    @@SERVERNAME AS server_name,
    CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(32)) AS product_version,
    CAST(SERVERPROPERTY('Edition') AS nvarchar(128)) AS edition,
    CAST(ROUND(pm.physical_memory_in_use_kb / 1024.0, 1) AS decimal(18, 1)) AS physical_memory_in_use_mb,
    CAST(ROUND(pm.locked_page_allocations_kb / 1024.0, 1) AS decimal(18, 1)) AS locked_pages_mb,
    CAST(ROUND(pm.large_page_allocations_kb / 1024.0, 1) AS decimal(18, 1)) AS large_pages_mb,
    CASE
        WHEN pm.locked_page_allocations_kb > 0 THEN N'YES - Task Manager under-reports this instance'
        ELSE N'NO - Task Manager Working Set should be close'
    END AS lock_pages_in_memory,
    CASE
        WHEN @max_server_memory_mb >= 2147483647 THEN N'unlimited (default)'
        ELSE CAST(@max_server_memory_mb AS nvarchar(20))
    END AS max_server_memory_mb,
    CAST(ROUND(osi.physical_memory_kb / 1024.0, 1) AS decimal(18, 1)) AS os_physical_memory_mb,
    CAST(ROUND(sm.available_physical_memory_kb / 1024.0, 1) AS decimal(18, 1)) AS os_available_physical_memory_mb,
    sm.system_memory_state_desc,
    pm.process_physical_memory_low,
    pm.process_virtual_memory_low
FROM sys.dm_os_process_memory AS pm
CROSS JOIN sys.dm_os_sys_info AS osi
CROSS JOIN sys.dm_os_sys_memory AS sm;

/* -------------------------------------------------------------------------- */
/* 2) Memory clerks: which SQL components hold the RAM                        */
/*    MEMORYCLERK_SQLBUFFERPOOL is the data/index cache (usually the largest).*/
/* -------------------------------------------------------------------------- */
SELECT TOP (20)
    mc.type AS clerk_type,
    mc.name AS clerk_name,
    CAST(ROUND(SUM(mc.pages_kb) / 1024.0, 1) AS decimal(18, 1)) AS pages_mb,
    CAST(ROUND(SUM(mc.awe_allocated_kb) / 1024.0, 1) AS decimal(18, 1)) AS awe_allocated_mb,
    CAST(ROUND(SUM(mc.virtual_memory_committed_kb) / 1024.0, 1) AS decimal(18, 1)) AS virtual_committed_mb
FROM sys.dm_os_memory_clerks AS mc
GROUP BY mc.type, mc.name
HAVING SUM(mc.pages_kb) > 1024
ORDER BY SUM(mc.pages_kb) DESC;

/* -------------------------------------------------------------------------- */
/* 3) Buffer pool by database (data/index pages currently cached in RAM)      */
/*    Can take a few seconds on a large buffer pool.                          */
/* -------------------------------------------------------------------------- */
SELECT TOP (30)
    CASE
        WHEN bd.database_id = 32767 THEN N'resource'
        ELSE ISNULL(DB_NAME(bd.database_id), N'(unknown)')
    END AS database_name,
    CAST(COUNT(*) * 8 / 1024.0 AS decimal(18, 1)) AS cached_mb,
    CAST(SUM(CASE WHEN bd.is_modified = 1 THEN 1 ELSE 0 END) * 8 / 1024.0 AS decimal(18, 1)) AS dirty_mb
FROM sys.dm_os_buffer_descriptors AS bd
GROUP BY bd.database_id
ORDER BY COUNT(*) DESC;
