# Real memory usage of each SQL Server instance

Task Manager does **not** show how much RAM each `sqlservr.exe` is using when the
service account has **Lock pages in memory** (LPIM). That is the usual setup on
a dedicated SQL box. LPIM allocations use AWE APIs and are left out of the
process Working Set, which is the column Task Manager displays.

Use SQL itself. The trustworthy figure for one instance is:

```sql
SELECT
    physical_memory_in_use_kb / 1024.0 AS physical_memory_in_use_mb,
    locked_page_allocations_kb / 1024.0 AS locked_pages_mb
FROM sys.dm_os_process_memory;
```

`physical_memory_in_use_mb` is the real RAM for **that** instance (working set
+ locked pages + large pages). Do not add `locked_pages_mb` on top — locked
pages are already included.

DMVs are per process. Connect to each instance (or run the PowerShell helper
once on the server).

## Scripts in this repo

| File | Use |
| --- | --- |
| `sql/sql_instance_memory_usage.sql` | Paste in SSMS on one instance: headline RAM, top memory clerks, buffer pool by database |
| `ps1/Get-SqlInstanceMemory.ps1` | On the Windows SQL server: one row per instance, plus a sum |

```powershell
# On the SQL server, from an elevated prompt (Windows auth, VIEW SERVER STATE):
cd <repo>\ps1
powershell -ExecutionPolicy Bypass -File .\Get-SqlInstanceMemory.ps1
```

From a workstation:

```powershell
.\Get-SqlInstanceMemory.ps1 -Server SQLHOST -Instances MSSQLSERVER,PHC,CLIENT2
```

Default instance name is `MSSQLSERVER`. Named instances are the name after
`MSSQL$` in Services (`MSSQL$PHC` → `PHC`).

## PerfMon (no query)

If you cannot run a query, use these counters (one object per instance):

| Instance | Object |
| --- | --- |
| Default | `SQLServer:Memory Manager\Total Server Memory (KB)` |
| Named `PHC` | `MSSQL$PHC:Memory Manager\Total Server Memory (KB)` |

That is SQL-managed memory (close to, usually a bit under,
`physical_memory_in_use_kb`). It still includes locked pages. Also set
`SQLServer:Memory Manager\Target Server Memory (KB)` next to it.

Also check `SQLServer:Memory Manager\Total Server Memory` vs
`max server memory` in `sp_configure`. If several instances share one box,
cap **each** `max server memory` so the sum leaves RAM for Windows and other
instances (a common starting point is ~4–6 GB for the OS, then split the rest).

## What not to use

- Task Manager **Memory (Private Working Set)** / **Mem Usage**
- `Get-Process sqlservr | Select WS` — same Working Set gap
- Resource Monitor **Working Set** — same gap (Commit is closer, still not the
  official figure)

`DBCC MEMORYSTATUS` is a support dump, not a daily check. Prefer the DMV
above.
