# THTCat

Verified one-family-at-a-time home cat sitting in Bangkok and Pathum Thani.
Final project for AST02.21 E-Business Development and Technology, Asian Institute of Technology.

Static website (`index.html`) on GitHub Pages, with Supabase for accounts (6-digit email codes), data, and live updates.
Payments are simulated; no real money moves.

## Files

| File | Purpose |
|---|---|
| `index.html` | The whole web app |
| `config.js` | Supabase project URL and anon key (both are safe to publish) |
| `supabase/schema.sql` | Tables, access rules, triggers and sample data. Run once in the Supabase SQL Editor |
| `supabase/make_admin.sql` | Makes your account the platform admin |

## Setup

1. Supabase: create a project, run `supabase/schema.sql` in SQL Editor.
2. Authentication > Emails > SMTP: use your Gmail (smtp.gmail.com, port 587, your Gmail address, a Gmail App Password).
3. Authentication > Emails > Templates: in **Magic link** and **Confirm signup**, show the code with `{{ .Token }}`.
4. Authentication > URL Configuration: set Site URL to the GitHub Pages address.
5. Put the project URL and anon key in `config.js`, push, and turn on GitHub Pages (Settings > Pages > Deploy from branch `main`, folder `/`).
6. Sign up on the site once, then run `supabase/make_admin.sql` with your email.

## Known limits

- Free Supabase projects pause after 7 days without activity; open the dashboard to resume.
- Booking records can be changed by any signed-in user; production needs server-side booking functions.
- Gmail SMTP sends from your own address and may land in Spam.
