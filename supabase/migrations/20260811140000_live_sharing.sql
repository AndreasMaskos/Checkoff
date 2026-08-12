-- Live sharing: a share link can now hand over a copy (as before) or admit the
-- recipient to the same list. Everyone admitted to a live list is an equal editor.
-- ponytail: no can_edit column until someone actually asks for view-only.

alter table lists add column if not exists share_mode text not null default 'copy'
  check (share_mode in ('copy', 'live'));

create table if not exists shares (
  list_id  uuid not null references lists on delete cascade,
  user_id  uuid not null references auth.users on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (list_id, user_id)
);
create index if not exists shares_user_idx on shares (user_id);
alter table shares enable row level security;

drop policy if exists "read own membership" on shares;
create policy "read own membership" on shares for select using (user_id = auth.uid());

drop policy if exists "leave" on shares;
create policy "leave" on shares for delete using (user_id = auth.uid());

drop policy if exists "owner manages members" on shares;
create policy "owner manages members" on shares for all
  using (exists (select 1 from lists l where l.id = list_id and l.owner = auth.uid()));

drop policy if exists "owner" on lists;
drop policy if exists "owner all" on lists;
create policy "owner all" on lists for all
  using (auth.uid() = owner) with check (auth.uid() = owner);

drop policy if exists "member reads" on lists;
create policy "member reads" on lists for select
  using (exists (select 1 from shares s where s.list_id = id and s.user_id = auth.uid()));

drop policy if exists "member writes" on lists;
create policy "member writes" on lists for update
  using (exists (select 1 from shares s where s.list_id = id and s.user_id = auth.uid()))
  with check (exists (select 1 from shares s where s.list_id = id and s.user_id = auth.uid()));

-- RLS grants a member write access to the whole row, which is more than we mean.
-- This trigger is the actual boundary: members edit content, owners control
-- ownership, deletion and who gets in.
create or replace function lists_member_guard() returns trigger
  language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is distinct from old.owner then
    if new.owner is distinct from old.owner then
      raise exception 'only the owner can transfer a list';
    end if;
    if new.deleted and not old.deleted then
      raise exception 'only the owner can delete a list';
    end if;
    new.share_token := old.share_token;      -- members cannot mint or rotate links
    new.share_mode  := old.share_mode;
  end if;
  return new;
end $$;

drop trigger if exists lists_member_guard on lists;
create trigger lists_member_guard before update on lists
  for each row execute function lists_member_guard();

-- Joining a live list. security definer because the caller cannot see the row
-- until the membership exists — but it only ever resolves an exact token.
create or replace function accept_invite(token uuid) returns uuid
  language plpgsql security definer set search_path = public as $$
declare target uuid;
begin
  if auth.uid() is null then
    raise exception 'sign in to join a shared list';
  end if;
  select id into target from lists
    where share_token = token and share_mode = 'live' and not deleted;
  if target is null then
    return null;
  end if;
  insert into shares (list_id, user_id) values (target, auth.uid())
    on conflict do nothing;
  return target;
end $$;

revoke all on function accept_invite(uuid) from public;
grant execute on function accept_invite(uuid) to authenticated;
