create extension if not exists "pgcrypto";
create extension if not exists "uuid-ossp";

create or replace function touch_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create table households (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  base_currency char(3) not null default 'HUF' check (base_currency in ('HUF','RON','EUR')),
  default_split_pct smallint not null default 50 check (default_split_pct between 0 and 100),
  invite_code text unique not null default upper(substr(encode(gen_random_bytes(4), 'hex'), 1, 8)),
  emergency_fund_months smallint not null default 6 check (emergency_fund_months > 0),
  created_at timestamptz not null default now()
);

create table profiles (
  id uuid primary key references auth.users on delete cascade,
  household_id uuid references households on delete set null,
  display_name text not null,
  color text not null,
  locale text not null default 'hu' check (locale in ('en','hu')),
  monthly_common_contribution_minor bigint check (monthly_common_contribution_minor is null or monthly_common_contribution_minor >= 0),
  updated_at timestamptz not null default now()
);

create table accounts (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households on delete cascade,
  name text not null,
  type text not null check (type in ('cash','bank','savings','investment','deposit')),
  ownership text not null check (ownership in ('common','personal')),
  owner_id uuid references profiles on delete cascade,
  currency char(3) not null default 'HUF' check (currency in ('HUF','RON','EUR')),
  opening_balance_minor bigint not null default 0,
  opening_date date not null default current_date,
  interest_rate_pct numeric(6,3),
  compounding text check (compounding in ('daily','monthly','quarterly','yearly')),
  interest_tax_pct numeric(5,2) not null default 0 check (interest_tax_pct between 0 and 100),
  maturity_date date,
  auto_post_interest boolean not null default false,
  include_in_net_worth boolean not null default true,
  icon text,
  color text,
  archived boolean not null default false,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (ownership = 'common' or owner_id is not null)
);

create table categories (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households on delete cascade,
  parent_id uuid references categories on delete set null,
  kind text not null check (kind in ('expense','income')),
  system_key text,
  name_en text not null,
  name_hu text not null,
  icon text not null,
  color text not null,
  is_essential boolean not null default false,
  sort_order smallint not null default 0,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table tags (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households on delete cascade,
  name text not null,
  color text,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (household_id, name)
);

create table recurring_rules (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households on delete cascade,
  created_by uuid not null references profiles on delete cascade,
  title text not null,
  kind text not null check (kind in ('expense','income','transfer')),
  scope text not null default 'individual' check (scope in ('individual','together')),
  visibility text not null default 'private' check (visibility in ('private','shared')),
  amount_minor bigint not null check (amount_minor > 0),
  currency char(3) not null default 'HUF' check (currency in ('HUF','RON','EUR')),
  paid_by uuid not null references profiles on delete cascade,
  paid_from_common boolean not null default false,
  account_id uuid not null,
  to_account_id uuid,
  is_contribution boolean not null default false,
  category_id uuid references categories on delete set null,
  merchant text,
  note text,
  split_pct smallint not null default 50 check (split_pct between 0 and 100),
  frequency text not null check (frequency in ('daily','weekly','monthly','yearly')),
  interval_count smallint not null default 1 check (interval_count > 0),
  next_due_date date not null,
  end_date date,
  auto_create boolean not null default true,
  is_subscription boolean not null default false,
  active boolean not null default true,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table transactions (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households on delete cascade,
  kind text not null check (kind in ('expense','income','transfer')),
  scope text not null check (scope in ('individual','together')),
  visibility text not null default 'private' check (visibility in ('private','shared')),
  occurred_on date not null,
  amount_minor bigint not null check (amount_minor > 0),
  currency char(3) not null check (currency in ('HUF','RON','EUR')),
  fx_rate_to_base numeric(18,8) not null default 1 check (fx_rate_to_base > 0),
  fx_source text not null default 'ecb' check (fx_source in ('ecb','cached','manual')),
  base_amount_minor bigint not null check (base_amount_minor > 0),
  paid_by uuid not null references profiles on delete cascade,
  paid_from_common boolean not null default false,
  account_id uuid not null, -- intentionally no FK to avoid leaking hidden personal accounts
  account_amount_minor bigint not null check (account_amount_minor > 0),
  to_account_id uuid,
  to_account_amount_minor bigint check (to_account_amount_minor is null or to_account_amount_minor > 0),
  is_contribution boolean not null default false,
  category_id uuid references categories on delete set null,
  merchant text,
  note text,
  recurring_rule_id uuid references recurring_rules on delete set null,
  created_by uuid not null references profiles on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table transaction_shares (
  transaction_id uuid not null references transactions on delete cascade,
  user_id uuid not null references profiles on delete cascade,
  share_minor bigint not null check (share_minor >= 0),
  share_base_minor bigint not null check (share_base_minor >= 0),
  primary key (transaction_id, user_id)
);

create table transaction_tags (
  transaction_id uuid not null references transactions on delete cascade,
  tag_id uuid not null references tags on delete cascade,
  primary key (transaction_id, tag_id)
);

create table budgets (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households on delete cascade,
  scope text not null check (scope in ('together','personal')),
  owner_id uuid references profiles on delete cascade,
  category_id uuid references categories on delete cascade, -- null = total monthly budget
  amount_minor bigint not null check (amount_minor > 0),
  currency char(3) not null default 'HUF' check (currency in ('HUF','RON','EUR')),
  rollover boolean not null default false,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (scope = 'together' or owner_id is not null)
);

create table settlements (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households on delete cascade,
  from_user uuid not null references profiles on delete cascade,
  to_user uuid not null references profiles on delete cascade,
  amount_minor bigint not null check (amount_minor > 0),
  currency char(3) not null default 'HUF' check (currency in ('HUF','RON','EUR')),
  base_amount_minor bigint not null check (base_amount_minor > 0),
  from_confirmed boolean not null default false,
  to_confirmed boolean not null default false,
  status text generated always as (
    case
      when rejected_by is not null then 'rejected'
      when from_confirmed and to_confirmed then 'confirmed'
      else 'pending'
    end
  ) stored,
  rejected_by uuid references profiles on delete set null,
  note text,
  created_by uuid not null references profiles on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (from_user <> to_user)
);

create table settlement_postings (
  settlement_id uuid not null references settlements on delete cascade,
  user_id uuid not null references profiles on delete cascade,
  account_id uuid not null,
  amount_minor bigint not null,
  updated_at timestamptz not null default now(),
  primary key (settlement_id, user_id)
);

create table account_valuations (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references accounts on delete cascade,
  valued_on date not null,
  value_minor bigint not null,
  note text,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (account_id, valued_on)
);

create table goals (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households on delete cascade,
  name text not null,
  type text not null default 'savings' check (type in ('savings','emergency_fund')),
  scope text not null check (scope in ('shared','personal')),
  owner_id uuid references profiles on delete cascade,
  target_minor bigint not null check (target_minor >= 0),
  currency char(3) not null default 'HUF' check (currency in ('HUF','RON','EUR')),
  deadline date,
  months_coverage smallint check (months_coverage is null or months_coverage > 0),
  icon text,
  color text,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (scope = 'shared' or owner_id is not null)
);

create table goal_accounts (
  goal_id uuid not null references goals on delete cascade,
  account_id uuid not null references accounts on delete cascade,
  weight_pct smallint not null default 100 check (weight_pct between 1 and 100),
  primary key (goal_id, account_id)
);

create table goal_contributions (
  id uuid primary key default gen_random_uuid(),
  goal_id uuid not null references goals on delete cascade,
  user_id uuid not null references profiles on delete cascade,
  amount_minor bigint not null,
  contributed_on date not null default current_date,
  note text,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table activity (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households on delete cascade,
  actor_id uuid not null references profiles on delete cascade,
  event_type text not null,
  entity_id uuid,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table fx_rates (
  rate_date date not null,
  base char(3) not null check (base in ('HUF','RON','EUR')),
  quote char(3) not null check (quote in ('HUF','RON','EUR')),
  rate numeric(18,8) not null check (rate > 0),
  primary key (rate_date, base, quote)
);

create table app_releases (
  version_code integer primary key,
  version_name text not null,
  apk_path text not null,
  sha256 text not null,
  release_notes_en text,
  release_notes_hu text,
  created_at timestamptz not null default now()
);

-- Indexes for sync and queries
create index idx_profiles_household on profiles (household_id);
create index idx_accounts_household_updated on accounts (household_id, updated_at);
create index idx_categories_household_updated on categories (household_id, updated_at);
create index idx_tags_household_updated on tags (household_id, updated_at);
create index idx_transactions_household_occurred on transactions (household_id, occurred_on desc);
create index idx_transactions_household_updated on transactions (household_id, updated_at);
create index idx_transaction_shares_user on transaction_shares (user_id);
create index idx_budgets_household_updated on budgets (household_id, updated_at);
create index idx_recurring_household_due on recurring_rules (household_id, next_due_date) where active and deleted_at is null;
create index idx_settlements_household_updated on settlements (household_id, updated_at);
create index idx_goals_household_updated on goals (household_id, updated_at);
create index idx_activity_household_created on activity (household_id, created_at desc);

-- Auto-update updated_at triggers
do $$
declare
  t text;
begin
  foreach t in array array[
    'profiles','accounts','categories','tags','recurring_rules','transactions',
    'budgets','settlements','settlement_postings','account_valuations','goals','goal_contributions'
  ] loop
    execute format(
      'create trigger trg_%I_updated_at before update on %I for each row execute function touch_updated_at()',
      t, t
    );
  end loop;
end;
$$;
