// Supabase Edge Function: admin_create_user
// Роль: администратор должен иметь возможность создать обычного пользователя
// (почта + пароль + имя) прямо из админ-панели. Создание аккаунта в Supabase
// Auth с произвольным паролем возможно только с правами service_role
// (серверный ключ), поэтому этот код выполняется как Edge-функция, а не в браузере.
//
// Безопасность: любой может дёрнуть URL, поэтому функция ПРОВЕРЯЕТ, что
// вызывающий аутентифицирован и имеет роль owner/admin в таблице public.staff.
// Пароль НЕ хранится в клиентском коде и НЕ логируется.
//
// Развёртывание (в корне Supabase-проекта, ref: xandcwnvmuyhmpzjylcy):
//   supabase functions new admin_create_user
//   # замените содержимое supabase/functions/admin_create_user/index.ts этим файлом
//   supabase secrets set SERVICE_ROLE_KEY=<ваш service_role ключ из Dashboard>
//   supabase functions deploy admin_create_user
//
// Публичный URL: https://xandcwnvmuyhmpzjylcy.supabase.co/functions/v1/admin_create_user
//
// Тело запроса (POST, JSON):
//   { "email": "user@mail.ru", "password": "secret", "name": "Имя" }

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method" }, 405);

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "";
  // service_role: суперключ, создаёт аккаунты в Auth. Задаётся через
  // `supabase secrets set SERVICE_ROLE_KEY=...` — в код не попадает.
  const SERVICE_ROLE_KEY = Deno.env.get("SERVICE_ROLE_KEY") || "";

  if (!SERVICE_ROLE_KEY) {
    return json({ error: "server", detail: "service role key not configured" }, 500);
  }

  let body: any;
  try { body = await req.json(); } catch { return json({ error: "body" }, 400); }

  const email = String(body.email || "").trim().toLowerCase();
  const password = String(body.password || "");
  const name = String(body.name || "").trim();

  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return json({ error: "email" }, 400);
  if (password.length < 6) return json({ error: "password", detail: "мин. 6 символов" }, 400);

  // --- Проверка вызывающего: должен быть админом (owner/admin) ---
  // Берём клиента от имени пользователя, передавшего Authorization-заголовок,
  // и спрашиваем его роль через защищённую RPC my_role() (security definer).
  const authHeader = req.headers.get("Authorization") || "";
  const userClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  let role = "";
  try {
    const { data } = await userClient.rpc("my_role");
    role = String((data as any) || "" || "").trim();
  } catch (e) {
    return json({ error: "unauthorized", detail: "не удалось определить роль" }, 401);
  }
  if (role !== "owner" && role !== "admin") {
    return json({ error: "forbidden", detail: "нужна роль owner/admin" }, 403);
  }

  // --- Создание пользователя в Auth с service_role ---
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: created, error } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true, // аккаунт сразу активен, не требует подтверждения письма
    user_metadata: { name },
  });

  if (error) {
    const msg = error.message || "create user";
    // Прозрачно сообщаем типовые причины (дубль почты и т.п.).
    return json({ error: "create", detail: msg }, 409);
  }

  // Профиль и user_prefs создаются триггером handle_new_user автоматически
  // (при insert в auth.users), так что отдельно создавать не нужно.
  return json({ ok: true, id: created?.user?.id, email });
});