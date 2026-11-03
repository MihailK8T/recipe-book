-- Книга рецептов · Supabase (безопасная версия)
-- Выполните весь скрипт в Supabase Dashboard → SQL Editor → New query → Run.
-- ВАЖНО: однажды выполнив, НЕ отключайте RLS у этих таблиц — иначе данные станут
-- публичными. Управление правами только через политики в этом файле.

create extension if not exists pgcrypto;

-- ===== PROFILES (профиль, связанный с auth.users) =====
-- Регистрация входит в Supabase AUTH: пароль хранится сервером (захеширован),
-- и в базе его нет. Здесь — только имя/показные данные пользователя.
create table if not exists public.profiles (
  id         uuid primary key references auth.users (id) on delete cascade,
  name       text not null,
  email      text not null,
  approved   boolean default false,     -- одобрен ли админом (false = на модерации)
  created_at timestamptz default now()
);

-- ===== RECIPES =====
-- Вместо текстового owner храним owner_id = auth.uid(). Личные рецепты
-- видны и изменяемы только владельцу.
create table if not exists public.recipes (
  id          text primary key,
  owner_id    uuid references auth.users (id) on delete cascade,
  name        text not null,
  cat         text,
  servings    int default 2,
  time        int default 0,
  description text default '',
  ingredients text default '',
  steps       text default '',
  private     boolean default false,
  status      text,                    -- статус рецепта (Приготовлено / Найдено / свой)
  custom_fields text default '[]',     -- свои поля: [{"name":"Рекомендация","value":"..."}]
  photo       text,
  photo_name  text,
  photo_type  text,
  created_at  timestamptz default now(),
  updated_at  timestamptz default now()
);

create index if not exists recipes_owner_idx on public.recipes (owner_id);
create index if not exists recipes_public_idx on public.recipes (private);

-- ===== USER_PREFS (настройки оформления, привязаны к аккаунту) =====
create table if not exists public.user_prefs (
  account_id   uuid primary key references auth.users (id) on delete cascade,
  theme        text default 'light',
  accent       text default 't3',
  bg           text default 'bg',
  large_text   boolean default true,
  quick_items  text default '',
  updated_at   timestamptz default now()
);

-- ===== STAFF (роли для админ-панели) =====
-- Привязка к auth.users по email. Хранит роль: owner / admin / moderator.
create table if not exists public.staff (
  id         uuid primary key references auth.users (id) on delete cascade,
  email      text not null,
  role       text not null default 'moderator' check (role in ('owner','admin','moderator')),
  created_at timestamptz default now()
);

-- Вспомогательная функция: роль текущего (аутентифицированного) пользователя.
create or replace function public.my_role()
returns text language sql stable as $$
  select role from public.staff where id = auth.uid();
$$;

-- Можно ли текущему пользователю выполнять админ-действия (owner/admin).
create or replace function public.is_admin()
returns boolean language sql stable as $$
  select exists(select 1 from public.staff where id = auth.uid() and role in ('owner','admin'));
$$;

-- Функция-триггер: при создании пользователя в auth создаём профиль.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  -- Новый пользователь создаётся на модерации (approved=false), пока админ
  -- не одобрит. Владельцы/сотрудники (из staff) одобряются сразу через add-owner/скрипт.
  insert into public.profiles (id, name, email, approved)
  values (new.id, coalesce(new.raw_user_meta_data->>'name', split_part(new.email,'@',1)), new.email, false)
  on conflict (id) do nothing;
  insert into public.user_prefs (account_id)
  values (new.id)
  on conflict (account_id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- =========================================================
-- RLS: включено везде, доступ только через политики и auth.uid().
-- =========================================================
alter table public.profiles   enable row level security;
alter table public.recipes    enable row level security;
alter table public.user_prefs enable row level security;

-- PROFILES: пользователь видит и обновляет свой профиль;
-- админ (owner/admin) видит все профили и может менять approved.
drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own on public.profiles
  for select to authenticated
  using (auth.uid() = id or public.is_admin());
drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  for update to authenticated
  using (auth.uid() = id or public.is_admin())
  with check (
    (auth.uid() = id and approved = true)   -- юзер может править только себя (не меняя approved)
    or
    public.is_admin()                        -- админ может менять anything (в т.ч. approved)
  );

-- RECIPES:
--  * читать можно публичные (любой аутентифицированный) + свои (private) — ТОЛЬКО если одобрен,
--    иначе только просмотр публичных;
--  * создавать/менять/удалять свои — ТОЛЬКО если профиль одобрен (approved=true);
--  * админ может удалять любые рецепты (для модерации).
drop policy if exists recipes_select_public on public.recipes;
create policy recipes_select_public on public.recipes
  for select to authenticated
  using (
    private = false
    or (owner_id = auth.uid() and exists(select 1 from public.profiles p where p.id = auth.uid() and p.approved = true))
  );
drop policy if exists recipes_insert_own on public.recipes;
create policy recipes_insert_own on public.recipes
  for insert to authenticated
  with check (
    owner_id = auth.uid()
    and exists(select 1 from public.profiles p where p.id = auth.uid() and p.approved = true)
  );
drop policy if exists recipes_update_own on public.recipes;
create policy recipes_update_own on public.recipes
  for update to authenticated
  using (owner_id = auth.uid())
  with check (
    owner_id = auth.uid()
    and exists(select 1 from public.profiles p where p.id = auth.uid() and p.approved = true)
  );
drop policy if exists recipes_delete_own on public.recipes;
create policy recipes_delete_own on public.recipes
  for delete to authenticated
  using (owner_id = auth.uid());
-- Админ удаляет любой рецепт (модерация публикаций).
drop policy if exists recipes_delete_admin on public.recipes;
create policy recipes_delete_admin on public.recipes
  for delete to authenticated
  using (public.is_admin());

-- USER_PREFS: полный доступ только к своим настройкам.
drop policy if exists prefs_all_own on public.user_prefs;
create policy prefs_all_own on public.user_prefs
  for all to authenticated
  using (account_id = auth.uid()) with check (account_id = auth.uid());

-- STAFF: только админы видят/меняют список ролей; сотрудник видит свою строку.
alter table public.staff enable row level security;
drop policy if exists staff_select on public.staff;
create policy staff_select on public.staff
  for select to authenticated
  using (public.is_admin() or id = auth.uid());
drop policy if exists staff_admin_all on public.staff;
create policy staff_admin_all on public.staff
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- =========================================================
-- Гранты: анонимный ключ НЕ имеет доступа к данным.
-- Только аутентифицированные (через токен) и только по политикам.
-- =========================================================
revoke all on public.profiles from anon;
revoke all on public.user_prefs from anon;
revoke select, insert, update, delete on public.recipes from anon;
revoke all on public.staff from anon;
grant usage on schema public to anon, authenticated;
grant usage, select on all sequences in schema public to authenticated;
grant select, insert, update, delete on public.profiles   to authenticated;
grant select, insert, update, delete on public.recipes    to authenticated;
grant select, insert, update, delete on public.user_prefs to authenticated;
grant select, insert, update, delete on public.staff      to authenticated;
grant execute on function public.my_role() to authenticated;
grant execute on function public.is_admin() to authenticated;