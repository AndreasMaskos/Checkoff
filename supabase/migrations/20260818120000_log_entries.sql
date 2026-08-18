-- Photo log: what actually happened on a step, with a timestamp. One row per
-- upload; the image itself lives in the private "logs" storage bucket and the
-- row holds its path, so the log survives even when a picture is deleted.

create table if not exists log_entries (
  id         uuid primary key default gen_random_uuid(),
  list_id    uuid not null references lists on delete cascade,
  owner      uuid not null references auth.users on delete cascade,
  step       int  not null,                    -- index into lists.items at upload time
  step_text  text not null,                    -- snapshot: steps get renamed, the log should not change
  note       text not null default '',
  path       text,                             -- object in the "logs" bucket, null = note only
  created_at timestamptz not null default now()
);
create index if not exists log_entries_list_idx on log_entries (list_id, created_at desc);

alter table log_entries enable row level security;

drop policy if exists "owner all" on log_entries;
create policy "owner all" on log_entries for all
  using (auth.uid() = owner) with check (auth.uid() = owner);

-- Everyone on a live-shared list sees and adds to the same log: the point of
-- sharing a lab checklist is one record, not one per person.
drop policy if exists "member reads" on log_entries;
create policy "member reads" on log_entries for select using (is_member(list_id));

drop policy if exists "member writes" on log_entries;
create policy "member writes" on log_entries for insert
  with check (is_member(list_id) and auth.uid() = owner);

-- Private bucket. The client reads through short-lived signed URLs, so an
-- image link cannot be forwarded to someone outside the list forever.
insert into storage.buckets (id, name, public) values ('logs', 'logs', false)
  on conflict (id) do nothing;

-- Objects are named "<list_id>/<uuid>.jpg", so access follows the list. The
-- shape check keeps a hand-uploaded file from erroring the whole policy on cast.
create or replace function log_object_access(name text) returns boolean
  language sql stable set search_path = public as $$
    select case when split_part(name, '/', 1) ~ '^[0-9a-f-]{36}$'
                then owns_list(split_part(name, '/', 1)::uuid)
                  or is_member(split_part(name, '/', 1)::uuid)
                else false end
  $$;
grant execute on function log_object_access(text) to authenticated;

drop policy if exists "log objects" on storage.objects;
create policy "log objects" on storage.objects for all to authenticated
  using (bucket_id = 'logs' and log_object_access(name))
  with check (bucket_id = 'logs' and log_object_access(name));
