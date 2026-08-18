-- A log is a record: deleting an entry hides it, it does not erase it. The row
-- stays visible in the log marked as deleted until someone deliberately purges
-- it, which is the only destructive action left in the UI.

alter table log_entries add column if not exists deleted_at timestamptz;
