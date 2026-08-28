-- Postgres grants execute to PUBLIC on a new function, so the previous
-- migration's "grant to authenticated" changed nothing and anon could call
-- log_storage_used(). It leaked nothing -- invoker rights, and anon matches no
-- policy on storage.objects, so it read a truthful 0 -- but a function that is
-- safe only because RLS happens to be right is one policy edit from not being.
-- Signed out, there is no such thing as your usage.
revoke execute on function log_storage_used() from public;
grant execute on function log_storage_used() to authenticated;
