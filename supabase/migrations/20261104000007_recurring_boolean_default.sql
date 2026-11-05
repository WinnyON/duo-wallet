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
  new.is_contribution:=src.ownership='personal' and coalesce(dst.ownership='common',false);
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
