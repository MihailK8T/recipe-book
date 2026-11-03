-- Добавление владельца (owner) «kot»
-- Выполните в Supabase Dashboard → SQL Editor → New query → Run.
--
-- Аккаунт: имя kot · email mr.mihail.kot@mail.ru · пароль rekonekt
--
-- При повторном запуске скрипт безопасен (idempotent): уже существующего
-- пользователя не дублирует, а роль owner в staff только обновит/вставит.

do $$
declare
  v_id uuid;
begin
  -- 1) Создаём пользователя в Supabase Auth, если ещё нет по этому email.
  select id into v_id from auth.users where email = 'mr.mihail.kot@mail.ru' limit 1;
  if v_id is null then
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at, confirmation_token, recovery_token
    )
    values (
      '00000000-0000-0000-0000-000000000000',
      gen_random_uuid(),
      'authenticated',
      'authenticated',
      'mr.mihail.kot@mail.ru',
      crypt('rekonekt', gen_salt('bf', 10)),
      now(),                                          -- email сразу подтверждён
      '{"provider":"email","providers":["email"]}',
      jsonb_build_object('name','kot'),
      now(), now(), '', ''
    );
  end if;

  -- 2) Берём id пользователя.
  select id into v_id from auth.users where email = 'mr.mihail.kot@mail.ru' limit 1;

  -- 3) Гарантируем профиль.
  insert into public.profiles (id, name, email)
  values (v_id, 'kot', 'mr.mihail.kot@mail.ru')
  on conflict (id) do update set name = excluded.name;

  -- 4) Добавляем роль owner в staff.
  insert into public.staff (id, email, role)
  values (v_id, 'mr.mihail.kot@mail.ru', 'owner')
  on conflict (id) do update set role = 'owner', email = excluded.email;

end $$;