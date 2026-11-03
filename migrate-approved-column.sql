-- Миграция: добавить колонку approved в существующую таблицу profiles
-- Безопасно при повторном запуске (проверяет existence).
-- Выполните в Supabase Dashboard → SQL Editor → New query → Run.

DO $$
BEGIN
  -- Резервный вариант SQL-схемы: если таблицы profiles нет — создать.
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='profiles') THEN
    CREATE TABLE public.profiles (
      id         uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
      name       text NOT NULL,
      email      text NOT NULL,
      approved   boolean DEFAULT false,
      created_at timestamptz DEFAULT now()
    );
    RAISE NOTICE 'created profiles table';
  END IF;

  -- Добавить колонку approved, если её нет.
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='profiles' AND column_name='approved'
  ) THEN
    ALTER TABLE public.profiles ADD COLUMN approved boolean DEFAULT false;
    RAISE NOTICE 'added column approved';
  END IF;

  -- Включить RLS, если вдруг выключен.
  ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
END $$;