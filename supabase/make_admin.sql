-- Run AFTER you have signed up on the website once. Replace the email with yours.
insert into public.admins (uid)
select id from auth.users where email = 'YOUR_EMAIL@gmail.com'
on conflict do nothing;
