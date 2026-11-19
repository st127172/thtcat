-- THTCat back office: members list, activity log and bans. Run once in SQL Editor (safe to run again).

create or replace function public.is_banned() returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and exists (select 1 from public.docs where path = 'bans/' || auth.uid()::text)
$$;

create or replace function public.can_read(p text) returns boolean
language sql stable as $$
  select split_part(p,'/',1) in ('sitters','config','profiles')
      or (split_part(p,'/',1) = 'bookings' and auth.uid() is not null)
      or p like 'data/users/' || coalesce(auth.uid()::text,'-') || '/%'
      or p = 'bans/' || coalesce(auth.uid()::text,'-')
      or public.is_admin()
$$;

create or replace function public.can_write(p text) returns boolean
language sql stable as $$
  select auth.uid() is not null and (
         public.is_admin()
      or (not public.is_banned() and (
             p like 'data/users/' || auth.uid()::text || '/%'
          or p = 'profiles/' || auth.uid()::text
          or p = 'members/' || auth.uid()::text
          or p = 'sitters/u-' || auth.uid()::text
          or p ~ '^sitters/[^/]+/reviews/[^/]+$'
          or p ~ '^activity/[^/]+$'
          or split_part(p,'/',1) = 'bookings')))
$$;

-- Activity entries can be added by users but only changed or deleted by an admin.
drop policy if exists docs_update on public.docs;
drop policy if exists docs_delete on public.docs;
create policy docs_update on public.docs for update
  using (public.can_write(path) and (split_part(path,'/',1) <> 'activity' or public.is_admin()))
  with check (public.can_write(path));
create policy docs_delete on public.docs for delete
  using (public.can_write(path) and (split_part(path,'/',1) <> 'activity' or public.is_admin()));

-- The user on an activity entry is always the person who wrote it.
create or replace function public.stamp_activity() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and not public.is_admin() then
    new.data := new.data || jsonb_build_object('uid', auth.uid()::text, 't', (extract(epoch from now())*1000)::bigint);
  end if;
  return new;
end $$;
drop trigger if exists stamp_activity on public.docs;
create trigger stamp_activity before insert on public.docs for each row
  when (new.path ~ '^activity/') execute function public.stamp_activity();

grant execute on function public.is_banned() to anon, authenticated;
