-- These checks also protect the legacy hosted schema (whose original tables did
-- not contain every canonical money/identity constraint).
alter table public.transactions add constraint duo_transaction_amounts check(
  amount_minor>0 and base_amount_minor>0 and account_amount_minor>0 and
  amount_minor<=9007199254740991 and base_amount_minor<=9007199254740991 and account_amount_minor<=9007199254740991 and
  fx_rate_to_base>0 and fx_rate_to_base<1000000000000 and
  (to_account_amount_minor is null or (to_account_amount_minor>0 and to_account_amount_minor<=9007199254740991)));
alter table public.transaction_shares add constraint duo_nonnegative_shares check(share_minor>=0 and share_base_minor>=0);
alter table public.budgets add constraint duo_budget_amount check(amount_minor>0 and amount_minor<=9007199254740991);
alter table public.goals add constraint duo_goal_amount check(target_minor>=0 and target_minor<=9007199254740991 and saved_amount_minor<=9007199254740991);
alter table public.settlements add constraint duo_settlement_amount check(amount_minor>0 and base_amount_minor>0 and amount_minor<=9007199254740991 and base_amount_minor<=9007199254740991);

create or replace function public.set_recurring_rule_visibility() returns trigger
language plpgsql security definer set search_path = '' as $$
declare src public.accounts;dst public.accounts; computed text;actor uuid:=auth.uid();
begin
  select * into src from public.accounts where id=new.account_id and household_id=new.household_id and deleted_at is null;
  if src.id is null then raise exception 'Invalid account for recurring rule'; end if;
  if src.ownership='personal' and src.owner_id<>new.paid_by then raise exception 'Cannot use partner personal account in recurring rule'; end if;
  if actor is not null and src.ownership='personal' and src.owner_id<>actor and
    (tg_op='INSERT' or new.account_id is distinct from old.account_id) then raise exception 'Cannot use partner personal account in recurring rule'; end if;
  new.paid_from_common:=src.ownership='common';
  if new.to_account_id is not null then
    select * into dst from public.accounts where id=new.to_account_id and household_id=new.household_id and deleted_at is null;
    if dst.id is null or dst.id=src.id then raise exception 'Invalid destination'; end if;
  end if;
  new.is_contribution:=src.ownership='personal' and dst.ownership='common';
  if new.kind='expense' then
    if new.paid_from_common then new.scope:='together'; end if;
    computed:=case when new.scope='together' then 'shared' else 'private' end;
  else
    computed:=case when new.paid_from_common or dst.ownership='common' then 'shared' else 'private' end;
    new.scope:=case when computed='shared' then 'together' else 'individual' end;
  end if;
  if tg_op='UPDATE' and computed<>old.visibility then raise exception 'Rule visibility is immutable; create a new rule'; end if;
  new.visibility:=computed;
  return new;
end;
$$;
revoke all on function public.set_recurring_rule_visibility() from public,anon,authenticated;

drop policy goal_contributions_write on public.goal_contributions;
create policy goal_contributions_write on public.goal_contributions for all to authenticated
using(user_id=auth.uid() and exists(select 1 from public.goals g where g.id=goal_id))
with check(user_id=auth.uid() and exists(select 1 from public.goals g where g.id=goal_id));
drop policy transaction_tags_write on public.transaction_tags;
create policy transaction_tags_write on public.transaction_tags for all to authenticated
using(exists(select 1 from public.transactions t where t.id=transaction_id))
with check(exists(select 1 from public.transactions t join public.tags tag on tag.household_id=t.household_id where t.id=transaction_id and tag.id=tag_id));
