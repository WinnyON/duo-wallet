-- Enable pg_cron & pg_net when available on Supabase
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
  end if;
  if exists (select 1 from pg_available_extensions where name = 'pg_net') then
    create extension if not exists pg_net;
  end if;
end;
$$;

-- Schedule daily recurring rules, monthly interest posting, and daily FX fetch
do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'cron') then
    perform cron.schedule(
      'duo-wallet-generate-recurring',
      '5 0 * * *',
      $job$select public.generate_recurring(current_date);$job$
    );

    perform cron.schedule(
      'duo-wallet-post-interest',
      '15 0 1 * *',
      $job$select public.post_interest(current_date);$job$
    );

    if exists (select 1 from pg_namespace where nspname = 'net') then
      perform cron.schedule(
        'duo-wallet-fetch-fx-rates',
        '30 15 * * 1-5',
        $job$
        select net.http_post(
          url := coalesce(current_setting('app.settings.supabase_url', true), 'http://localhost:54321') || '/functions/v1/fetch-fx-rates',
          headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || coalesce(current_setting('app.settings.service_role_key', true), '')
          ),
          body := '{}'::jsonb
        );
        $job$
      );
    end if;
  end if;
end;
$$;

-- Storage bucket for sideloaded APK releases and latest.json
do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'storage') then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values (
      'releases',
      'releases',
      false,
      104857600, -- 100 MB
      array['application/vnd.android.package-archive', 'application/json']
    )
    on conflict (id) do nothing;

    if not exists (
      select 1 from pg_policies
       where schemaname = 'storage' and tablename = 'objects' and policyname = 'releases_authenticated_read'
    ) then
      execute $pol$
        create policy releases_authenticated_read on storage.objects
          for select to authenticated
          using (bucket_id = 'releases' and public.my_household_id() is not null);
      $pol$;
    end if;
  end if;
end;
$$;
