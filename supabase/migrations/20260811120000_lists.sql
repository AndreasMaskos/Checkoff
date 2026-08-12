-- Checkoff: one row per checklist, owned by one user, optionally shareable by token.

create table if not exists lists (
  id          uuid primary key,
  owner       uuid not null references auth.users on delete cascade,
  title       text not null,
  items       jsonb not null default '[]',
  share_token uuid,                               -- null = private
  deleted     boolean not null default false,     -- tombstone, so deletes propagate on sync
  updated_at  timestamptz not null default now()
);

create index if not exists lists_owner_idx on lists (owner);
create index if not exists lists_share_token_idx on lists (share_token) where share_token is not null;

alter table lists enable row level security;

drop policy if exists "owner" on lists;
create policy "owner" on lists for all
  using (auth.uid() = owner) with check (auth.uid() = owner);

-- Share links resolve through this function, never through a policy: a policy like
-- "share_token is not null" would let any signed-in user enumerate everyone else's
-- shared lists. security definer + an exact token match cannot leak more than the
-- one list whose token the caller already holds.
create or replace function shared_list(token uuid) returns setof lists
  language sql security definer stable set search_path = public as $$
    select * from lists where share_token = token and not deleted
  $$;

revoke all on function shared_list(uuid) from public;
grant execute on function shared_list(uuid) to anon, authenticated;
