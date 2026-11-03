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
  desc        text default '',
  ingredients text default '',
  steps       text default '',
  private     boolean default false,
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

-- Функция-триггер: при создании пользователя в auth создаём профиль.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (id, name, email)
  values (new.id, coalesce(new.raw_user_meta_data->>'name', split_part(new.email,'@',1)), new.email)
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

-- PROFILES: юзер видит только свой профиль, может обновлять свой.
drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own on public.profiles
  for select to authenticated using (auth.uid() = id);
drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);

-- RECIPES: читать можно публичные (любой аутентифицированный) + свои (все);
-- полный контроль (insert/update/delete) только над своими.
drop policy if exists recipes_select_public on public.recipes;
create policy recipes_select_public on public.recipes
  for select to authenticated
  using (private = false or owner_id = auth.uid());
drop policy if exists recipes_insert_own on public.recipes;
create policy recipes_insert_own on public.recipes
  for insert to authenticated
  with check (owner_id = auth.uid());
drop policy if exists recipes_update_own on public.recipes;
create policy recipes_update_own on public.recipes
  for update to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
drop policy if exists recipes_delete_own on public.recipes;
create policy recipes_delete_own on public.recipes
  for delete to authenticated
  using (owner_id = auth.uid());

-- USER_PREFS: полный доступ только к своим настройкам.
drop policy if exists prefs_all_own on public.user_prefs;
create policy prefs_all_own on public.user_prefs
  for all to authenticated
  using (account_id = auth.uid()) with check (account_id = auth.uid());

-- =========================================================
-- Гранты: анонимный ключ НЕ имеет доступа к данным.
-- Только аутентифицированные (через токен) и только по политикам.
-- =========================================================
revoke all on public.profiles from anon;
revoke all on public.user_prefs from anon;
revoke select, insert, update, delete on public.recipes from anon;
grant usage on schema public to anon, authenticated;
grant usage, select on all sequences in schema public to authenticated;
grant select, insert, update, delete on public.profiles   to authenticated;
grant select, insert, update, delete on public.recipes    to authenticated;
grant select, insert, update, delete on public.user_prefs to authenticated;