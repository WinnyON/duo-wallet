begin;
create extension if not exists pgtap;
select plan(20);

-- Create 3 test auth users (Sam = user A, Anna = user B, Intruder = user C)
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', 'sam@example.com'),
  ('00000000-0000-0000-0000-000000000002', 'anna@example.com'),
  ('00000000-0000-0000-0000-000000000003', 'intruder@example.com')
on conflict (id) do nothing;

-- Authenticate as Sam (User A) and create household
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);

select lives_ok(
  $$select create_household('Sam & Anna', 'Sam', '#4F46E5')$$,
  '1. User A creates household with default categories and personal Cash account'
);

-- Authenticate as Anna (User B) and join household using invite code
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);

do $$
declare
  v_code text;
begin
  set local role postgres;
  select invite_code into v_code from households limit 1;
  set local role authenticated;
  perform join_household(v_code, 'Anna', '#EC4899');
end;
$$;

select is(
  (select count(*)::int from profiles where household_id = my_household_id()),
  2,
  '2. User B joins household successfully (2 members total)'
);

-- Authenticate as Intruder (User C) and attempt to join full 2-member household
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', true);

select throws_ok(
  $$
  select join_household(
    (select invite_code from households limit 1),
    'Intruder',
    '#EF4444'
  )
  $$,
  null,
  '3. 3rd member is rejected from joining a 2-person household'
);

-- Switch to User B (Anna) and create private data + shared data
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);

-- Common bank account created by Anna
insert into accounts (id, household_id, name, type, ownership, currency, opening_balance_minor, opening_date)
values (
  '00000000-0000-0000-0000-0000000000c0',
  my_household_id(),
  'Common Bank',
  'bank',
  'common',
  'HUF',
  50000000,
  current_date
);

-- Anna's private bank account + valuation
insert into accounts (id, household_id, name, type, ownership, owner_id, currency, opening_balance_minor, opening_date)
values (
  '00000000-0000-0000-0000-0000000000b1',
  my_household_id(),
  'Anna Secret Investment',
  'investment',
  'personal',
  '00000000-0000-0000-0000-000000000002',
  'HUF',
  100000000,
  current_date
);

insert into account_valuations (id, account_id, valued_on, value_minor)
values (
  '00000000-0000-0000-0000-0000000000b2',
  '00000000-0000-0000-0000-0000000000b1',
  current_date,
  120000000
);

-- Anna's private individual expense + share
insert into transactions (
  id, household_id, kind, scope, occurred_on,
  amount_minor, currency, fx_rate_to_base, base_amount_minor,
  paid_by, paid_from_common, account_id, account_amount_minor,
  merchant, note, created_by
) values (
  '00000000-0000-0000-0000-0000000000b3',
  my_household_id(),
  'expense',
  'individual',
  current_date,
  500000,
  'HUF',
  1,
  500000,
  '00000000-0000-0000-0000-000000000002',
  false,
  '00000000-0000-0000-0000-0000000000b1',
  500000,
  'Secret Gift Shop',
  'Surprise for Sam',
  '00000000-0000-0000-0000-000000000002'
);

insert into transaction_shares (transaction_id, user_id, share_minor, share_base_minor)
values (
  '00000000-0000-0000-0000-0000000000b3',
  '00000000-0000-0000-0000-000000000002',
  500000,
  500000
);

-- Anna's private budget and private goal
insert into budgets (id, household_id, scope, owner_id, amount_minor)
values (
  '00000000-0000-0000-0000-0000000000b4',
  my_household_id(),
  'personal',
  '00000000-0000-0000-0000-000000000002',
  15000000
);

insert into goals (id, household_id, name, type, scope, owner_id, target_minor)
values (
  '00000000-0000-0000-0000-0000000000b5',
  my_household_id(),
  'Anna Private Goal',
  'savings',
  'personal',
  '00000000-0000-0000-0000-000000000002',
  50000000
);

-- Shared Together expense paid by Anna from her personal account (10 000 Ft, 60% Sam / 40% Anna)
insert into transactions (
  id, household_id, kind, scope, occurred_on,
  amount_minor, currency, fx_rate_to_base, base_amount_minor,
  paid_by, paid_from_common, account_id, account_amount_minor,
  merchant, note, created_by
) values (
  '00000000-0000-0000-0000-0000000000b6',
  my_household_id(),
  'expense',
  'together',
  current_date,
  1000000,
  'HUF',
  1,
  1000000,
  '00000000-0000-0000-0000-000000000002',
  false,
  '00000000-0000-0000-0000-0000000000b1',
  1000000,
  'Lidl',
  'Shared groceries',
  '00000000-0000-0000-0000-000000000002'
);

insert into transaction_shares (transaction_id, user_id, share_minor, share_base_minor) values
  ('00000000-0000-0000-0000-0000000000b6', '00000000-0000-0000-0000-000000000001', 600000, 600000),
  ('00000000-0000-0000-0000-0000000000b6', '00000000-0000-0000-0000-000000000002', 400000, 400000);

-- Test: Common-account expense attempted with scope='individual' is forced to 'together' and 'shared'
insert into transactions (
  id, household_id, kind, scope, occurred_on,
  amount_minor, currency, fx_rate_to_base, base_amount_minor,
  paid_by, paid_from_common, account_id, account_amount_minor,
  merchant, created_by
) values (
  '00000000-0000-0000-0000-0000000000b7',
  my_household_id(),
  'expense',
  'individual',
  current_date,
  845000,
  'HUF',
  1,
  845000,
  '00000000-0000-0000-0000-000000000002',
  true,
  '00000000-0000-0000-0000-0000000000c0',
  845000,
  'MVM Next',
  '00000000-0000-0000-0000-000000000002'
);

insert into transaction_shares (transaction_id, user_id, share_minor, share_base_minor) values
  ('00000000-0000-0000-0000-0000000000b7', '00000000-0000-0000-0000-000000000001', 422500, 422500),
  ('00000000-0000-0000-0000-0000000000b7', '00000000-0000-0000-0000-000000000002', 422500, 422500);

select is(
  (select scope || ':' || visibility from transactions where id = '00000000-0000-0000-0000-0000000000b7'),
  'together:shared',
  '4. Expense paid from common account is forced to scope=together and visibility=shared'
);

-- Test: Visibility immutability trigger rejects changing visibility or scope in-place
select throws_ok(
  $$update transactions set scope = 'together' where id = '00000000-0000-0000-0000-0000000000b3'$$,
  'Transaction visibility is immutable; create a new row and soft-delete the old one',
  '5. Visibility trigger rejects in-place scope/visibility change on existing transaction'
);

-- Settlement proposed by Anna with Anna's private posting
insert into settlements (
  id, household_id, from_user, to_user,
  amount_minor, currency, base_amount_minor,
  from_confirmed, to_confirmed, created_by
) values (
  '00000000-0000-0000-0000-0000000000b8',
  my_household_id(),
  '00000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000002',
  200000,
  'HUF',
  200000,
  false,
  true,
  '00000000-0000-0000-0000-000000000002'
);

insert into settlement_postings (settlement_id, user_id, account_id, amount_minor)
values (
  '00000000-0000-0000-0000-0000000000b8',
  '00000000-0000-0000-0000-000000000002',
  '00000000-0000-0000-0000-0000000000b1',
  200000
);

-- Switch to User A (Sam) and verify strict RLS zero-row isolation on all of User B's private rows
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);

select is(
  (select count(*)::int from transactions where id = '00000000-0000-0000-0000-0000000000b3'),
  0,
  '6. User A sees 0 rows for User B private transaction'
);

select is(
  (select count(*)::int from transaction_shares where transaction_id = '00000000-0000-0000-0000-0000000000b3'),
  0,
  '7. User A sees 0 rows for User B private transaction_shares'
);

select is(
  (select count(*)::int from accounts where id = '00000000-0000-0000-0000-0000000000b1'),
  0,
  '8. User A sees 0 rows for User B personal account (even when referenced by a shared Together expense)'
);

select is(
  (select count(*)::int from account_valuations where id = '00000000-0000-0000-0000-0000000000b2'),
  0,
  '9. User A sees 0 rows for User B personal account_valuations'
);

select is(
  (select count(*)::int from budgets where id = '00000000-0000-0000-0000-0000000000b4'),
  0,
  '10. User A sees 0 rows for User B personal budget'
);

select is(
  (select count(*)::int from goals where id = '00000000-0000-0000-0000-0000000000b5'),
  0,
  '11. User A sees 0 rows for User B personal goal'
);

select is(
  (select count(*)::int from settlement_postings where settlement_id = '00000000-0000-0000-0000-0000000000b8'),
  0,
  '12. User A sees 0 rows for User B private settlement_postings'
);

select is(
  (select count(*)::int from transactions where id = '00000000-0000-0000-0000-0000000000b6'),
  1,
  '13. User A CAN see the shared Together expense paid by User B'
);

-- User A cannot spend from User B's personal account
select throws_ok(
  $$
  insert into transactions (
    household_id, kind, scope, occurred_on,
    amount_minor, currency, fx_rate_to_base, base_amount_minor,
    paid_by, paid_from_common, account_id, account_amount_minor, created_by
  ) values (
    my_household_id(), 'expense', 'together', current_date,
    100000, 'HUF', 1, 100000,
    '00000000-0000-0000-0000-000000000001', false,
    '00000000-0000-0000-0000-0000000000b1', 100000,
    '00000000-0000-0000-0000-000000000001'
  )
  $$,
  'Cannot use partner personal account',
  '14. User A is blocked from spending out of User B personal account'
);

-- RPCs run as security invoker and never leak User B's private expense into User A's individual view
select is(
  (select sum(expense_base_minor)::bigint from monthly_totals(extract(year from current_date)::int, 'individual')),
  0::bigint,
  '15. monthly_totals(individual) for User A returns 0 (excludes User B private expenses)'
);

-- Settle-up balance before confirmation:
-- Anna paid 10 000 Ft (Sam's share = 6 000 Ft = 600000 minor). Common-account expense (8 450 Ft) creates 0 debt.
-- Pending settlement (2 000 Ft) is not yet confirmed, so Sam's balance is -600000 minor.
select is(
  get_balance(),
  -600000::bigint,
  '16. get_balance() excludes common-account expenses and unconfirmed settlements'
);

-- User B cannot set User A's confirmation flag (from_confirmed)
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);

select throws_ok(
  $$update settlements set from_confirmed = true where id = '00000000-0000-0000-0000-0000000000b8'$$,
  'Only from_user can set from_confirmed',
  '17. User B cannot set User A (from_user) confirmation flag'
);

-- User A confirms the settlement, and attempts a stale offline payload with to_confirmed = false
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);

update settlements
   set from_confirmed = true,
       to_confirmed = false -- simulating stale offline state from User A's phone
 where id = '00000000-0000-0000-0000-0000000000b8';

select is(
  (select status from settlements where id = '00000000-0000-0000-0000-0000000000b8'),
  'confirmed',
  '18. Stale offline update cannot clear partner confirmation flag; settlement becomes confirmed'
);

select is(
  get_balance(),
  -400000::bigint,
  '19. Confirmed settlement adjusts get_balance() (-600000 + 200000 = -400000)'
);

-- Recurring rule deterministic UUIDv5 idempotency test
insert into recurring_rules (
  id, household_id, created_by, title, kind, scope,
  amount_minor, currency, paid_by, paid_from_common, account_id,
  frequency, next_due_date, auto_create
) values (
  '00000000-0000-0000-0000-0000000000b9',
  my_household_id(),
  '00000000-0000-0000-0000-000000000001',
  'Netflix',
  'expense',
  'together',
  449000,
  'HUF',
  '00000000-0000-0000-0000-000000000001',
  true,
  '00000000-0000-0000-0000-0000000000c0',
  'monthly',
  current_date,
  true
);

select is(
  generate_recurring(current_date) + generate_recurring(current_date),
  1,
  '20. generate_recurring() creates deterministic UUIDv5 transaction once and is idempotent on re-run'
);

select * from finish();
rollback;
