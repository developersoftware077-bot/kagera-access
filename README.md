# Kagera Access

Market-research MVP for phone accessories in Kagera, Tanzania.

## Start

1. Copy `.env.example` to `.env` and put your Supabase Project URL and **Publishable/anon key** in it.
2. Run every command in `supabase/schema.sql` in Supabase **SQL Editor**.
3. Run `supabase/catalogue_migration.sql` once in the same existing project. It is additive and idempotent: it adds only the catalogue capability, activates the seeded catalogue, and does not delete data.
4. In Supabase Authentication, create the researcher account using the requested email and password.
5. Run `npm install`, then `npm run dev`.

The UI intentionally shows a clear configuration message until Supabase values are supplied. The `sb_secret_...` key must never enter the browser or `.env` file. The public questionnaire is bearer-link based: anyone holding a valid active link can submit one or more responses; do not distribute links broadly.
