-- THTCat database for Supabase. Paste the whole file into SQL Editor and press Run once.

-- 1. One table holds every record, addressed by a path such as 'sitters/s1' or 'bookings/BK123/messages/m1'.
create table if not exists public.docs (
  path text primary key,
  parent text not null,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
create index if not exists docs_parent_idx on public.docs(parent);
alter table public.docs replica identity full;

-- 2. Platform admins (add yourself after you sign up, see step 3 of the guide).
create table if not exists public.admins (uid uuid primary key references auth.users(id) on delete cascade);
alter table public.admins enable row level security;
drop policy if exists "read own admin row" on public.admins;
create policy "read own admin row" on public.admins for select using (uid = auth.uid());

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admins where uid = auth.uid())
$$;

-- 3. Who may read and write which paths.
create or replace function public.can_read(p text) returns boolean
language sql stable as $$
  select split_part(p,'/',1) in ('sitters','config','profiles')
      or (split_part(p,'/',1) = 'bookings' and auth.uid() is not null)
      or p like 'data/users/' || coalesce(auth.uid()::text,'-') || '/%'
      or public.is_admin()
$$;
create or replace function public.can_write(p text) returns boolean
language sql stable as $$
  select auth.uid() is not null and (
         p like 'data/users/' || auth.uid()::text || '/%'
      or p = 'profiles/' || auth.uid()::text
      or p = 'sitters/u-' || auth.uid()::text
      or p ~ '^sitters/[^/]+/reviews/[^/]+$'
      or split_part(p,'/',1) = 'bookings'
      or public.is_admin())
$$;

alter table public.docs enable row level security;
drop policy if exists docs_select on public.docs;
drop policy if exists docs_insert on public.docs;
drop policy if exists docs_update on public.docs;
drop policy if exists docs_delete on public.docs;
create policy docs_select on public.docs for select using (public.can_read(path));
create policy docs_insert on public.docs for insert with check (public.can_write(path));
create policy docs_update on public.docs for update using (public.can_write(path)) with check (public.can_write(path));
create policy docs_delete on public.docs for delete using (public.can_write(path));

-- 4. Shallow merge used by the app's "update".
create or replace function public.doc_merge(p text, d jsonb) returns void
language plpgsql security invoker set search_path = public as $$
begin
  update public.docs set data = data || d, updated_at = now() where path = p;
  if not found then raise exception 'document % not found', p using errcode = 'P0002'; end if;
end $$;

-- 5. Only an admin can make a sitter profile live; a new profile always starts as pending.
create or replace function public.guard_sitter() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.path ~ '^sitters/[^/]+$' and auth.uid() is not null and not public.is_admin() then
    if tg_op = 'INSERT' then
      new.data := jsonb_set(new.data, '{status}', '"pending"');
    elsif coalesce(new.data->>'status','') is distinct from coalesce(old.data->>'status','') then
      new.data := jsonb_set(new.data, '{status}', coalesce(old.data->'status','"pending"'));
    end if;
  end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists guard_sitter on public.docs;
create trigger guard_sitter before insert or update on public.docs for each row execute function public.guard_sitter();

-- 6. A new review updates the sitter's rating on the server.
create or replace function public.apply_review() returns trigger
language plpgsql security definer set search_path = public as $$
declare sid text := split_part(new.path,'/',2); s jsonb; n int; r numeric;
begin
  select data into s from public.docs where path = 'sitters/' || sid;
  if s is null then return new; end if;
  n := coalesce((s->>'reviews')::int,0) + 1;
  r := round(((coalesce((s->>'rating')::numeric,0) * (n-1)) + coalesce((new.data->>'stars')::numeric,5)) / n, 2);
  update public.docs set data = data || jsonb_build_object('reviews', n, 'rating', r, 'done', coalesce((s->>'done')::int,0)+1)
   where path = 'sitters/' || sid;
  return new;
end $$;
drop trigger if exists apply_review on public.docs;
create trigger apply_review after insert on public.docs for each row
  when (new.path ~ '^sitters/[^/]+/reviews/[^/]+$') execute function public.apply_review();

-- 7a. Let the website's roles use the table (rows are still filtered by the policies above).
grant usage on schema public to anon, authenticated;
grant select on public.docs to anon;
grant select, insert, update, delete on public.docs to authenticated;
grant select on public.admins to authenticated;
grant execute on function public.doc_merge(text, jsonb) to authenticated;
grant execute on function public.is_admin(), public.can_read(text), public.can_write(text) to anon, authenticated;

-- 7. Live updates for the app.
do $$ begin
  alter publication supabase_realtime add table public.docs;
exception when duplicate_object then null; end $$;

-- 8. Sample sitters and seasonal prices.
insert into public.docs (path, parent, data) values
  ('sitters/s1', 'sitters', '{"name": "Nattaya Phromsiri", "area": "Khlong Luang (near AIT)", "color": "#0e6b66", "rating": 4.96, "reviews": 128, "years": 4, "home": "Condo · 2 bedrooms · 9th floor", "zone": "Dedicated 16 m² cat room with netted window, cat tree and 2 litter stations", "own": "1 resident cat (calm, vaccinated)", "langs": "Thai, English", "hours": "08:00–21:00", "addons": ["groom", "med", "video", "litter"], "tags": ["Senior cats", "Medication", "English speaker"], "bio": "Former vet-clinic assistant. I work from home, so your cat is never alone for more than an hour. 6 minutes from the AIT main gate.", "resp": "within 10 min", "done": 212, "superhost": true, "demo": true, "status": "live", "paused": false, "blocked": [], "seed": 0, "createdAt": 0}'::jsonb),
  ('sitters/s2', 'sitters', '{"name": "Krit Wongsakul", "area": "Rangsit", "color": "#e5733a", "rating": 4.88, "reviews": 74, "years": 2, "home": "Townhouse · 3 floors", "zone": "Entire 2nd floor is a cat zone (24 m²) with catwalk shelves", "own": "No resident pets", "langs": "Thai", "hours": "09:00–22:00", "addons": ["groom", "video", "litter"], "tags": ["Kittens", "Active cats", "Big space"], "bio": "Software tester working remotely. Lots of play time, wand toys and catwalks. Great for young, energetic cats.", "resp": "within 30 min", "done": 96, "superhost": false, "demo": true, "status": "live", "paused": false, "blocked": [], "seed": 1, "createdAt": 0}'::jsonb),
  ('sitters/s3', 'sitters', '{"name": "Siriporn Chaiyo", "area": "Lat Phrao", "color": "#5c8fbf", "rating": 4.92, "reviews": 156, "years": 5, "home": "Detached house (indoor-only care)", "zone": "Sunroom 20 m², fully enclosed, air-conditioned", "own": "2 resident cats (chipped & vaccinated)", "langs": "Thai, English, Japanese", "hours": "07:00–20:00", "addons": ["groom", "med", "video", "litter"], "tags": ["Long-term stays", "Medication", "Japanese speaker"], "bio": "Retired nurse. I specialise in monthly stays and cats needing daily medication. Weekly weight log included.", "resp": "within 15 min", "done": 301, "superhost": true, "demo": true, "status": "live", "paused": false, "blocked": [], "seed": 2, "createdAt": 0}'::jsonb),
  ('sitters/s4', 'sitters', '{"name": "Thanawat Rattanakorn", "area": "Phaya Thai", "color": "#6b4a8f", "rating": 4.81, "reviews": 41, "years": 1, "home": "Condo · 1 bedroom + study", "zone": "Study room converted to cat room, 10 m²", "own": "No resident pets", "langs": "Thai, English", "hours": "10:00–23:00", "addons": ["video", "litter"], "tags": ["Shy cats", "Near BTS", "Night owl"], "bio": "Quiet home, perfect for shy or anxious cats who need a calm one-cat environment. 4 min walk to BTS Ari.", "resp": "within 1 hr", "done": 38, "superhost": false, "demo": true, "status": "live", "paused": false, "blocked": [], "seed": 3, "createdAt": 0}'::jsonb),
  ('sitters/s5', 'sitters', '{"name": "Pimchanok Lertsiri", "area": "Sathorn", "color": "#c23b4a", "rating": 4.97, "reviews": 203, "years": 6, "home": "Condo · 2 bedrooms · high floor", "zone": "Cat room 14 m² + supervised living-room time", "own": "1 resident cat (Ragdoll, 6 yrs)", "langs": "Thai, English", "hours": "08:00–22:00", "addons": ["groom", "med", "video", "litter"], "tags": ["Long-haired breeds", "Grooming", "Superhost"], "bio": "Professional groomer. Persian, Ragdoll and Maine Coon parents love the daily brushing and photo diary.", "resp": "within 5 min", "done": 388, "superhost": true, "demo": true, "status": "live", "paused": false, "blocked": [], "seed": 4, "createdAt": 0}'::jsonb),
  ('sitters/s6', 'sitters', '{"name": "Arthit Boonmee", "area": "Bang Na", "color": "#1f8a4c", "rating": 4.85, "reviews": 66, "years": 3, "home": "Townhouse · 2 floors", "zone": "Ground-floor cat zone 18 m² with window perches", "own": "No resident pets", "langs": "Thai", "hours": "08:00–20:00", "addons": ["groom", "litter"], "tags": ["Multi-cat families", "Weekly stays"], "bio": "Cat family of 3 or 4? No problem — one family at a time, all together, just like home.", "resp": "within 20 min", "done": 117, "superhost": false, "demo": true, "status": "live", "paused": false, "blocked": [], "seed": 5, "createdAt": 0}'::jsonb),
  ('sitters/s7', 'sitters', '{"name": "Malee Sutthiwong", "area": "On Nut", "color": "#d9a33b", "rating": 4.9, "reviews": 89, "years": 3, "home": "Condo · 1 bedroom", "zone": "Bedroom cat zone 12 m², blackout curtains for nap time", "own": "No resident pets", "langs": "Thai, English", "hours": "09:00–21:00", "addons": ["med", "video", "litter"], "tags": ["Diabetic cats", "Medication", "Near BTS"], "bio": "Pharmacy student. Experienced with insulin injections and special diets (vet documents required).", "resp": "within 15 min", "done": 102, "superhost": false, "demo": true, "status": "live", "paused": false, "blocked": [], "seed": 6, "createdAt": 0}'::jsonb),
  ('sitters/s8', 'sitters', '{"name": "Ekkachai Prasert", "area": "Nonthaburi", "color": "#4f8a6b", "rating": 4.79, "reviews": 33, "years": 1, "home": "Detached house", "zone": "Converted guest room 15 m² with screened balcony", "own": "No resident pets", "langs": "Thai", "hours": "08:00–19:00", "addons": ["groom", "video"], "tags": ["Budget-friendly", "New sitter"], "bio": "New on THTCat with all checks passed. First-time customers of mine get a free grooming session.", "resp": "within 1 hr", "done": 12, "superhost": false, "demo": true, "status": "live", "paused": false, "blocked": [], "seed": 7, "createdAt": 0}'::jsonb),
  ('config/pricing', 'config', '{"rules": [{"id": "r-high", "name": "High tourist season", "type": "season", "start": "2026-11-01", "end": "2027-02-28", "pct": 10, "recurring": true, "active": true}, {"id": "r-low", "name": "Rainy low season", "type": "season", "start": "2026-06-01", "end": "2026-09-30", "pct": -10, "recurring": true, "active": true}, {"id": "r-ny", "name": "New Year holidays", "type": "festival", "start": "2026-12-28", "end": "2027-01-03", "pct": 30, "recurring": true, "active": true}, {"id": "r-songkran", "name": "Songkran", "type": "festival", "start": "2027-04-11", "end": "2027-04-17", "pct": 30, "recurring": true, "active": true}, {"id": "r-cny27", "name": "Chinese New Year 2027", "type": "festival", "start": "2027-02-05", "end": "2027-02-09", "pct": 20, "recurring": false, "active": true}, {"id": "r-loy26", "name": "Loy Krathong 2026", "type": "festival", "start": "2026-11-23", "end": "2026-11-25", "pct": 15, "recurring": false, "active": true}]}'::jsonb)
on conflict (path) do nothing;
