-- One entry, several files. Until now the card in the log was *derived* — same
-- run, same step, same minute, same description — so correcting the description
-- of one picture walked it out of the card it was logged with, and the same
-- moment appeared twice. group_id says outright what belongs together, and
-- nothing an edit does to a row can change its mind.

alter table log_entries add column if not exists group_id uuid;

-- Backfill what the derived rule meant, before any edit pulled it apart. The
-- description is deliberately not in the key: a description that diverged is
-- precisely the damage this repairs. Owner is, because two people logging the
-- same step of a shared run in the same minute did two things, not one.
update log_entries e set group_id = g.gid from (
  select id, first_value(id) over (
           partition by run_id, owner, step, date_trunc('minute', created_at)
           order by created_at, id) as gid
    from log_entries where run_id is not null and group_id is null) g
 where e.id = g.id and e.group_id is null;

-- A row from before run ids has no run to group by: it is its own entry.
update log_entries set group_id = id where group_id is null;

alter table log_entries alter column group_id set default gen_random_uuid();
alter table log_entries alter column group_id set not null;
create index if not exists log_entries_group_idx on log_entries (group_id);
