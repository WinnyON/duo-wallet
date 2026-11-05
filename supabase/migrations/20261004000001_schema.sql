-- Schema for Duo Wallet

create table households (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  base_currency char(3) not null default 'HUF',
  default_split_pct smallint not null default 50,
  invite_code text unique,
  emergency_fund_months smallint not null default 6,
  created_at timestamptz default now()
);
create table profiles (
  id uuid primary key references auth.users on delete cascade,
  household_id uuid references households,
  display_name text not null,
  color text not null,
  locale text default 'hu',
  monthly_common_contribution_minor bigint,
  updated_at timestamptz default now()
);
create table accounts (
  id uuid primary key,
  household_id uuid not null references households,
  name text not null,
  type text not null check (type in ('cash','bank','savings','investment','deposit')),
  ownership text not null check (ownership in ('common','personal')),
  owner_id uuid references profiles,
  currency char(3) not null check (currency in ('HUF','RON','EUR')),
  opening_balance_minor bigint not null default 0,
  opening_date date not null,
  interest_rate_pct numeric(6,3),
  compounding text check (compounding in ('daily','monthly','quarterly','yearly')),
  interest_tax_pct numeric(5,2) default 0,
  maturity_date date,
  auto_post_interest boolean default false,
  include_in_net_worth boolean default true,
  icon text, color text, archived boolean default false,
  updated_at timestamptz default now(), deleted_at timestamptz,
  check (ownership = 'common' or owner_id is not null)
);
create table categories (
  id uuid primary key,
  household_id uuid not null references households,
  parent_id uuid references categories,
  name text not null,
  system_key text,
  icon text not null,
  color text not null,
  kind text not null check (kind in ('expense','income')),
  is_essential boolean default false,
  sort_order int default 0,
  archived boolean default false,
  updated_at timestamptz default now(), deleted_at timestamptz
);
create table fx_rates (
  rate_date date, base char(3), quote char(3), rate numeric(18,8),
  primary key (rate_date, base, quote)
);
create table tags (
  id uuid primary key,
  household_id uuid not null references households,
  name text not null,
  color text not null,
  updated_at timestamptz default now(), deleted_at timestamptz
);
create table recurring_rules (
  id uuid primary key,
  household_id uuid not null references households,
  kind text not null check (kind in ('expense','income','transfer')),
  frequency text not null check (frequency in ('daily','weekly','monthly','yearly')),
  interval_amount smallint not null default 1,
  next_due date not null,
  auto_create boolean default false,
  is_subscription boolean default false,
  -- template fields
  amount_minor bigint not null,
  currency char(3) not null,
  account_id uuid not null,
  to_account_id uuid,
  category_id uuid references categories,
  merchant text, note text,
  created_by uuid not null references profiles,
  updated_at timestamptz default now(), deleted_at timestamptz
);
create table transactions (
  id uuid primary key,
  household_id uuid not null references households,
  kind text not null check (kind in ('expense','income','transfer')),
  scope text not null check (scope in ('individual','together')),
  visibility text not null check (visibility in ('private','shared')),
  occurred_on date not null,
  amount_minor bigint not null check (amount_minor > 0),
  currency char(3) not null,
  fx_rate_to_base numeric(18,8) not null,
  fx_source text default 'ecb',
  base_amount_minor bigint not null,
  paid_by uuid not null references profiles,
  paid_from_common boolean not null,
  account_id uuid not null,
  account_amount_minor bigint not null,
  to_account_id uuid,
  to_account_amount_minor bigint,
  is_contribution boolean default false,
  category_id uuid references categories,
  merchant text, note text,
  recurring_rule_id uuid references recurring_rules,
  created_by uuid not null references profiles,
  created_at timestamptz default now(),
  updated_at timestamptz default now(), deleted_at timestamptz
);
create table transaction_shares (
  transaction_id uuid references transactions on delete cascade,
  user_id uuid references profiles,
  share_minor bigint not null,
  share_base_minor bigint not null,
  primary key (transaction_id, user_id)
);
create table transaction_tags (
  transaction_id uuid references transactions on delete cascade,
  tag_id uuid references tags on delete cascade,
  primary key (transaction_id, tag_id)
);
create table settlements (
  id uuid primary key,
  household_id uuid not null references households,
  from_user uuid not null references profiles,
  to_user uuid not null references profiles,
  amount_minor bigint not null, currency char(3) not null,
  base_amount_minor bigint not null,
  from_confirmed boolean default false,
  to_confirmed boolean default false,
  status text generated always as (
    case when from_confirmed and to_confirmed then 'confirmed' else 'pending' end
  ) stored,
  rejected_by uuid references profiles,
  note text, created_by uuid not null references profiles,
  updated_at timestamptz default now(), deleted_at timestamptz
);
create table settlement_postings (
  settlement_id uuid references settlements on delete cascade,
  user_id uuid references profiles,
  account_id uuid not null,
  amount_minor bigint not null,
  primary key (settlement_id, user_id)
);
create table budgets (
  id uuid primary key,
  household_id uuid not null references households,
  scope text not null check (scope in ('personal','together')),
  user_id uuid references profiles,
  category_id uuid references categories,
  amount_minor bigint not null,
  rollover boolean default false,
  alert_thresholds smallint[] default '{50,80,100}',
  valid_from date not null, valid_to date,
  updated_at timestamptz default now(), deleted_at timestamptz,
  check (scope = 'together' or user_id is not null)
);
create table goals (
  id uuid primary key,
  household_id uuid not null references households,
  type text not null check (type in ('savings','emergency_fund')),
  scope text not null check (scope in ('personal','shared')),
  user_id uuid references profiles,
  name text not null,
  target_amount_minor bigint not null,
  currency char(3) not null,
  deadline date,
  icon text, color text,
  updated_at timestamptz default now(), deleted_at timestamptz,
  check (scope = 'shared' or user_id is not null)
);
create table goal_accounts (
  goal_id uuid references goals on delete cascade,
  account_id uuid references accounts on delete cascade,
  primary key (goal_id, account_id)
);
create table goal_contributions (
  id uuid primary key,
  goal_id uuid references goals on delete cascade,
  user_id uuid references profiles,
  amount_minor bigint not null,
  occurred_on date not null,
  note text,
  updated_at timestamptz default now(), deleted_at timestamptz
);
create table account_valuations (
  id uuid primary key,
  account_id uuid references accounts on delete cascade,
  date date not null,
  value_minor bigint not null,
  note text,
  updated_at timestamptz default now(), deleted_at timestamptz
);
create table activity (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households,
  user_id uuid references profiles,
  event_type text not null,
  title text not null,
  details text,
  created_at timestamptz default now()
);
-- Triggers for updated_at
create or replace function update_updated_at_column()
returns trigger as $$
begin
  NEW.updated_at = now();
  return NEW;
end;
$$ language plpgsql;
create trigger set_profiles_updated_at before update on profiles for each row execute procedure update_updated_at_column();
create trigger set_accounts_updated_at before update on accounts for each row execute procedure update_updated_at_column();
create trigger set_categories_updated_at before update on categories for each row execute procedure update_updated_at_column();
create trigger set_tags_updated_at before update on tags for each row execute procedure update_updated_at_column();
create trigger set_recurring_rules_updated_at before update on recurring_rules for each row execute procedure update_updated_at_column();
create trigger set_transactions_updated_at before update on transactions for each row execute procedure update_updated_at_column();
create trigger set_settlements_updated_at before update on settlements for each row execute procedure update_updated_at_column();
create trigger set_budgets_updated_at before update on budgets for each row execute procedure update_updated_at_column();
create trigger set_goals_updated_at before update on goals for each row execute procedure update_updated_at_column();
create trigger set_goal_contributions_updated_at before update on goal_contributions for each row execute procedure update_updated_at_column();
create trigger set_account_valuations_updated_at before update on account_valuations for each row execute procedure update_updated_at_column();
-- Indexes for performance
create index idx_transactions_household_date on transactions(household_id, occurred_on);
create index idx_activity_household_date on activity(household_id, created_at desc);
