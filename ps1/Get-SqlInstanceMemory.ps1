<#
.SYNOPSIS
    Real RAM used by every SQL Server instance on a machine.

.DESCRIPTION
    Task Manager Working Set excludes Locked Pages in Memory, so sqlservr.exe
    often looks almost empty. This script connects to each instance and reads
    sys.dm_os_process_memory.physical_memory_in_use_kb - the OS working set
    plus locked/large pages.

    Run locally on the SQL server (recommended), or pass -Server and
    -Instances from a workstation with Windows auth.

    Requires VIEW SERVER STATE on each instance.

.EXAMPLE
    .\Get-SqlInstanceMemory.ps1

.EXAMPLE
    .\Get-SqlInstanceMemory.ps1 -Server SQLHOST -Instances MSSQLSERVER,PHC
#>
[CmdletBinding()]
param(
    [string]$Server = '.',
    [string[]]$Instances
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-LocalSqlInstanceNames {
    $names = New-Object System.Collections.Generic.List[string]
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Microsoft SQL Server\Instance Names\SQL'
    )
    foreach ($path in $paths) {
        if (-not (Test-Path $path)) { continue }
        $props = Get-ItemProperty -Path $path
        $props.PSObject.Properties |
            Where-Object { $_.Name -notlike 'PS*' } |
            ForEach-Object { [void]$names.Add($_.Name) }
    }
    if ($names.Count -eq 0) {
        Get-Service -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq 'MSSQLSERVER' -or $_.Name -like 'MSSQL$*' } |
            ForEach-Object {
                if ($_.Name -eq 'MSSQLSERVER') {
                    [void]$names.Add('MSSQLSERVER')
                } else {
                    [void]$names.Add($_.Name.Substring(6))
                }
            }
    }
    return $names | Select-Object -Unique | Sort-Object
}

function Get-SqlDataSource {
    param([string]$HostName, [string]$InstanceName)
    if ($InstanceName -eq 'MSSQLSERVER') { return $HostName }
    return ('{0}\{1}' -f $HostName, $InstanceName)
}

if (-not $Instances -or $Instances.Count -eq 0) {
    if ($Server -eq '.' -or $Server -eq '(local)' -or $Server -eq 'localhost' -or
        $Server -eq $env:COMPUTERNAME) {
        $Instances = @(Get-LocalSqlInstanceNames)
    }
    if (-not $Instances -or $Instances.Count -eq 0) {
        throw @'
No SQL instances found. Run this script on the SQL server, or pass them explicitly:

  .\Get-SqlInstanceMemory.ps1 -Server SQLHOST -Instances MSSQLSERVER,PHC,CLIENT2
'@
    }
}

$query = @'
SELECT
    CAST(ISNULL(SERVERPROPERTY('InstanceName'), N'MSSQLSERVER') AS nvarchar(128)) AS instance_name,
    @@SERVERNAME AS server_name,
    CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(32)) AS product_version,
    CAST(SERVERPROPERTY('Edition') AS nvarchar(128)) AS edition,
    CAST(ROUND(pm.physical_memory_in_use_kb / 1024.0, 1) AS decimal(18, 1)) AS physical_memory_in_use_mb,
    CAST(ROUND(pm.locked_page_allocations_kb / 1024.0, 1) AS decimal(18, 1)) AS locked_pages_mb,
    CAST(ROUND(pm.large_page_allocations_kb / 1024.0, 1) AS decimal(18, 1)) AS large_pages_mb,
    CASE WHEN pm.locked_page_allocations_kb > 0 THEN N'YES' ELSE N'NO' END AS lock_pages_in_memory,
    (
        SELECT CAST(value_in_use AS bigint)
        FROM sys.configurations
        WHERE name = N'max server memory (MB)'
    ) AS max_server_memory_mb,
    CAST(ROUND(osi.physical_memory_kb / 1024.0, 1) AS decimal(18, 1)) AS os_physical_memory_mb,
    CAST(ROUND(sm.available_physical_memory_kb / 1024.0, 1) AS decimal(18, 1)) AS os_available_mb,
    sm.system_memory_state_desc
FROM sys.dm_os_process_memory AS pm
CROSS JOIN sys.dm_os_sys_info AS osi
CROSS JOIN sys.dm_os_sys_memory AS sm;
'@

$rows = New-Object System.Collections.Generic.List[object]

foreach ($instanceName in $Instances) {
    $dataSource = Get-SqlDataSource -HostName $Server -InstanceName $instanceName
    $cs = 'Data Source={0};Initial Catalog=master;Integrated Security=True;Connection Timeout=8' -f $dataSource
    $row = [ordered]@{
        Instance                 = $instanceName
        ServerName               = $dataSource
        Status                   = $null
        PhysicalMemoryMB         = $null
        LockedPagesMB            = $null
        LargePagesMB             = $null
        LockPagesInMemory        = $null
        MaxServerMemoryMB        = $null
        OsPhysicalMemoryMB       = $null
        OsAvailableMB            = $null
        ProductVersion           = $null
        Edition                  = $null
        MemoryState              = $null
        Error                    = $null
    }
    $conn = New-Object System.Data.SqlClient.SqlConnection $cs
    try {
        $conn.Open()
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $query
        $cmd.CommandTimeout = 30
        $reader = $cmd.ExecuteReader()
        if ($reader.Read()) {
            $maxMb = [int64]$reader['max_server_memory_mb']
            $row.Status            = 'online'
            $row.ServerName        = [string]$reader['server_name']
            $row.PhysicalMemoryMB  = [decimal]$reader['physical_memory_in_use_mb']
            $row.LockedPagesMB     = [decimal]$reader['locked_pages_mb']
            $row.LargePagesMB      = [decimal]$reader['large_pages_mb']
            $row.LockPagesInMemory = [string]$reader['lock_pages_in_memory']
            $row.MaxServerMemoryMB = if ($maxMb -ge 2147483647) { 'unlimited' } else { $maxMb }
            $row.OsPhysicalMemoryMB = [decimal]$reader['os_physical_memory_mb']
            $row.OsAvailableMB     = [decimal]$reader['os_available_mb']
            $row.ProductVersion    = [string]$reader['product_version']
            $row.Edition           = [string]$reader['edition']
            $row.MemoryState       = [string]$reader['system_memory_state_desc']
        } else {
            $row.Status = 'no data'
        }
        $reader.Close()
    } catch {
        $row.Status = 'error'
        $row.Error = $_.Exception.Message
    } finally {
        if ($conn.State -ne 'Closed') { $conn.Close() }
        $conn.Dispose()
    }
    [void]$rows.Add((New-Object PSObject -Property $row))
}

$online = @($rows | Where-Object { $_.Status -eq 'online' })
$totalMb = 0
if ($online.Count -gt 0) {
    $totalMb = ($online | Measure-Object -Property PhysicalMemoryMB -Sum).Sum
}

Write-Host ''
Write-Host 'Real SQL Server memory (physical_memory_in_use_kb). Task Manager Working Set is not this number.'
if ($online.Count -gt 0) {
    Write-Host ("Instances online: {0}    Sum of instance RAM: {1:N1} MB ({2:N1} GB)" -f `
        $online.Count, $totalMb, ($totalMb / 1024))
}
Write-Host ''

$rows |
    Select-Object Instance, ServerName, Status, PhysicalMemoryMB, LockedPagesMB,
                  LockPagesInMemory, MaxServerMemoryMB, OsAvailableMB, ProductVersion, Error |
    Format-Table -AutoSize |
    Out-Host

if ($online.Count -gt 0 -and @($online | Where-Object { $_.LockPagesInMemory -eq 'YES' }).Count -gt 0) {
    Write-Host 'Lock Pages in Memory is ON for at least one instance - that is why Task Manager looks wrong.'
}

return $rows
