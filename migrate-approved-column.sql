-- Откат системы одобрения: удалить колонку approved из profiles.
-- Одобрение больше не используется: доступ к рецептам по владельческой RLS.
-- Выполните в Supabase Dashboard → SQL Editor → New query → Run.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='profiles' AND column_name='approved'
  ) THEN
    ALTER TABLE public.profiles DROP COLUMN approved;
    RAISE NOTICE 'dropped column approved';
  END IF;
END $$;