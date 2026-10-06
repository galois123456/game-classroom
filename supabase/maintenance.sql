-- Run manually once per day, or schedule with Supabase Cron.
-- Deletes only expired sessions and >1-day-old rate-limit buckets; no student/game data.
select public.gamehub_cleanup();
-- Optional, after enabling pg_cron in Supabase Database > Extensions:
-- select cron.schedule('gamehub-daily-cleanup','0 18 * * *','select public.gamehub_cleanup();');
-- 18:00 UTC = 03:00 Korea. Do not create the same job repeatedly.
