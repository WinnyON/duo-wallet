-- Functions for Duo Wallet

create or replace function generate_invite_code(len int default 6) returns text as $$
declare
  chars text := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  result text := '';
  i int;
begin
  for i in 1..len loop
    result := result || substr(chars, floor(random() * length(chars) + 1)::int, 1);
  end loop;
  return result;
end;
$$ language plpgsql;
create or replace function create_household(p_name text, p_currency char(3), p_display_name text, p_color text)
returns json
language plpgsql security definer
as $$
declare
  v_household_id uuid;
  v_invite_code text;
begin
  -- generate a unique invite code
  loop
    v_invite_code := generate_invite_code(6);
    begin
      insert into households (name, base_currency, invite_code)
      values (p_name, p_currency, v_invite_code)
      returning id into v_household_id;
      exit;
    exception when unique_violation then
      -- retry if code exists
    end;
  end loop;

  -- Create profile
  insert into profiles (id, household_id, display_name, color)
  values (auth.uid(), v_household_id, p_display_name, p_color);

  -- Create default personal cash account
  insert into accounts (id, household_id, name, type, ownership, owner_id, currency, opening_date)
  values (gen_random_uuid(), v_household_id, 'Cash', 'cash', 'personal', auth.uid(), p_currency, current_date);

  -- Insert default categories
  insert into categories (id, household_id, name, system_key, icon, color, kind, is_essential) values
    (gen_random_uuid(), v_household_id, 'Groceries', 'cat_groceries', 'shopping_cart', '#4CAF50', 'expense', true),
    (gen_random_uuid(), v_household_id, 'Rent', 'cat_rent', 'home', '#2196F3', 'expense', true),
    (gen_random_uuid(), v_household_id, 'Utilities', 'cat_utilities', 'bolt', '#FFC107', 'expense', true),
    (gen_random_uuid(), v_household_id, 'Dining', 'cat_dining', 'restaurant', '#FF5722', 'expense', false),
    (gen_random_uuid(), v_household_id, 'Transport', 'cat_transport', 'directions_car', '#9C27B0', 'expense', true),
    (gen_random_uuid(), v_household_id, 'Health', 'cat_health', 'medical_services', '#E91E63', 'expense', true),
    (gen_random_uuid(), v_household_id, 'Salary', 'cat_salary', 'payments', '#4CAF50', 'income', false);

  return json_build_object('household_id', v_household_id, 'invite_code', v_invite_code);
end;
$$;
create or replace function join_household(p_invite_code text, p_display_name text, p_color text)
returns json
language plpgsql security definer
as $$
declare
  v_household_id uuid;
  v_member_count int;
  v_currency char(3);
begin
  select id, base_currency into v_household_id, v_currency from households where invite_code = p_invite_code;
  if v_household_id is null then
    raise exception 'Invalid invite code';
  end if;

  select count(*) into v_member_count from profiles where household_id = v_household_id;
  if v_member_count >= 2 then
    raise exception 'Household is full';
  end if;

  insert into profiles (id, household_id, display_name, color)
  values (auth.uid(), v_household_id, p_display_name, p_color);

  -- Create default personal cash account
  insert into accounts (id, household_id, name, type, ownership, owner_id, currency, opening_date)
  values (gen_random_uuid(), v_household_id, 'Cash', 'cash', 'personal', auth.uid(), v_currency, current_date);

  return json_build_object('household_id', v_household_id);
end;
$$;
-- Additional aggregates and cron functions will be added as needed, but the core setup requires these two.;
