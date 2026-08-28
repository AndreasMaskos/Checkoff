-- Revoking from PUBLIC was not enough. Supabase ships default privileges that
-- grant execute on new public-schema functions to anon and authenticated by
-- name, so anon kept a grant of its own and went on answering.
--
-- Revoke both: PUBLIC for the Postgres default, anon for Supabase's. Any
-- function added here that is not meant for signed-out callers needs the same
-- pair -- the grant line alone reads as if it restricts, and it does not.
revoke execute on function log_storage_used() from public;
revoke execute on function log_storage_used() from anon;
grant execute on function log_storage_used() to authenticated;
