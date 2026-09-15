# GenericPHC

PHC / SQL Server utilities.

## SQL instance memory (Task Manager is wrong)

When several SQL Server instances share one Windows box, Task Manager does not
show the real RAM of each `sqlservr.exe` if **Lock pages in memory** is enabled.

See `docs/sql-instance-memory.md`.

- `sql/sql_instance_memory_usage.sql` — run in SSMS on one instance
- `ps1/Get-SqlInstanceMemory.ps1` — one row per instance on the server
