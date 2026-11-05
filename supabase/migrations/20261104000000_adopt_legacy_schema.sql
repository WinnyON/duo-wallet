-- The hosted project predates the checked-in canonical baseline. Adopt it with
-- ALTER/backfill rather than resetting or replaying CREATE TABLE over user data.
do $adopt$
declare r record;
begin
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='goals' and column_name='user_id') then return; end if;
  for r in select tablename,policyname from pg_policies where schemaname='public' loop
    execute format('drop policy %I on public.%I',r.policyname,r.tablename);
  end loop;
  for r in select c.relname,t.tgname from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and not t.tgisinternal loop
    execute format('drop trigger %I on public.%I',r.tgname,r.relname);
  end loop;
  alter table public.budgets rename column user_id to owner_id;
  alter table public.goals rename column user_id to owner_id;
  alter table public.goals rename column target_amount_minor to target_minor;
  alter table public.categories rename column name to name_en;
  alter table public.categories add column name_hu text;
  update public.categories set name_hu=name_en;
  alter table public.categories alter column name_hu set not null;
  alter table public.recurring_rules rename column interval_amount to interval_count;
  alter table public.recurring_rules rename column next_due to next_due_date;
  alter table public.recurring_rules add column title text not null default 'Recurring bill';
  alter table public.recurring_rules add column scope text not null default 'individual';
  alter table public.recurring_rules add column paid_by uuid references public.profiles;
  update public.recurring_rules set paid_by=created_by,scope=case when visibility='shared' then 'together' else 'individual' end,title=coalesce(merchant,note,'Recurring bill');
  alter table public.recurring_rules alter column paid_by set not null;
  alter table public.recurring_rules add column paid_from_common boolean not null default false;
  alter table public.recurring_rules add column is_contribution boolean not null default false;
  alter table public.recurring_rules add column split_pct smallint not null default 50 check(split_pct between 0 and 100);
  alter table public.recurring_rules add column end_date date;
  alter table public.recurring_rules add column active boolean not null default true;
  update public.recurring_rules rr set paid_from_common=(a.ownership='common') from public.accounts a where a.id=rr.account_id;
  alter table public.account_valuations rename column date to valued_on;
  alter table public.goal_contributions rename column occurred_on to contributed_on;
  alter table public.goal_accounts add column weight_pct smallint not null default 100;
  alter table public.goals add column months_coverage smallint;
  alter table public.goals alter column currency set default 'HUF';
  alter table public.goals alter column type set default 'savings';
  alter table public.budgets alter column valid_from set default current_date;
  alter table public.settlement_postings add column updated_at timestamptz not null default now();
  alter table public.activity rename column user_id to actor_id;
  alter table public.activity alter column title set default 'Shared activity';
  alter table public.activity add column entity_id uuid;
  alter table public.activity add column payload jsonb not null default '{}'::jsonb;
  update public.activity set payload=jsonb_build_object('summary_en',title,'summary_hu',coalesce(details,title));
  alter table public.settlements rename column status to legacy_status;
  alter table public.settlements alter column legacy_status drop not null;
  alter table public.settlements add column status text generated always as(case when rejected_by is not null then 'rejected' when from_confirmed and to_confirmed then 'confirmed' else 'pending' end) stored;
  for r in select table_name from information_schema.columns where table_schema='public' and column_name='id' and data_type='uuid' and table_name<>'profiles' loop
    execute format('alter table public.%I alter column id set default gen_random_uuid()',r.table_name);
  end loop;
  alter table public.accounts alter column currency set default 'HUF';
  create table if not exists public.app_releases(version_code integer primary key,version_name text not null,apk_path text not null,sha256 text not null,release_notes_en text,release_notes_hu text,created_at timestamptz not null default now());
  drop function if exists public.create_household(text,character,text,text);
  drop function if exists public.join_household(text,text,text);

  execute $touch$create or replace function touch_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

$touch$;
  execute $policies$-- Helper: current authenticated user's household_id
create or replace function my_household_id() returns uuid
language sql stable security definer
set search_path = public
as $$
  select household_id from profiles where id = auth.uid();
$$;

-- Trigger: enforce account ownership & compute/lock transaction visibility
create or replace function set_transaction_visibility() returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_acc_ownership text;
  v_acc_owner uuid;
  v_acc_household uuid;
  v_to_ownership text;
  v_computed_vis text;
  v_actor uuid := coalesce(auth.uid(), new.paid_by, new.created_by);
begin
  if tg_op = 'INSERT' or new.account_id is distinct from old.account_id then
    select ownership, owner_id, household_id
      into v_acc_ownership, v_acc_owner, v_acc_household
      from accounts
     where id = new.account_id and deleted_at is null;

    if v_acc_ownership is null or v_acc_household is distinct from new.household_id then
      raise exception 'Invalid source account';
    end if;

    if v_acc_ownership = 'personal' and v_acc_owner is distinct from v_actor then
      raise exception 'Cannot use partner personal account';
    end if;

    if v_acc_ownership = 'common' then
      new.paid_from_common := true;
    end if;
  end if;

  if new.to_account_id is not null then
    select ownership into v_to_ownership
      from accounts
     where id = new.to_account_id and household_id = new.household_id and deleted_at is null;
    if v_to_ownership = 'common' and not new.paid_from_common then
      new.is_contribution := true;
    end if;
  end if;

  -- Common-account expenses are always Together
  if new.kind = 'expense' and new.paid_from_common then
    new.scope := 'together';
  end if;

  -- Compute visibility strictly from content
  if new.kind = 'expense' then
    v_computed_vis := case when new.scope = 'together' then 'shared' else 'private' end;
  else
    v_computed_vis := case
      when new.paid_from_common or new.is_contribution or coalesce(v_to_ownership = 'common', false) then 'shared'
      else 'private'
    end;
    new.scope := case when v_computed_vis = 'shared' then 'together' else 'individual' end;
  end if;

  if tg_op = 'UPDATE' then
    if new.visibility is distinct from old.visibility or v_computed_vis is distinct from old.visibility then
      raise exception 'Transaction visibility is immutable; create a new row and soft-delete the old one';
    end if;
  end if;

  new.visibility := v_computed_vis;
  return new;
end;
$$;

create trigger trg_transactions_visibility
  before insert or update on transactions
  for each row execute function set_transaction_visibility();

-- Trigger: recurring_rules visibility and account ownership
create or replace function set_recurring_rule_visibility() returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_acc_ownership text;
  v_acc_owner uuid;
  v_to_ownership text;
  v_actor uuid := coalesce(auth.uid(), new.paid_by, new.created_by);
begin
  if tg_op = 'INSERT' or new.account_id is distinct from old.account_id then
    select ownership, owner_id into v_acc_ownership, v_acc_owner
      from accounts
     where id = new.account_id and household_id = new.household_id and deleted_at is null;
    if v_acc_ownership is null then
      raise exception 'Invalid account for recurring rule';
    end if;
    if v_acc_ownership = 'personal' and v_acc_owner is distinct from v_actor then
      raise exception 'Cannot use partner personal account in recurring rule';
    end if;
    if v_acc_ownership = 'common' then
      new.paid_from_common := true;
    end if;
  end if;

  if new.to_account_id is not null then
    select ownership into v_to_ownership
      from accounts
     where id = new.to_account_id and household_id = new.household_id and deleted_at is null;
    if v_to_ownership = 'common' and not new.paid_from_common then
      new.is_contribution := true;
    end if;
  end if;

  if new.kind = 'expense' and new.paid_from_common then
    new.scope := 'together';
  end if;

  if new.kind = 'expense' then
    new.visibility := case when new.scope = 'together' then 'shared' else 'private' end;
  else
    new.visibility := case
      when new.paid_from_common or new.is_contribution or coalesce(v_to_ownership = 'common', false) then 'shared'
      else 'private'
    end;
    new.scope := case when new.visibility = 'shared' then 'together' else 'individual' end;
  end if;

  return new;
end;
$$;

create trigger trg_recurring_rules_visibility
  before insert or update on recurring_rules
  for each row execute function set_recurring_rule_visibility();

-- Trigger: settlement confirmation protection
create or replace function check_settlement_confirmation() returns trigger
language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    if new.from_confirmed and auth.uid() is distinct from new.from_user then
      raise exception 'Only from_user can set from_confirmed';
    end if;
    if new.to_confirmed and auth.uid() is distinct from new.to_user then
      raise exception 'Only to_user can set to_confirmed';
    end if;
  elsif tg_op = 'UPDATE' then
    -- Stale offline updates cannot clear an already-confirmed flag
    if old.from_confirmed and not new.from_confirmed then
      new.from_confirmed := true;
    end if;
    if old.to_confirmed and not new.to_confirmed then
      new.to_confirmed := true;
    end if;

    if new.from_confirmed and not old.from_confirmed and auth.uid() is distinct from new.from_user then
      raise exception 'Only from_user can set from_confirmed';
    end if;
    if new.to_confirmed and not old.to_confirmed and auth.uid() is distinct from new.to_user then
      raise exception 'Only to_user can set to_confirmed';
    end if;
  end if;
  return new;
end;
$$;

create trigger trg_settlements_confirmation
  before insert or update on settlements
  for each row execute function check_settlement_confirmation();

-- Enable RLS on all 19 tables
alter table households enable row level security;
alter table profiles enable row level security;
alter table accounts enable row level security;
alter table categories enable row level security;
alter table tags enable row level security;
alter table recurring_rules enable row level security;
alter table transactions enable row level security;
alter table transaction_shares enable row level security;
alter table transaction_tags enable row level security;
alter table budgets enable row level security;
alter table settlements enable row level security;
alter table settlement_postings enable row level security;
alter table account_valuations enable row level security;
alter table goals enable row level security;
alter table goal_accounts enable row level security;
alter table goal_contributions enable row level security;
alter table activity enable row level security;
alter table fx_rates enable row level security;
alter table app_releases enable row level security;

-- 1. households
create policy households_select on households for select
  using (id = my_household_id());
create policy households_update on households for update
  using (id = my_household_id())
  with check (id = my_household_id());

-- 2. profiles
create policy profiles_select on profiles for select
  using (id = auth.uid() or (household_id is not null and household_id = my_household_id()));
create policy profiles_insert on profiles for insert
  with check (id = auth.uid());
create policy profiles_update on profiles for update
  using (id = auth.uid())
  with check (id = auth.uid());

-- 3. accounts (common = household, personal = owner only)
create policy accounts_select on accounts for select
  using (household_id = my_household_id() and (ownership = 'common' or owner_id = auth.uid()));
create policy accounts_write on accounts for all
  using (household_id = my_household_id() and (ownership = 'common' or owner_id = auth.uid()))
  with check (household_id = my_household_id() and (ownership = 'common' or owner_id = auth.uid()));

-- 4. categories (shared labels across household)
create policy categories_all on categories for all
  using (household_id = my_household_id())
  with check (household_id = my_household_id());

-- 5. tags (shared labels across household)
create policy tags_all on tags for all
  using (household_id = my_household_id())
  with check (household_id = my_household_id());

-- 6. recurring_rules (shared vs private to creator)
create policy recurring_rules_select on recurring_rules for select
  using (household_id = my_household_id() and (visibility = 'shared' or created_by = auth.uid()));
create policy recurring_rules_write on recurring_rules for all
  using (household_id = my_household_id() and (visibility = 'shared' or created_by = auth.uid()))
  with check (household_id = my_household_id() and (visibility = 'shared' or created_by = auth.uid()));

-- 7. transactions (shared vs private to creator)
create policy transactions_select on transactions for select
  using (household_id = my_household_id() and (visibility = 'shared' or created_by = auth.uid()));
create policy transactions_write on transactions for all
  using (household_id = my_household_id() and (visibility = 'shared' or created_by = auth.uid()))
  with check (household_id = my_household_id() and (visibility = 'shared' or created_by = auth.uid()));

-- 8. transaction_shares (inherits visibility from parent transaction via RLS)
create policy transaction_shares_select on transaction_shares for select
  using (exists (select 1 from transactions t where t.id = transaction_shares.transaction_id));
create policy transaction_shares_write on transaction_shares for all
  using (exists (select 1 from transactions t where t.id = transaction_shares.transaction_id))
  with check (exists (select 1 from transactions t where t.id = transaction_shares.transaction_id));

-- 9. transaction_tags (inherits visibility from parent transaction via RLS)
create policy transaction_tags_select on transaction_tags for select
  using (exists (select 1 from transactions t where t.id = transaction_tags.transaction_id));
create policy transaction_tags_write on transaction_tags for all
  using (exists (select 1 from transactions t where t.id = transaction_tags.transaction_id))
  with check (exists (select 1 from transactions t where t.id = transaction_tags.transaction_id));

-- 10. budgets (together = household, personal = owner only)
create policy budgets_select on budgets for select
  using (household_id = my_household_id() and (scope = 'together' or owner_id = auth.uid()));
create policy budgets_write on budgets for all
  using (household_id = my_household_id() and (scope = 'together' or owner_id = auth.uid()))
  with check (household_id = my_household_id() and (scope = 'together' or owner_id = auth.uid()));

-- 11. settlements (shared across household)
create policy settlements_all on settlements for all
  using (household_id = my_household_id())
  with check (household_id = my_household_id());

-- 12. settlement_postings (strictly private to user_id)
create policy settlement_postings_all on settlement_postings for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- 13. account_valuations (inherits visibility from parent account via RLS)
create policy account_valuations_select on account_valuations for select
  using (exists (select 1 from accounts a where a.id = account_valuations.account_id));
create policy account_valuations_write on account_valuations for all
  using (exists (select 1 from accounts a where a.id = account_valuations.account_id))
  with check (exists (select 1 from accounts a where a.id = account_valuations.account_id));

-- 14. goals (shared = household, personal = owner only)
create policy goals_select on goals for select
  using (household_id = my_household_id() and (scope = 'shared' or owner_id = auth.uid()));
create policy goals_write on goals for all
  using (household_id = my_household_id() and (scope = 'shared' or owner_id = auth.uid()))
  with check (household_id = my_household_id() and (scope = 'shared' or owner_id = auth.uid()));

-- 15. goal_accounts (requires visibility on both goal and account)
create policy goal_accounts_select on goal_accounts for select
  using (
    exists (select 1 from goals g where g.id = goal_accounts.goal_id)
    and exists (select 1 from accounts a where a.id = goal_accounts.account_id)
  );
create policy goal_accounts_write on goal_accounts for all
  using (
    exists (select 1 from goals g where g.id = goal_accounts.goal_id)
    and exists (select 1 from accounts a where a.id = goal_accounts.account_id)
  )
  with check (
    exists (select 1 from goals g where g.id = goal_accounts.goal_id)
    and exists (select 1 from accounts a where a.id = goal_accounts.account_id)
  );

-- 16. goal_contributions (inherits visibility from parent goal via RLS)
create policy goal_contributions_select on goal_contributions for select
  using (exists (select 1 from goals g where g.id = goal_contributions.goal_id));
create policy goal_contributions_write on goal_contributions for all
  using (exists (select 1 from goals g where g.id = goal_contributions.goal_id))
  with check (exists (select 1 from goals g where g.id = goal_contributions.goal_id));

-- 17. activity (shared events only for household)
create policy activity_all on activity for all
  using (household_id = my_household_id())
  with check (household_id = my_household_id());

-- 18. fx_rates (global read-only for authenticated users)
create policy fx_rates_select on fx_rates for select
  using (true);

-- 19. app_releases (global read-only for authenticated users)
create policy app_releases_select on app_releases for select
  using (true);
$policies$;
  execute $functions$-- 1. create_household: creates household, profile, default categories, and personal Cash account
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
  if v_uid is null then
    raise exception 'Authentication required';
  end if;

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
  if v_uid is null then
    raise exception 'Authentication required';
  end if;

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

-- 3. get_balance: returns net settle-up balance in base minor units owed to auth.uid()
--    (positive = partner owes me, negative = I owe partner).
--    Excludes common-account expenses and contributions; includes only confirmed settlements.
create or replace function get_balance() returns bigint
language sql stable security invoker
set search_path = public
as $$
  with me as (
    select auth.uid() as uid, my_household_id() as hh_id
  ),
  expense_deltas as (
    select
      coalesce(sum(
        case
          when t.paid_by = me.uid and ts.user_id <> me.uid then ts.share_base_minor
          when t.paid_by <> me.uid and ts.user_id = me.uid then -ts.share_base_minor
          else 0
        end
      ), 0)::bigint as delta
    from transactions t
    join transaction_shares ts on ts.transaction_id = t.id
    cross join me
    where t.household_id = me.hh_id
      and t.deleted_at is null
      and t.kind = 'expense'
      and t.scope = 'together'
      and not t.paid_from_common
      and not t.is_contribution
  ),
  settlement_deltas as (
    select
      coalesce(sum(
        case
          when s.from_user = me.uid then s.base_amount_minor
          when s.to_user = me.uid then -s.base_amount_minor
          else 0
        end
      ), 0)::bigint as delta
    from settlements s
    cross join me
    where s.household_id = me.hh_id
      and s.deleted_at is null
      and s.status = 'confirmed'
  )
  select (select delta from expense_deltas) + (select delta from settlement_deltas);
$$;

-- 4. monthly_totals: security invoker aggregate for 'together' | 'individual' | 'my_total'
create or replace function monthly_totals(
  p_year int,
  p_view text default 'together'
) returns table (
  month int,
  expense_base_minor bigint,
  income_base_minor bigint
)
language sql stable security invoker
set search_path = public
as $$
  with months as (
    select generate_series(1, 12) as m
  ),
  tx as (
    select
      extract(month from t.occurred_on)::int as m,
      t.kind,
      case
        when p_view = 'together' and t.scope = 'together' then t.base_amount_minor
        when p_view = 'individual' and t.scope = 'individual' and t.created_by = auth.uid() then t.base_amount_minor
        when p_view in ('my_total', 'myTotal') then
          case
            when t.kind = 'expense' then coalesce(
              (select ts.share_base_minor from transaction_shares ts where ts.transaction_id = t.id and ts.user_id = auth.uid()),
              case when t.scope = 'individual' and t.created_by = auth.uid() then t.base_amount_minor else 0 end
            )
            when t.kind = 'income' and t.created_by = auth.uid() then t.base_amount_minor
            else 0
          end
        else 0
      end as eff_base_minor
    from transactions t
    where t.household_id = my_household_id()
      and t.deleted_at is null
      and extract(year from t.occurred_on)::int = p_year
  )
  select
    months.m as month,
    coalesce(sum(case when tx.kind = 'expense' then tx.eff_base_minor else 0 end), 0)::bigint as expense_base_minor,
    coalesce(sum(case when tx.kind = 'income' then tx.eff_base_minor else 0 end), 0)::bigint as income_base_minor
  from months
  left join tx on tx.m = months.m
  group by months.m
  order by months.m;
$$;

-- 5. category_totals: security invoker aggregate per category in date range for a view
create or replace function category_totals(
  p_from date,
  p_to date,
  p_view text default 'together'
) returns table (
  category_id uuid,
  total_base_minor bigint
)
language sql stable security invoker
set search_path = public
as $$
  select
    t.category_id,
    coalesce(sum(
      case
        when p_view = 'together' and t.scope = 'together' then t.base_amount_minor
        when p_view = 'individual' and t.scope = 'individual' and t.created_by = auth.uid() then t.base_amount_minor
        when p_view in ('my_total', 'myTotal') then coalesce(
          (select ts.share_base_minor from transaction_shares ts where ts.transaction_id = t.id and ts.user_id = auth.uid()),
          case when t.scope = 'individual' and t.created_by = auth.uid() then t.base_amount_minor else 0 end
        )
        else 0
      end
    ), 0)::bigint as total_base_minor
  from transactions t
  where t.household_id = my_household_id()
    and t.deleted_at is null
    and t.kind = 'expense'
    and t.occurred_on between p_from and p_to
  group by t.category_id
  having coalesce(sum(
      case
        when p_view = 'together' and t.scope = 'together' then t.base_amount_minor
        when p_view = 'individual' and t.scope = 'individual' and t.created_by = auth.uid() then t.base_amount_minor
        when p_view in ('my_total', 'myTotal') then coalesce(
          (select ts.share_base_minor from transaction_shares ts where ts.transaction_id = t.id and ts.user_id = auth.uid()),
          case when t.scope = 'individual' and t.created_by = auth.uid() then t.base_amount_minor else 0 end
        )
        else 0
      end
    ), 0) > 0;
$$;

-- 6. generate_recurring: idempotent cron job using deterministic UUIDv5 ('duo-wallet:recurring:<rule_id>:<YYYY-MM-DD>')
create or replace function generate_recurring(p_as_of date default current_date) returns int
language plpgsql security definer
set search_path = public
as $$
declare
  r record;
  v_tx_id uuid;
  v_fx numeric(18,8);
  v_base_minor bigint;
  v_partner_id uuid;
  v_share_creator bigint;
  v_share_base_creator bigint;
  v_count int := 0;
begin
  for r in
    select *
      from recurring_rules
     where active
       and auto_create
       and deleted_at is null
       and next_due_date <= p_as_of
       and (end_date is null or next_due_date <= end_date)
  loop
    while r.next_due_date <= p_as_of and (r.end_date is null or r.next_due_date <= r.end_date) loop
      v_tx_id := uuid_generate_v5(
        uuid_ns_url(),
        'duo-wallet:recurring:' || r.id::text || ':' || to_char(r.next_due_date, 'YYYY-MM-DD')
      );

      if r.currency = 'HUF' then
        v_fx := 1;
      else
        select rate into v_fx
          from fx_rates
         where base = r.currency and quote = 'HUF' and rate_date <= r.next_due_date
         order by rate_date desc
         limit 1;
        v_fx := coalesce(v_fx, 1);
      end if;

      v_base_minor := round(r.amount_minor * v_fx)::bigint;

      insert into transactions (
        id, household_id, kind, scope, occurred_on,
        amount_minor, currency, fx_rate_to_base, fx_source, base_amount_minor,
        paid_by, paid_from_common, account_id, account_amount_minor,
        to_account_id, to_account_amount_minor, is_contribution,
        category_id, merchant, note, recurring_rule_id, created_by
      ) values (
        v_tx_id, r.household_id, r.kind, r.scope, r.next_due_date,
        r.amount_minor, r.currency, v_fx, 'ecb', v_base_minor,
        r.paid_by, r.paid_from_common, r.account_id, r.amount_minor,
        r.to_account_id, case when r.to_account_id is not null then r.amount_minor else null end, r.is_contribution,
        r.category_id, r.merchant, coalesce(r.note, r.title), r.id, r.created_by
      )
      on conflict (id) do nothing;

      if found and r.kind = 'expense' then
        v_count := v_count + 1;
        if r.scope = 'individual' and not r.paid_from_common then
          insert into transaction_shares (transaction_id, user_id, share_minor, share_base_minor)
          values (v_tx_id, r.created_by, r.amount_minor, v_base_minor)
          on conflict do nothing;
        else
          v_share_creator := round(r.amount_minor * (r.split_pct / 100.0))::bigint;
          v_share_base_creator := round(v_base_minor * (r.split_pct / 100.0))::bigint;

          insert into transaction_shares (transaction_id, user_id, share_minor, share_base_minor)
          values (v_tx_id, r.created_by, v_share_creator, v_share_base_creator)
          on conflict do nothing;

          select id into v_partner_id
            from profiles
           where household_id = r.household_id and id <> r.created_by
           limit 1;

          if v_partner_id is not null then
            insert into transaction_shares (transaction_id, user_id, share_minor, share_base_minor)
            values (v_tx_id, v_partner_id, r.amount_minor - v_share_creator, v_base_minor - v_share_base_creator)
            on conflict do nothing;
          end if;
        end if;
      elsif found then
        v_count := v_count + 1;
      end if;

      r.next_due_date := case r.frequency
        when 'daily'   then r.next_due_date + (r.interval_count || ' days')::interval
        when 'weekly'  then r.next_due_date + (r.interval_count || ' weeks')::interval
        when 'monthly' then r.next_due_date + (r.interval_count || ' months')::interval
        when 'yearly'  then r.next_due_date + (r.interval_count || ' years')::interval
      end;
    end loop;

    update recurring_rules
       set next_due_date = r.next_due_date
     where id = r.id;
  end loop;

  return v_count;
end;
$$;

-- 7. post_interest: posts automatic net interest (after interest_tax_pct) on savings/deposit accounts
create or replace function post_interest(p_as_of date default current_date) returns int
language plpgsql security definer
set search_path = public
as $$
declare
  a record;
  v_bal bigint;
  v_net_interest bigint;
  v_fx numeric(18,8);
  v_tx_id uuid;
  v_actor uuid;
  v_cat_id uuid;
  v_count int := 0;
begin
  for a in
    select *
      from accounts
     where auto_post_interest
       and deleted_at is null
       and not archived
       and coalesce(interest_rate_pct, 0) > 0
       and (maturity_date is null or p_as_of <= maturity_date)
  loop
    select a.opening_balance_minor
      + coalesce(sum(
          case
            when t.kind = 'income' and t.account_id = a.id then t.account_amount_minor
            when t.kind = 'expense' and t.account_id = a.id then -t.account_amount_minor
            when t.kind = 'transfer' and t.account_id = a.id then -t.account_amount_minor
            when t.kind = 'transfer' and t.to_account_id = a.id then coalesce(t.to_account_amount_minor, t.account_amount_minor)
            else 0
          end
        ), 0)::bigint
      into v_bal
      from transactions t
     where t.household_id = a.household_id
       and t.deleted_at is null
       and t.occurred_on <= p_as_of;

    if v_bal > 0 then
      v_net_interest := round(
        v_bal * (a.interest_rate_pct / 100.0 / 12.0) * (1.0 - coalesce(a.interest_tax_pct, 0) / 100.0)
      )::bigint;

      if v_net_interest > 0 then
        v_tx_id := uuid_generate_v5(
          uuid_ns_url(),
          'duo-wallet:interest:' || a.id::text || ':' || to_char(p_as_of, 'YYYY-MM')
        );

        v_actor := coalesce(
          a.owner_id,
          (select id from profiles where household_id = a.household_id order by id limit 1)
        );

        select id into v_cat_id
          from categories
         where household_id = a.household_id and system_key = 'interest' and deleted_at is null
         limit 1;

        if a.currency = 'HUF' then
          v_fx := 1;
        else
          select rate into v_fx
            from fx_rates
           where base = a.currency and quote = 'HUF' and rate_date <= p_as_of
           order by rate_date desc
           limit 1;
          v_fx := coalesce(v_fx, 1);
        end if;

        insert into transactions (
          id, household_id, kind, scope, occurred_on,
          amount_minor, currency, fx_rate_to_base, fx_source, base_amount_minor,
          paid_by, paid_from_common, account_id, account_amount_minor,
          category_id, note, created_by
        ) values (
          v_tx_id, a.household_id, 'income',
          case when a.ownership = 'common' then 'together' else 'individual' end,
          p_as_of,
          v_net_interest, a.currency, v_fx, 'ecb', round(v_net_interest * v_fx)::bigint,
          v_actor, (a.ownership = 'common'), a.id, v_net_interest,
          v_cat_id, 'Automatic interest', v_actor
        )
        on conflict (id) do nothing;

        if found then
          v_count := v_count + 1;
        end if;
      end if;
    end if;
  end loop;

  return v_count;
end;
$$;
$functions$;
  for r in select unnest(array['profiles','accounts','categories','tags','recurring_rules','transactions','budgets','settlements','settlement_postings','account_valuations','goals','goal_contributions']) as table_name loop
    execute format('create trigger duo_updated_at before update on public.%I for each row execute function public.touch_updated_at()',r.table_name);
  end loop;
  grant all on all tables in schema public to authenticated,service_role;
end;
$adopt$;

-- Public release downloads are incompatible with authenticated-only storage.
drop policy if exists "Public Access to Releases" on storage.objects;
update storage.buckets set public=false where id='releases';
