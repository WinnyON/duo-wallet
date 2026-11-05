-- Helper: current authenticated user's household_id
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
