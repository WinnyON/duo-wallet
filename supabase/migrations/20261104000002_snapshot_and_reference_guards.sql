alter table public.households alter column invite_code set default upper(encode(extensions.gen_random_bytes(16),'hex'));

create or replace function public.guard_record_references() returns trigger
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
  if tg_op = 'UPDATE' and new.household_id is distinct from old.household_id then raise exception 'Household is immutable'; end if;
  if tg_table_name = 'recurring_rules' then
    if tg_op = 'INSERT' and uid is not null and (new.created_by <> uid or new.paid_by <> uid) then raise exception 'Cannot impersonate rule creator'; end if;
    if tg_op = 'UPDATE' and (new.created_by <> old.created_by or new.paid_by <> old.paid_by) then raise exception 'Rule identity is immutable'; end if;
    if new.category_id is not null and not exists(select 1 from public.categories where id = new.category_id and household_id = new.household_id) then raise exception 'Invalid category'; end if;
    if new.to_account_id is not null and not exists(select 1 from public.accounts where id = new.to_account_id and household_id = new.household_id and (ownership='common' or owner_id=uid)) then raise exception 'Invalid destination'; end if;
  elsif tg_table_name = 'budgets' then
    if new.category_id is not null and not exists(select 1 from public.categories where id = new.category_id and household_id = new.household_id) then raise exception 'Invalid category'; end if;
    if new.scope = 'personal' and new.owner_id is distinct from uid then raise exception 'Invalid budget owner'; end if;
    if tg_op = 'UPDATE' and (new.owner_id is distinct from old.owner_id or new.scope <> old.scope) then raise exception 'Budget ownership is immutable'; end if;
  elsif tg_table_name = 'goals' then
    if new.scope = 'personal' and new.owner_id is distinct from uid then raise exception 'Invalid goal owner'; end if;
    if tg_op = 'UPDATE' and (new.owner_id is distinct from old.owner_id or new.scope <> old.scope) then raise exception 'Goal ownership is immutable'; end if;
    if exists(select 1 from unnest(new.linked_account_ids) as linked(account_id) where not exists(select 1 from public.accounts a where a.id=linked.account_id and a.household_id=new.household_id and (a.ownership='common' or (new.scope='personal' and a.owner_id=uid)))) then raise exception 'Invalid goal account'; end if;
    if exists(select 1 from jsonb_object_keys(new.contributions_by_user) as contributors(user_key) where not exists(select 1 from public.profiles p where p.id::text=contributors.user_key and p.household_id=new.household_id)) then raise exception 'Invalid goal contributor'; end if;
  elsif tg_table_name = 'activity' then
    if new.actor_id is distinct from uid then raise exception 'Cannot impersonate activity actor'; end if;
  elsif tg_table_name = 'categories' then
    if new.parent_id is not null and not exists(select 1 from public.categories where id = new.parent_id and household_id = new.household_id) then raise exception 'Invalid parent category'; end if;
  end if;
  return new;
end;
$$;
create trigger guard_record_references before insert or update on public.recurring_rules for each row execute function public.guard_record_references();
create trigger guard_record_references before insert or update on public.budgets for each row execute function public.guard_record_references();
create trigger guard_record_references before insert or update on public.goals for each row execute function public.guard_record_references();
create trigger guard_record_references before insert or update on public.categories for each row execute function public.guard_record_references();
create trigger guard_record_references before insert or update on public.activity for each row execute function public.guard_record_references();

-- One consistent statement snapshot under caller RLS, including tombstones.
create or replace function public.duo_snapshot() returns jsonb
language sql stable security invoker set search_path = '' as $$
select jsonb_build_object(
  'household', (select to_jsonb(h) from public.households h where id=public.my_household_id()),
  'profiles', coalesce((select jsonb_agg(to_jsonb(p)) from public.profiles p),'[]'::jsonb),
  'accounts', coalesce((select jsonb_agg(to_jsonb(a)) from public.accounts a),'[]'::jsonb),
  'categories', coalesce((select jsonb_agg(to_jsonb(c)) from public.categories c),'[]'::jsonb),
  'transactions', coalesce((select jsonb_agg(to_jsonb(t)||jsonb_build_object('transaction_shares',coalesce((select jsonb_agg(to_jsonb(s)) from public.transaction_shares s where s.transaction_id=t.id),'[]'::jsonb))) from public.transactions t),'[]'::jsonb),
  'budgets', coalesce((select jsonb_agg(to_jsonb(b)) from public.budgets b),'[]'::jsonb),
  'settlements', coalesce((select jsonb_agg(to_jsonb(s)) from public.settlements s),'[]'::jsonb),
  'settlement_postings', coalesce((select jsonb_agg(to_jsonb(s)) from public.settlement_postings s),'[]'::jsonb),
  'recurring_rules', coalesce((select jsonb_agg(to_jsonb(r)) from public.recurring_rules r),'[]'::jsonb),
  'account_valuations', coalesce((select jsonb_agg(to_jsonb(v)) from public.account_valuations v),'[]'::jsonb),
  'goals', coalesce((select jsonb_agg(to_jsonb(g)) from public.goals g),'[]'::jsonb),
  'activity', coalesce((select jsonb_agg(to_jsonb(a)) from public.activity a),'[]'::jsonb)
);
$$;
revoke all on function public.duo_snapshot(),public.guard_record_references() from public,anon;
grant execute on function public.duo_snapshot() to authenticated;
