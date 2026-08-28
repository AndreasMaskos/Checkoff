-- How much of the free tier's 1 GB the log files take up, answered in one call.
-- Listing it from the client would be a storage.list() per checklist, paginated
-- at 100 objects, and the sizes are already sitting in storage.objects.metadata.
--
-- Invoker rights on purpose: the "log objects" policy on storage.objects already
-- scopes a select to the lists you own or belong to, so the sum is filtered by
-- the very rule that decides what you can download. No security definer, and
-- nothing here to keep in step with that policy when it changes.
--
-- The quota is per project, not per user, so on a project with other people in
-- it this is your share and not the whole bill. Ours has one user.
create or replace function log_storage_used()
  returns table (bytes bigint, files bigint)
  language sql stable set search_path = public as $$
    select coalesce(sum((metadata->>'size')::bigint), 0)::bigint, count(*)::bigint
    from storage.objects
    where bucket_id = 'logs'
  $$;
grant execute on function log_storage_used() to authenticated;
