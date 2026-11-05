-- 1. create_household: creates household, profile, default categories, and personal Cash account
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
