-- A forged client event must not turn private financial content into a shared feed.
drop policy activity_all on public.activity;
create policy activity_select on public.activity for select to authenticated
  using(household_id=public.my_household_id());
revoke insert,update,delete on public.activity from authenticated;
drop trigger guard_record_references on public.activity;

create or replace function public.record_shared_activity() returns trigger
language plpgsql security definer set search_path = '' as $$
declare ev text; en text; hu text; amount bigint; cur text; actor uuid;
begin
  actor := coalesce(auth.uid(),new.created_by);
  if tg_table_name='transactions' then
    if new.visibility<>'shared' or new.deleted_at is not null or tg_op<>'INSERT' then return new; end if;
    ev := case when new.kind='expense' then 'expense_added' when new.is_contribution then 'contribution_added' else 'transfer_added' end;
    en := 'Shared transaction recorded'; hu := 'Közös tranzakció rögzítve'; amount:=new.base_amount_minor; cur:='HUF';
  elsif tg_table_name='settlements' then
    if tg_op='INSERT' then ev:='settlement_proposed'; en:='Settlement proposed'; hu:='Elszámolás kezdeményezve';
    elsif new.from_confirmed and new.to_confirmed and not(old.from_confirmed and old.to_confirmed) then
      ev:='settlement_confirmed'; en:='Settlement confirmed'; hu:='Elszámolás megerősítve';
    else return new; end if;
    amount:=new.amount_minor;cur:=new.currency;
  end if;
  insert into public.activity(household_id,actor_id,event_type,entity_id,payload)
    values(new.household_id,actor,ev,new.id,jsonb_build_object('summary_en',en,'summary_hu',hu,'amount_minor',amount,'currency',cur));
  return new;
end;
$$;
create trigger record_shared_activity after insert on public.transactions for each row execute function public.record_shared_activity();
create trigger record_shared_activity after insert or update on public.settlements for each row execute function public.record_shared_activity();
revoke all on function public.record_shared_activity() from public,anon,authenticated;

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

revoke all on function public.guard_record_references() from public,anon,authenticated;
