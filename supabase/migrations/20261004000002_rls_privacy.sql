-- RLS and Privacy Model for Duo Wallet

create or replace function my_household_id() returns uuid
language sql stable security definer as $$
  select household_id from profiles where id = auth.uid()
$$;
-- Household
alter table households enable row level security;
create policy "read household" on households for select using (id = my_household_id());
create policy "update household" on households for update using (id = my_household_id());
-- Profiles
alter table profiles enable row level security;
create policy "read profiles" on profiles for select using (household_id = my_household_id());
create policy "update own profile" on profiles for update using (id = auth.uid());
create policy "insert own profile" on profiles for insert with check (id = auth.uid());
-- FX Rates (global read)
alter table fx_rates enable row level security;
create policy "read fx_rates" on fx_rates for select using (true);
-- Categories & Tags
alter table categories enable row level security;
create policy "read categories" on categories for select using (household_id = my_household_id());
create policy "write categories" on categories for all using (household_id = my_household_id()) with check (household_id = my_household_id());
alter table tags enable row level security;
create policy "read tags" on tags for select using (household_id = my_household_id());
create policy "write tags" on tags for all using (household_id = my_household_id()) with check (household_id = my_household_id());
-- ACCOUNTS
alter table accounts enable row level security;
create policy "read accounts" on accounts for select using (
  household_id = my_household_id()
  and (ownership = 'common' or owner_id = auth.uid())
);
create policy "write accounts" on accounts for all using (
  household_id = my_household_id()
  and (ownership = 'common' or owner_id = auth.uid())
) with check (
  household_id = my_household_id()
  and (ownership = 'common' or owner_id = auth.uid())
);
-- TRANSACTIONS
-- Visibility Trigger
create or replace function set_transaction_visibility() returns trigger as $$
begin
  if NEW.paid_from_common = true then
    NEW.scope := 'together';
  end if;

  if NEW.kind = 'expense' then
    if NEW.scope = 'together' then
      NEW.visibility := 'shared';
    else
      NEW.visibility := 'private';
    end if;
  else
    -- income or transfer
    if NEW.paid_from_common = true or (NEW.to_account_id is not null and exists (select 1 from accounts where id = NEW.to_account_id and ownership = 'common')) then
      NEW.visibility := 'shared';
    else
      NEW.visibility := 'private';
    end if;
  end if;

  if TG_OP = 'UPDATE' and OLD.visibility != NEW.visibility then
    raise exception 'Cannot change visibility of a transaction. Soft delete and recreate instead.';
  end if;

  return NEW;
end;
$$ language plpgsql security definer;
create trigger trg_set_transaction_visibility
  before insert or update on transactions
  for each row execute procedure set_transaction_visibility();
-- Transactions RLS
alter table transactions enable row level security;
create policy "read transactions" on transactions for select using (
  household_id = my_household_id()
  and (visibility = 'shared' or created_by = auth.uid())
);
create policy "write transactions" on transactions for all using (
  household_id = my_household_id()
  and (visibility = 'shared' or created_by = auth.uid())
) with check (
  household_id = my_household_id()
  and (visibility = 'shared' or created_by = auth.uid())
);
-- Account Usage Validation Trigger
create or replace function validate_transaction_account() returns trigger as $$
declare
  acc_owner uuid;
  acc_own text;
begin
  select owner_id, ownership into acc_owner, acc_own from accounts where id = NEW.account_id;
  if acc_own = 'personal' and acc_owner != NEW.created_by then
    raise exception 'Cannot use partner personal account';
  end if;
  return NEW;
end;
$$ language plpgsql security definer;
create trigger trg_validate_transaction_account
  before insert or update on transactions
  for each row execute procedure validate_transaction_account();
-- Transaction Shares
alter table transaction_shares enable row level security;
create policy "read transaction shares" on transaction_shares for select using (
  exists (select 1 from transactions t where t.id = transaction_shares.transaction_id)
);
create policy "write transaction shares" on transaction_shares for all using (
  exists (select 1 from transactions t where t.id = transaction_shares.transaction_id)
) with check (
  exists (select 1 from transactions t where t.id = transaction_shares.transaction_id)
);
-- Transaction Tags
alter table transaction_tags enable row level security;
create policy "read transaction tags" on transaction_tags for select using (
  exists (select 1 from transactions t where t.id = transaction_tags.transaction_id)
);
create policy "write transaction tags" on transaction_tags for all using (
  exists (select 1 from transactions t where t.id = transaction_tags.transaction_id)
) with check (
  exists (select 1 from transactions t where t.id = transaction_tags.transaction_id)
);
-- SETTLEMENTS
alter table settlements enable row level security;
create policy "read settlements" on settlements for select using (household_id = my_household_id());
create policy "write settlements" on settlements for all using (household_id = my_household_id()) with check (household_id = my_household_id());
-- Settlement Validation Trigger
create or replace function validate_settlement_flags() returns trigger as $$
begin
  if TG_OP = 'UPDATE' then
    if OLD.from_confirmed = true and NEW.from_confirmed = false and auth.uid() != OLD.from_user then
       raise exception 'Cannot unconfirm partner flag';
    end if;
    if OLD.to_confirmed = true and NEW.to_confirmed = false and auth.uid() != OLD.to_user then
       raise exception 'Cannot unconfirm partner flag';
    end if;
    if NEW.from_confirmed != OLD.from_confirmed and auth.uid() != NEW.from_user then
       raise exception 'Cannot change partner confirm flag';
    end if;
    if NEW.to_confirmed != OLD.to_confirmed and auth.uid() != NEW.to_user then
       raise exception 'Cannot change partner confirm flag';
    end if;
  end if;
  return NEW;
end;
$$ language plpgsql security definer;
create trigger trg_validate_settlement_flags
  before update on settlements
  for each row execute procedure validate_settlement_flags();
-- Settlement Postings (Private)
alter table settlement_postings enable row level security;
create policy "read settlement postings" on settlement_postings for select using (user_id = auth.uid());
create policy "write settlement postings" on settlement_postings for all using (user_id = auth.uid()) with check (user_id = auth.uid());
-- BUDGETS
alter table budgets enable row level security;
create policy "read budgets" on budgets for select using (
  household_id = my_household_id()
  and (scope = 'together' or user_id = auth.uid())
);
create policy "write budgets" on budgets for all using (
  household_id = my_household_id()
  and (scope = 'together' or user_id = auth.uid())
) with check (
  household_id = my_household_id()
  and (scope = 'together' or user_id = auth.uid())
);
-- GOALS
alter table goals enable row level security;
create policy "read goals" on goals for select using (
  household_id = my_household_id()
  and (scope = 'shared' or user_id = auth.uid())
);
create policy "write goals" on goals for all using (
  household_id = my_household_id()
  and (scope = 'shared' or user_id = auth.uid())
) with check (
  household_id = my_household_id()
  and (scope = 'shared' or user_id = auth.uid())
);
-- Goal Accounts & Contributions (Inherit Visibility)
alter table goal_accounts enable row level security;
create policy "read goal accounts" on goal_accounts for select using (
  exists (select 1 from goals g where g.id = goal_accounts.goal_id)
);
create policy "write goal accounts" on goal_accounts for all using (
  exists (select 1 from goals g where g.id = goal_accounts.goal_id)
) with check (
  exists (select 1 from goals g where g.id = goal_accounts.goal_id)
);
alter table goal_contributions enable row level security;
create policy "read goal contributions" on goal_contributions for select using (
  exists (select 1 from goals g where g.id = goal_contributions.goal_id)
);
create policy "write goal contributions" on goal_contributions for all using (
  exists (select 1 from goals g where g.id = goal_contributions.goal_id)
) with check (
  exists (select 1 from goals g where g.id = goal_contributions.goal_id)
);
-- RECURRING RULES
alter table recurring_rules enable row level security;
-- Simplification: If the rule generates a shared transaction, it should be shared, else private.
-- We can just scope it like transactions, but for now we'll say if the account is common or it's a together rule.
-- We will add a 'visibility' field or just derive it, but let's derive it similarly.
-- Actually, let's just make recurring rules follow the same logic. Let's add a visibility column.
alter table recurring_rules add column visibility text not null default 'private' check (visibility in ('private','shared'));
create or replace function set_recurring_visibility() returns trigger as $$
begin
  -- For MVP: shared if account is common, or to_account is common.
  -- The app should probably explicitly set it based on what it generates, but we'll use this.
  if exists (select 1 from accounts where id = NEW.account_id and ownership = 'common') or
     (NEW.to_account_id is not null and exists (select 1 from accounts where id = NEW.to_account_id and ownership = 'common')) then
    NEW.visibility := 'shared';
  end if;
  return NEW;
end;
$$ language plpgsql security definer;
create trigger trg_set_recurring_visibility
  before insert or update on recurring_rules
  for each row execute procedure set_recurring_visibility();
create policy "read recurring" on recurring_rules for select using (
  household_id = my_household_id()
  and (visibility = 'shared' or created_by = auth.uid())
);
create policy "write recurring" on recurring_rules for all using (
  household_id = my_household_id()
  and (visibility = 'shared' or created_by = auth.uid())
) with check (
  household_id = my_household_id()
  and (visibility = 'shared' or created_by = auth.uid())
);
-- ACCOUNT VALUATIONS
alter table account_valuations enable row level security;
create policy "read valuations" on account_valuations for select using (
  exists (select 1 from accounts a where a.id = account_valuations.account_id)
);
create policy "write valuations" on account_valuations for all using (
  exists (select 1 from accounts a where a.id = account_valuations.account_id)
) with check (
  exists (select 1 from accounts a where a.id = account_valuations.account_id)
);
-- ACTIVITY (Shared only)
alter table activity enable row level security;
create policy "read activity" on activity for select using (household_id = my_household_id());
create policy "write activity" on activity for all using (household_id = my_household_id()) with check (household_id = my_household_id());
