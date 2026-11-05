-- Cron and Storage

create extension if not exists pg_cron;
-- Create Storage bucket for releases
insert into storage.buckets (id, name, public)
values ('releases', 'releases', true)
on conflict (id) do nothing;
create policy "Public Access to Releases" on storage.objects
for select using ( bucket_id = 'releases' );
-- (Only admins/service_role can upload releases);
