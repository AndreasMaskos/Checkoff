-- Run history. The runner already measured every step's elapsed time and whether
-- it was done or skipped, then threw it away at Exit. One row per run, keyed by
-- the same id the log entries carry, so a run and its pictures line up.

create table if not exists runs (
  id          uuid primary key,                 -- the run_id stamped on log_entries
  list_id     uuid not null references lists on delete cascade,
  owner       uuid not null references auth.users on delete cascade,
  title       text not null,                    -- snapshot: the checklist may be renamed later
  started_at  timestamptz not null,
  finished_at timestamptz not null,
  steps       jsonb not null default '[]'       -- [{ text, state: true|false|null, secs }]
);
create index if not exists runs_list_idx on runs (list_id, started_at desc);

alter table runs enable row level security;

drop policy if exists "owner all" on runs;
create policy "owner all" on runs for all
  using (auth.uid() = owner) with check (auth.uid() = owner);

-- Same rule as the log: everyone on a live-shared list sees the same history.
drop policy if exists "member reads" on runs;
create policy "member reads" on runs for select using (is_member(list_id));

drop policy if exists "member writes" on runs;
create policy "member writes" on runs for insert
  with check (is_member(list_id) and auth.uid() = owner);
