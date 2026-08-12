-- lists."member reads" queried shares, and shares."owner manages members" queried
-- lists, so each policy re-entered the other: 42P17 infinite recursion, every
-- select on either table returning 500.
--
-- Both lookups now go through security definer functions. Those run with the
-- definer's rights, so the inner query does not evaluate RLS again and the cycle
-- is broken. They leak nothing: each returns a boolean about the caller's own
-- membership or ownership.

create or replace function is_member(l uuid) returns boolean
  language sql security definer stable set search_path = public as $$
    select exists (select 1 from shares where list_id = l and user_id = auth.uid())
  $$;

create or replace function owns_list(l uuid) returns boolean
  language sql security definer stable set search_path = public as $$
    select exists (select 1 from lists where id = l and owner = auth.uid())
  $$;

grant execute on function is_member(uuid), owns_list(uuid) to anon, authenticated;

drop policy if exists "member reads" on lists;
create policy "member reads" on lists for select using (is_member(id));

drop policy if exists "member writes" on lists;
create policy "member writes" on lists for update
  using (is_member(id)) with check (is_member(id));

drop policy if exists "owner manages members" on shares;
create policy "owner manages members" on shares for all
  using (owns_list(list_id)) with check (owns_list(list_id));
