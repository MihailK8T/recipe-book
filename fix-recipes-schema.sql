-- =========================================================
-- Восстановление схемы таблицы recipes: добавление недостающих колонок
-- Выполнить в Supabase: SQL Editor -> New query -> Run (весь блок)
-- Колонки добавляются, только если их ещё нет (IF NOT EXISTS)
-- =========================================================

alter table public.recipes add column if not exists status text;
alter table public.recipes add column if not exists custom_fields text default '[]';
alter table public.recipes add column if not exists photo text;
alter table public.recipes add column if not exists photo_name text;
alter table public.recipes add column if not exists photo_type text;
alter table public.recipes add column if not exists created_at timestamptz default now();
alter table public.recipes add column if not exists updated_at timestamptz default now();
alter table public.recipes add column if not exists servings int default 2;
alter table public.recipes add column if not exists time int default 0;
alter table public.recipes add column if not exists description text default '';
alter table public.recipes add column if not exists ingredients text default '';
alter table public.recipes add column if not exists steps text default '';
alter table public.recipes add column if not exists private boolean default false;
alter table public.recipes add column if not exists cat text;

-- Перезагрузка кэша схемы PostgREST, чтобы столбцы подхватились
select pg_notify('pgrst', 'reload schema');

-- Проверка: какие колонки теперь есть в recipes
select column_name, data_type
from information_schema.columns
where table_schema='public' and table_name='recipes'
order by ordinal_position;