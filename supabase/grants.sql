-- Run once if the site says "permission denied for table docs".
-- New Supabase projects do not give the web roles access to new tables; row level security still decides which rows each user may see.
grant usage on schema public to anon, authenticated;
grant select on public.docs to anon;
grant select, insert, update, delete on public.docs to authenticated;
grant select on public.admins to authenticated;
grant execute on function public.doc_merge(text, jsonb) to authenticated;
grant execute on function public.is_admin(), public.can_read(text), public.can_write(text) to anon, authenticated;
