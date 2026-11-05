-- Existing shared rows must reach UPDATE guards rather than INSERT actor guards.
-- Keep caller RLS and replace shares in the same transaction as the parent write.
create or replace function public.duo_save_transaction(p_transaction jsonb, p_shares jsonb, p_base_shares jsonb) returns void
language plpgsql security invoker set search_path = '' as $$
declare t public.transactions; existing public.transactions;
begin
  if auth.uid() is null or public.my_household_id() is null then raise exception 'Verified membership required'; end if;
  t := jsonb_populate_record(null::public.transactions,p_transaction);
  select * into existing from public.transactions where id=t.id for update;
  if found then
    if row(t.household_id,t.created_by,t.paid_by) is distinct from
       row(existing.household_id,existing.created_by,existing.paid_by) then
      raise exception 'Transaction identity is immutable';
    end if;
    update public.transactions set
      kind=t.kind,scope=t.scope,visibility=t.visibility,occurred_on=t.occurred_on,
      amount_minor=t.amount_minor,currency=t.currency,fx_rate_to_base=t.fx_rate_to_base,
      fx_source=t.fx_source,base_amount_minor=t.base_amount_minor,paid_by=t.paid_by,
      paid_from_common=t.paid_from_common,account_id=t.account_id,account_amount_minor=t.account_amount_minor,
      to_account_id=t.to_account_id,to_account_amount_minor=t.to_account_amount_minor,is_contribution=t.is_contribution,
      category_id=t.category_id,merchant=t.merchant,note=t.note,recurring_rule_id=t.recurring_rule_id,
      deleted_at=t.deleted_at,tags=t.tags
    where id=t.id;
    if not found then raise exception 'Transaction update denied'; end if;
  else
    insert into public.transactions select t.*;
  end if;
  delete from public.transaction_shares where transaction_id=t.id;
  insert into public.transaction_shares(transaction_id,user_id,share_minor,share_base_minor)
    select t.id,key::uuid,value::bigint,coalesce((p_base_shares->>key)::bigint,0) from jsonb_each_text(p_shares);
end;
$$;
revoke all on function public.duo_save_transaction(jsonb,jsonb,jsonb) from public,anon;
grant execute on function public.duo_save_transaction(jsonb,jsonb,jsonb) to authenticated;
