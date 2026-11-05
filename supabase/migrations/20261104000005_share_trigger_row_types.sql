create or replace function public.check_transaction_shares() returns trigger
language plpgsql security definer set search_path = '' as $$
declare t public.transactions; tid uuid;
begin
  if tg_op='DELETE' then
    tid := (to_jsonb(old)->>'transaction_id')::uuid;
  else
    tid := coalesce((to_jsonb(new)->>'transaction_id')::uuid,(to_jsonb(new)->>'id')::uuid);
  end if;
  select * into t from public.transactions where id = tid;
  if t.id is null or t.deleted_at is not null or t.kind <> 'expense' then return null; end if;
  if exists(select 1 from public.transaction_shares s left join public.profiles p on p.id = s.user_id
    where s.transaction_id = tid and (p.household_id is distinct from t.household_id or (t.scope = 'individual' and s.user_id <> t.created_by))) then raise exception 'Invalid share participant'; end if;
  if (select coalesce(sum(share_minor),0) from public.transaction_shares where transaction_id = tid) <> t.amount_minor or
     (select coalesce(sum(share_base_minor),0) from public.transaction_shares where transaction_id = tid) <> t.base_amount_minor then raise exception 'Shares must equal transaction amount'; end if;
  return null;
end;
$$;

revoke all on function public.check_transaction_shares() from public,anon,authenticated;
