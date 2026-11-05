-- Pin remaining canonical/legacy helper search paths. Public is not writable by
-- clients; only the two deliberately privileged onboarding RPCs can add membership.
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in ('update_updated_at_column','validate_settlement_flags','set_recurring_visibility','generate_invite_code','validate_transaction_account','touch_updated_at') loop
    execute format('alter function %s set search_path = public,extensions', f.signature);
  end loop;
end;
$$;
