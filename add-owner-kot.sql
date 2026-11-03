-- Восстановление владельца (owner) «kot» — ИСПРАВЛЕННАЯ версия
-- Выполните в Supabase Dashboard → SQL Editor → New query → Run.
--
-- Аккаунт: имя kot · email mr.mihail.kot@mail.ru · пароль rekonekt
--
-- Зачем: прежний скрипт создавал пользователя без записей в auth.identities,
-- из-за чего GoTrue (вход/регистрация) возвращал «Database error finding user».
-- Этот скрипт удаляет такого сломанного пользователя и создаёт корректного
-- с provider identity (email), как это делает сама регистрация.

begin;

-- 1) Удаляем прежнего (возможно сломанного) пользователя kot, чтобы не конфликтовал.
delete from public.staff where email = 'mr.mihail.kot@mail.ru';
delete from public.user_prefs where account_id in
  (select id from auth.users where email = 'mr.mihail.kot@mail.ru');
delete from public.profiles where email = 'mr.mihail.kot@mail.ru';
delete from public.recipes where owner_id in
  (select id from auth.users where email = 'mr.mihail.kot@mail.ru');
delete from auth.identities where user_id in
  (select id from auth.users where email = 'mr.mihail.kot@mail.ru');
delete from auth.users where email = 'mr.mihail.kot@mail.ru';

-- 2) Создаём пользователя в auth корректно.
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, confirmation_sent_at, recovery_sent_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
values (
  '00000000-0000-0000-0000-000000000000',
  gen_random_uuid(),
  'authenticated', 'authenticated',
  'mr.mihail.kot@mail.ru',
  crypt('rekonekt', gen_salt('bf', 10)),
  now(), now(), now(),
  '{"provider":"email","providers":["email"]}',
  '{"name":"kot"}',
  now(), now(),
  '', '', '', ''
);

-- 3) Создаём identity (обязательно для работы GoTrue-входа).
insert into auth.identities (
  id, user_id, provider_id, identity_data, provider, last_sign_in_at,
  created_at, updated_at
)
select
  id, id, id,
  jsonb_build_object('sub', id::text, 'email', 'mr.mihail.kot@mail.ru'),
  'email', now(), now(), now()
from auth.users where email = 'mr.mihail.kot@mail.ru';

-- 4) Берём id и гарантируем профиль.
do $$
declare v_id uuid;
begin
  select id into v_id from auth.users where email = 'mr.mihail.kot@mail.ru';
  if v_id is not null then
    insert into public.profiles (id, name, email)
    values (v_id, 'kot', 'mr.mihail.kot@mail.ru')
    on conflict (id) do update set name = 'kot', email = excluded.email;
  end if;
end $$;

-- 5) Роль owner в staff.
insert into public.staff (id, email, role)
select id, 'mr.mihail.kot@mail.ru', 'owner'
from auth.users where email = 'mr.mihail.kot@mail.ru'
on conflict (id) do update set role = 'owner', email = excluded.email;

commit;