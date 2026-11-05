-- Client/schema alignment. Passwords remain exclusively in Supabase Auth.
alter table public.profiles add column if not exists avatar_type text not null default 'initials';
alter table public.profiles add column if not exists avatar_url text;
alter table public.transactions add column if not exists tags text[] not null default '{}';
alter table public.goals add column if not exists saved_amount_minor bigint not null default 0 check (saved_amount_minor >= 0);
alter table public.goals add column if not exists annual_interest_rate_pct numeric not null default 0;
alter table public.goals add column if not exists linked_account_ids uuid[] not null default '{}';
alter table public.goals add column if not exists contributions_by_user jsonb not null default '{}'::jsonb;

-- Membership is assigned only by the authenticated create/join RPCs. A user must
-- not be able to join an arbitrary household by updating their own profile.
revoke all on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;
grant update(display_name, color, locale, monthly_common_contribution_minor, avatar_type, avatar_url)
  on public.profiles to authenticated;
revoke all on public.households from anon, authenticated;
grant select on public.households to authenticated;
grant update(name, default_split_pct, emergency_fund_months) on public.households to authenticated;

create or replace function public.my_household_id() returns uuid
language sql stable security definer set search_path = '' as $$
  select p.household_id from public.profiles p join auth.users u on u.id = p.id
    where p.id = auth.uid() and u.email_confirmed_at is not null;
$$;

-- Transaction security is derived from actual accounts on every write, never
-- from client-supplied paid_from_common or is_contribution flags.
create or replace function public.set_transaction_visibility() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  src public.accounts; dst public.accounts;
  actor uuid := auth.uid(); computed text;
begin
  select * into src from public.accounts where id = new.account_id and deleted_at is null;
  if src.id is null or src.household_id <> new.household_id then raise exception 'Invalid source account'; end if;
  if tg_op = 'INSERT' then
    if actor is not null and (new.created_by <> actor or new.paid_by <> actor) then raise exception 'Cannot impersonate another user'; end if;
  else
    if new.household_id <> old.household_id or new.created_by <> old.created_by or new.paid_by <> old.paid_by then
      raise exception 'Transaction identity is immutable';
    end if;
  end if;
  if src.ownership = 'personal' and src.owner_id <> new.paid_by then raise exception 'Cannot use partner personal account'; end if;
  if actor is not null and src.ownership = 'personal' and src.owner_id <> actor and
     (tg_op = 'INSERT' or new.account_id is distinct from old.account_id) then raise exception 'Cannot use partner personal account'; end if;
  new.paid_from_common := src.ownership = 'common';
  new.is_contribution := false;
  if new.kind = 'transfer' then
    select * into dst from public.accounts where id = new.to_account_id and household_id = new.household_id and deleted_at is null;
    if dst.id is null or dst.id = src.id or new.to_account_amount_minor is null then raise exception 'Invalid transfer destination'; end if;
    if actor is not null and dst.ownership = 'personal' and dst.owner_id <> actor and
      (tg_op = 'INSERT' or new.to_account_id is distinct from old.to_account_id) then raise exception 'Cannot credit partner personal account'; end if;
    new.is_contribution := src.ownership = 'personal' and dst.ownership = 'common';
  elsif new.to_account_id is not null then raise exception 'Only transfers have a destination';
  end if;
  if new.category_id is not null and not exists(select 1 from public.categories where id = new.category_id and household_id = new.household_id) then raise exception 'Invalid category'; end if;
  if new.recurring_rule_id is not null and not exists(select 1 from public.recurring_rules where id = new.recurring_rule_id and household_id = new.household_id) then raise exception 'Invalid recurring rule'; end if;
  if new.kind = 'expense' then
    if new.paid_from_common then new.scope := 'together'; end if;
    computed := case when new.scope = 'together' then 'shared' else 'private' end;
  else
    computed := case when new.paid_from_common or dst.ownership = 'common' then 'shared' else 'private' end;
    new.scope := case when computed = 'shared' then 'together' else 'individual' end;
  end if;
  if tg_op = 'UPDATE' and (computed <> old.visibility or new.visibility <> old.visibility) then
    raise exception 'Transaction visibility is immutable; create a new row and soft-delete the old one';
  end if;
  new.visibility := computed;
  return new;
end;
$$;

create or replace function public.guard_account_identity() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.ownership = 'common' and new.owner_id is not null then raise exception 'Common accounts have no private owner'; end if;
  if tg_op = 'UPDATE' and (new.household_id <> old.household_id or new.ownership <> old.ownership or new.owner_id is distinct from old.owner_id) then
    raise exception 'Account ownership is immutable';
  end if;
  return new;
end;
$$;
create trigger guard_account_identity before insert or update on public.accounts
  for each row execute function public.guard_account_identity();

create or replace function public.check_settlement_confirmation() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if not exists(select 1 from public.profiles where id = new.from_user and household_id = new.household_id) or
     not exists(select 1 from public.profiles where id = new.to_user and household_id = new.household_id) then raise exception 'Invalid settlement participants'; end if;
  if auth.uid() is not null and auth.uid() not in (new.from_user, new.to_user) then raise exception 'Not a settlement participant'; end if;
  if tg_op = 'INSERT' then
    if auth.uid() is distinct from new.created_by then raise exception 'Cannot impersonate proposer'; end if;
    if new.from_confirmed and auth.uid() is distinct from new.from_user then raise exception 'Only from_user can set from_confirmed'; end if;
    if new.to_confirmed and auth.uid() is distinct from new.to_user then raise exception 'Only to_user can set to_confirmed'; end if;
  else
    if row(new.household_id,new.created_by,new.from_user,new.to_user,new.amount_minor,new.base_amount_minor,new.currency) is distinct from
       row(old.household_id,old.created_by,old.from_user,old.to_user,old.amount_minor,old.base_amount_minor,old.currency) then raise exception 'Settlement proposal is immutable'; end if;
    if old.from_confirmed then new.from_confirmed := true; end if;
    if old.to_confirmed then new.to_confirmed := true; end if;
    if new.from_confirmed and not old.from_confirmed and auth.uid() is distinct from new.from_user then raise exception 'Only from_user can set from_confirmed'; end if;
    if new.to_confirmed and not old.to_confirmed and auth.uid() is distinct from new.to_user then raise exception 'Only to_user can set to_confirmed'; end if;
    if old.status = 'confirmed' and (new.deleted_at is distinct from old.deleted_at or new.rejected_by is distinct from old.rejected_by) then raise exception 'Confirmed settlement is immutable'; end if;
    if old.rejected_by is not null and new.rejected_by is distinct from old.rejected_by then raise exception 'Rejected settlement is immutable'; end if;
  end if;
  if new.rejected_by is not null and new.rejected_by is distinct from auth.uid() then raise exception 'Cannot impersonate rejection'; end if;
  return new;
end;
$$;

-- Private postings must reference the actor's actual account and a proposal in
-- their household; guessing another user's settlement/account IDs is insufficient.
drop policy settlement_postings_all on public.settlement_postings;
create policy settlement_postings_all on public.settlement_postings for all to authenticated
using (user_id = auth.uid()) with check (
  user_id = auth.uid() and
  exists(select 1 from public.accounts a where a.id = account_id and a.ownership = 'personal' and a.owner_id = auth.uid()) and
  exists(select 1 from public.settlements s where s.id = settlement_id and auth.uid() in (s.from_user,s.to_user))
);

-- A share cannot name a user outside the parent transaction's household.
create or replace function public.check_transaction_shares() returns trigger
language plpgsql security definer set search_path = '' as $$
declare t public.transactions; tid uuid;
begin
  tid := case when tg_table_name = 'transactions' then new.id else coalesce(new.transaction_id,old.transaction_id) end;
  select * into t from public.transactions where id = tid;
  if t.id is null or t.deleted_at is not null or t.kind <> 'expense' then return null; end if;
  if exists(select 1 from public.transaction_shares s left join public.profiles p on p.id = s.user_id
    where s.transaction_id = tid and (p.household_id is distinct from t.household_id or (t.scope = 'individual' and s.user_id <> t.created_by))) then raise exception 'Invalid share participant'; end if;
  if (select coalesce(sum(share_minor),0) from public.transaction_shares where transaction_id = tid) <> t.amount_minor or
     (select coalesce(sum(share_base_minor),0) from public.transaction_shares where transaction_id = tid) <> t.base_amount_minor then raise exception 'Shares must equal transaction amount'; end if;
  return null;
end;
$$;
create constraint trigger transaction_shares_total after insert or update on public.transactions
  deferrable initially deferred for each row execute function public.check_transaction_shares();
create constraint trigger transaction_shares_total after insert or update or delete on public.transaction_shares
  deferrable initially deferred for each row execute function public.check_transaction_shares();

-- Transaction + shares are saved atomically. This is invoker security: the
-- caller's JWT/RLS still controls every parent and child write.
create or replace function public.duo_save_transaction(p_transaction jsonb, p_shares jsonb, p_base_shares jsonb) returns void
language plpgsql security invoker set search_path = '' as $$
declare t public.transactions;
begin
  if auth.uid() is null or public.my_household_id() is null then raise exception 'Verified membership required'; end if;
  t := jsonb_populate_record(null::public.transactions,p_transaction);
  insert into public.transactions select t.* on conflict(id) do update set
    kind=excluded.kind,scope=excluded.scope,visibility=excluded.visibility,occurred_on=excluded.occurred_on,
    amount_minor=excluded.amount_minor,currency=excluded.currency,fx_rate_to_base=excluded.fx_rate_to_base,
    fx_source=excluded.fx_source,base_amount_minor=excluded.base_amount_minor,paid_by=excluded.paid_by,
    paid_from_common=excluded.paid_from_common,account_id=excluded.account_id,account_amount_minor=excluded.account_amount_minor,
    to_account_id=excluded.to_account_id,to_account_amount_minor=excluded.to_account_amount_minor,is_contribution=excluded.is_contribution,
    category_id=excluded.category_id,merchant=excluded.merchant,note=excluded.note,recurring_rule_id=excluded.recurring_rule_id,
    deleted_at=excluded.deleted_at,tags=excluded.tags;
  delete from public.transaction_shares where transaction_id=t.id;
  insert into public.transaction_shares(transaction_id,user_id,share_minor,share_base_minor)
    select t.id,key::uuid,value::bigint,coalesce((p_base_shares->>key)::bigint,0) from jsonb_each_text(p_shares);
end;
$$;

-- No anonymous finance API and no destructive client DELETEs on domain records.
revoke all on all tables in schema public from anon;
revoke delete on public.accounts,public.transactions,public.categories,public.recurring_rules,public.budgets,
  public.goals,public.settlements,public.settlement_postings,public.account_valuations,public.activity from authenticated;
revoke all on all functions in schema public from public, anon, authenticated;
grant execute on function public.my_household_id(), public.create_household(text,text,text),public.join_household(text,text,text),
  public.get_balance(),public.monthly_totals(int,text),public.category_totals(date,date,text),
  public.duo_save_transaction(jsonb,jsonb,jsonb) to authenticated;
grant execute on function public.generate_recurring(date),public.post_interest(date) to service_role;

-- Private per-user backup objects. No public URLs, no cross-user reads/writes.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('backups','backups',false,10485760,array['application/json']) on conflict(id) do update set public=false;
create policy duo_backups_select on storage.objects for select to authenticated
using(bucket_id='backups' and (storage.foldername(name))[1]=auth.uid()::text);
create policy duo_backups_insert on storage.objects for insert to authenticated
with check(bucket_id='backups' and (storage.foldername(name))[1]=auth.uid()::text);
create policy duo_backups_update on storage.objects for update to authenticated
using(bucket_id='backups' and (storage.foldername(name))[1]=auth.uid()::text)
with check(bucket_id='backups' and (storage.foldername(name))[1]=auth.uid()::text);
create policy duo_backups_delete on storage.objects for delete to authenticated
using(bucket_id='backups' and (storage.foldername(name))[1]=auth.uid()::text);

-- Hardened idempotent membership onboarding.
create or replace function create_household(
  p_name text,
  p_display_name text,
  p_color text
) returns uuid
language plpgsql security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_hh_id uuid;
begin
  if v_uid is null or not exists(select 1 from auth.users where id = v_uid and email_confirmed_at is not null) then
    raise exception 'Authentication required';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_uid::text,0));
  select household_id into v_hh_id from profiles where id = v_uid for update;
  if v_hh_id is not null then return v_hh_id; end if;
  if length(trim(p_name)) not between 1 and 80 or length(trim(p_display_name)) not between 1 and 80 then raise exception 'Invalid name'; end if;

  insert into households (name)
  values (p_name)
  returning id into v_hh_id;

  insert into profiles (id, household_id, display_name, color)
  values (v_uid, v_hh_id, p_display_name, p_color)
  on conflict (id) do update
    set household_id = excluded.household_id,
        display_name = excluded.display_name,
        color = excluded.color;

  insert into categories (household_id, kind, system_key, name_en, name_hu, icon, color, is_essential, sort_order)
  values
    (v_hh_id, 'expense', 'groceries',  'Groceries',             'Élelmiszer',             'shopping_cart',  '#10B981', true,  1),
    (v_hh_id, 'expense', 'housing',    'Housing & Utilities',   'Lakhatás és rezsi',      'home',           '#3B82F6', true,  2),
    (v_hh_id, 'expense', 'dining',     'Dining & Coffee',       'Étterem és kávé',        'restaurant',     '#F59E0B', false, 3),
    (v_hh_id, 'expense', 'transport',  'Transport',             'Közlekedés',             'directions_car', '#6366F1', true,  4),
    (v_hh_id, 'expense', 'health',     'Health',                'Egészség',               'favorite',       '#EF4444', true,  5),
    (v_hh_id, 'expense', 'fun',        'Entertainment & Gifts', 'Szórakozás és ajándék',  'celebration',    '#EC4899', false, 6),
    (v_hh_id, 'income',  'salary',     'Salary',                'Fizetés',                'payments',       '#14B8A6', false, 7),
    (v_hh_id, 'income',  'interest',   'Interest & Returns',    'Kamat és hozam',         'trending_up',    '#0EA5E9', false, 8);

  insert into accounts (household_id, name, type, ownership, owner_id, currency, opening_balance_minor, opening_date, icon, color)
  values (v_hh_id, p_display_name || ' Cash', 'cash', 'personal', v_uid, 'HUF', 0, current_date, 'payments', p_color);

  return v_hh_id;
end;
$$;

-- 2. join_household: enforces 2-member limit, joins household, creates personal Cash account
create or replace function join_household(
  p_invite_code text,
  p_display_name text,
  p_color text
) returns uuid
language plpgsql security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_hh_id uuid;
  v_member_count int;
begin
  if v_uid is null or not exists(select 1 from auth.users where id = v_uid and email_confirmed_at is not null) then
    raise exception 'Authentication required';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_uid::text,0));
  if exists(select 1 from profiles where id = v_uid and household_id is not null) then raise exception 'Already belongs to a household'; end if;
  if length(trim(p_display_name)) not between 1 and 80 then raise exception 'Invalid display name'; end if;

  select id into v_hh_id
    from households
   where upper(invite_code) = upper(trim(p_invite_code))
   for update;

  if v_hh_id is null then
    raise exception 'Invalid invite code';
  end if;

  select count(*) into v_member_count
    from profiles
   where household_id = v_hh_id
     and id <> v_uid;

  if v_member_count >= 2 then
    raise exception 'Household already has 2 members';
  end if;

  insert into profiles (id, household_id, display_name, color)
  values (v_uid, v_hh_id, p_display_name, p_color)
  on conflict (id) do update
    set household_id = excluded.household_id,
        display_name = excluded.display_name,
        color = excluded.color;

  insert into accounts (household_id, name, type, ownership, owner_id, currency, opening_balance_minor, opening_date, icon, color)
  values (v_hh_id, p_display_name || ' Cash', 'cash', 'personal', v_uid, 'HUF', 0, current_date, 'payments', p_color);

  return v_hh_id;
end;
$$;


revoke all on function public.create_household(text,text,text),public.join_household(text,text,text) from public,anon;
grant execute on function public.create_household(text,text,text),public.join_household(text,text,text) to authenticated;
