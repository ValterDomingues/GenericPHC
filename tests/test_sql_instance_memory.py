"""Sanity checks for the SQL instance memory scripts."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL = (ROOT / "sql" / "sql_instance_memory_usage.sql").read_text(encoding="utf-8")
PS1 = (ROOT / "ps1" / "Get-SqlInstanceMemory.ps1").read_text(encoding="utf-8")
DOC = (ROOT / "docs" / "sql-instance-memory.md").read_text(encoding="utf-8")


def test_sql_uses_process_memory_dmv():
    assert "sys.dm_os_process_memory" in SQL
    assert "physical_memory_in_use_kb" in SQL
    assert "locked_page_allocations_kb" in SQL
    assert "sys.dm_os_memory_clerks" in SQL
    assert "sys.dm_os_buffer_descriptors" in SQL


def test_sql_does_not_add_locked_pages_on_top():
    # locked pages are a subset of physical_memory_in_use; no SUM of the two.
    assert "physical_memory_in_use_kb + locked" not in SQL.replace(" ", "").lower()
    assert "PLUS locked" in SQL or "plus locked" in SQL.lower()


def test_powershell_queries_each_instance():
    assert "sys.dm_os_process_memory" in PS1
    assert "Instance Names\\SQL" in PS1
    assert "Integrated Security=True" in PS1
    assert "PhysicalMemoryMB" in PS1


def test_docs_explain_task_manager():
    assert "Lock pages in memory" in DOC
    assert "physical_memory_in_use" in DOC
    assert "Get-SqlInstanceMemory.ps1" in DOC


if __name__ == "__main__":
    tests = [
        test_sql_uses_process_memory_dmv,
        test_sql_does_not_add_locked_pages_on_top,
        test_powershell_queries_each_instance,
        test_docs_explain_task_manager,
    ]
    for fn in tests:
        fn()
        print("ok", fn.__name__)
    print("all passed")
