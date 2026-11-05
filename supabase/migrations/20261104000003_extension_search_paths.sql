-- Supabase installs uuid-ossp in extensions, not necessarily public.
alter function public.generate_recurring(date) set search_path = public,extensions;
alter function public.post_interest(date) set search_path = public,extensions;
revoke create on schema public from public,anon,authenticated;
