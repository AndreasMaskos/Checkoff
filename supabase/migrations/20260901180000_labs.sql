-- A lab: one lead, some members, and the checklists that belong to it.
--
-- This is where access stops following the *list* and starts following the
-- *row's owner*. Until now everyone on a live-shared list saw the whole log,
-- which is one shared record and exactly wrong for a group where each person
-- keeps their own work: a member now sees what they logged, the lead sees
-- everything logged on the lab's checklists, and a member the lead has unlocked
-- sees the lab's work too. Personal checklists have no lab and are nobody
-- else's business — which is why the lab is on the *list* and not on the person.

create table if not exists labs (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  lead       uuid not null references auth.users on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists lab_members (
  lab_id    uuid not null references labs on delete cascade,
  user_id   uuid not null references auth.users on delete cascade,
  email     text,                             -- auth.users is not readable; this is how the list reads as people
  -- ponytail: one switch per member, not a grant per pair of people. "Can see
  -- the lab's work" is what was asked for; a lab_grants(viewer, subject) table
  -- is the upgrade if someone needs A to see B and not C.
  sees_all  boolean not null default false,
  joined_at timestamptz not null default now(),
  primary key (lab_id, user_id)
);

create table if not exists lab_invites (
  id         uuid primary key default gen_random_uuid(),
  lab_id     uuid not null references labs on delete cascade,
  email      text not null,
  created_at timestamptz not null default now(),
  unique (lab_id, email)
);

alter table lists add column if not exists lab_id uuid references labs on delete set null;
create index if not exists lists_lab_idx on lists (lab_id);

-- Every lookup a policy needs, as security definer so the inner query does not
-- evaluate RLS again — the same cure as is_member/owns_list, and for the same
-- disease: labs would ask about lab_members, which would ask about labs.
create or replace function in_lab(l uuid) returns boolean
  language sql security definer stable set search_path = public as $$
    select exists (select 1 from lab_members where lab_id = l and user_id = auth.uid()) $$;

create or replace function leads_lab(l uuid) returns boolean
  language sql security definer stable set search_path = public as $$
    select exists (select 1 from labs where id = l and lead = auth.uid()) $$;

create or replace function unlocked(l uuid) returns boolean
  language sql security definer stable set search_path = public as $$
    select exists (select 1 from lab_members
                    where lab_id = l and user_id = auth.uid() and sees_all) $$;

create or replace function list_lab(l uuid) returns uuid
  language sql security definer stable set search_path = public as $$
    select lab_id from lists where id = l $$;

-- The one rule the whole feature comes down to: my own row, or a row on a lab
-- checklist that I lead or have been unlocked in.
create or replace function may_see(l uuid, row_owner uuid) returns boolean
  language sql security definer stable set search_path = public as $$
    select row_owner = auth.uid()
        or (select lab_id is not null and (leads_lab(lab_id) or unlocked(lab_id))
              from lists where id = l) $$;

grant execute on function in_lab(uuid), leads_lab(uuid), unlocked(uuid),
                          list_lab(uuid), may_see(uuid, uuid) to anon, authenticated;

alter table labs        enable row level security;
alter table lab_members enable row level security;
alter table lab_invites enable row level security;

-- The lab itself is readable by everyone in it and changed only by its lead.
drop policy if exists "in the lab reads" on labs;
create policy "in the lab reads" on labs for select using (lead = auth.uid() or in_lab(id));
drop policy if exists "lead makes a lab" on labs;
create policy "lead makes a lab" on labs for insert with check (lead = auth.uid());
drop policy if exists "lead runs the lab" on labs;
create policy "lead runs the lab" on labs for update using (lead = auth.uid()) with check (lead = auth.uid());
drop policy if exists "lead ends the lab" on labs;
create policy "lead ends the lab" on labs for delete using (lead = auth.uid());

-- Who is in it is visible to everyone in it: a member should know who can read
-- their work. Only the lead adds, unlocks or removes anyone.
drop policy if exists "members are visible" on lab_members;
create policy "members are visible" on lab_members for select using (in_lab(lab_id));
drop policy if exists "lead manages members" on lab_members;
create policy "lead manages members" on lab_members for all
  using (leads_lab(lab_id)) with check (leads_lab(lab_id));
-- A lab needs its first member, and at that moment leads_lab() is already true.
drop policy if exists "lead joins own lab" on lab_members;
create policy "lead joins own lab" on lab_members for insert
  with check (leads_lab(lab_id) and user_id = auth.uid());

drop policy if exists "lead manages invites" on lab_invites;
create policy "lead manages invites" on lab_invites for all
  using (leads_lab(lab_id)) with check (leads_lab(lab_id));

-- Redeeming an invite is the one thing a stranger to the lab may do, and only
-- for an invite addressed to the address they signed in with.
create or replace function accept_lab_invites() returns int
  language plpgsql security definer set search_path = public as $$
  declare n int; addr text := lower(auth.jwt() ->> 'email');
  begin
    if addr is null then return 0; end if;
    insert into lab_members (lab_id, user_id, email)
      select i.lab_id, auth.uid(), addr from lab_invites i where lower(i.email) = addr
      on conflict (lab_id, user_id) do nothing;
    get diagnostics n = row_count;
    delete from lab_invites where lower(email) = addr;
    return n;
  end $$;
revoke execute on function accept_lab_invites() from public, anon;
grant  execute on function accept_lab_invites() to authenticated;

-- A lab checklist is readable and runnable by everyone in the lab.
drop policy if exists "lab reads lists" on lists;
create policy "lab reads lists" on lists for select
  using (lab_id is not null and in_lab(lab_id));

-- The log stops being one shared record. "member reads" granted everyone on a
-- live-shared list sight of every entry on it; that is the rule being replaced,
-- so it goes rather than sitting underneath as a second, looser way in.
drop policy if exists "member reads" on log_entries;
create policy "owner or lab reads" on log_entries for select using (may_see(list_id, owner));

drop policy if exists "member writes" on log_entries;
create policy "lab or member writes" on log_entries for insert with check (
  auth.uid() = owner and (is_member(list_id)
    or (list_lab(list_id) is not null and in_lab(list_lab(list_id)))));

drop policy if exists "member reads" on runs;
create policy "owner or lab reads" on runs for select using (may_see(list_id, owner));

drop policy if exists "member writes" on runs;
create policy "lab or member writes" on runs for insert with check (
  auth.uid() = owner and (is_member(list_id)
    or (list_lab(list_id) is not null and in_lab(list_lab(list_id)))));

-- Storage follows the same rule, and it can only do that if the owner is in the
-- object's name. New objects are "<list_id>/<owner>/<uuid>"; the ones already
-- written are "<list_id>/<uuid>" with no owner to check, so they keep the rule
-- they were written under rather than becoming unreadable.
create or replace function log_object_access(name text) returns boolean
  language sql stable set search_path = public as $$
    select case
      when split_part(name, '/', 1) !~ '^[0-9a-f-]{36}$' then false
      when split_part(name, '/', 2) ~ '^[0-9a-f-]{36}$'
        then may_see(split_part(name, '/', 1)::uuid, split_part(name, '/', 2)::uuid)
      else owns_list(split_part(name, '/', 1)::uuid) or is_member(split_part(name, '/', 1)::uuid)
    end $$;
grant execute on function log_object_access(text) to authenticated;
