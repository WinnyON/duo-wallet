-- Initial ECB exchange rates for HUF, EUR, RON
insert into fx_rates (rate_date, base, quote, rate) values
  (current_date, 'HUF', 'HUF', 1.00000000),
  (current_date, 'EUR', 'EUR', 1.00000000),
  (current_date, 'RON', 'RON', 1.00000000),
  (current_date, 'EUR', 'HUF', 400.00000000),
  (current_date, 'HUF', 'EUR', 0.00250000),
  (current_date, 'EUR', 'RON', 4.97500000),
  (current_date, 'RON', 'EUR', 0.20100503),
  (current_date, 'RON', 'HUF', 80.40201005),
  (current_date, 'HUF', 'RON', 0.01243750)
on conflict (rate_date, base, quote) do update
  set rate = excluded.rate;

-- Ensure any existing households have the default EN/HU expense and income categories
insert into categories (household_id, kind, system_key, name_en, name_hu, icon, color, is_essential, sort_order)
select h.id, c.kind, c.system_key, c.name_en, c.name_hu, c.icon, c.color, c.is_essential, c.sort_order
from households h
cross join (
  values
    ('expense', 'groceries',     'Groceries',             'Élelmiszer',             'shopping_cart',  '#10B981', true,  1),
    ('expense', 'housing',       'Housing & Utilities',   'Lakhatás és rezsi',      'home',           '#3B82F6', true,  2),
    ('expense', 'dining',        'Dining & Coffee',       'Étterem és kávé',        'restaurant',     '#F59E0B', false, 3),
    ('expense', 'transport',     'Transport',             'Közlekedés',             'directions_car', '#6366F1', true,  4),
    ('expense', 'health',        'Health',                'Egészség',               'favorite',       '#EF4444', true,  5),
    ('expense', 'fun',           'Entertainment & Gifts', 'Szórakozás és ajándék',  'celebration',    '#EC4899', false, 6),
    ('expense', 'subscriptions', 'Subscriptions',         'Előfizetések',           'subscriptions',  '#8B5CF6', false, 7),
    ('income',  'salary',        'Salary',                'Fizetés',                'payments',       '#14B8A6', false, 8),
    ('income',  'freelance',     'Freelance & Bonus',     'Mellékállás és bónusz',  'work',           '#22C55E', false, 9),
    ('income',  'interest',      'Interest & Returns',    'Kamat és hozam',         'trending_up',    '#0EA5E9', false, 10)
) as c(kind, system_key, name_en, name_hu, icon, color, is_essential, sort_order)
where not exists (
  select 1 from categories existing
   where existing.household_id = h.id and existing.system_key = c.system_key
);
