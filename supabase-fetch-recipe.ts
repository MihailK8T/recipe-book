// Supabase Edge Function: fetch_recipe
// Роль: получать внешнюю страницу рецепта по ссылке, извлекать из неё
// название, фото, ингредиенты и шаги, возвращать в JSON.
//
// Развёртывание: в корне Supabase-проекта
//   supabase functions new fetch_recipe
//   * замените содержимое index.ts этим файлом *
//   supabase secrets set --env-file .env.local   (с UNSPLASH_API_KEY, опционально)
//   supabase functions deploy fetch_recipe
//
// Публичный URL: https://<ref>.supabase.co/functions/v1/fetch_recipe
// (ваш ref: xandcwnvmuyhmpzjylcy)

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

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

// Делает HTML читаемым: снимает теги скриптов/стилей, переводит абзацы.
function toText(html: string): string {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<br\s*\/?\s*>/gi, "\n")
    .replace(/<\/p>/gi, "\n\n")
    .replace(/<\/li>/gi, "\n")
    .replace(/<\/h[1-6]>/gi, "\n")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/\s+/g, " ")
    .trim();
}

// Пытается найти изображение рецепта: og:image, schema.org, первые <img>.
function pickImage(html: string, baseUrl: string): string {
  let m = html.match(/<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)/i);
  if (!m) m = html.match(/<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image["']/i);
  if (m) return absolute(m[1], baseUrl);
  m = html.match(/"image"\s*:\s*"([^"]+)"/i);
  if (m) return absolute(m[1], baseUrl);
  const imgs = [...html.matchAll(/<img[^>]+src=["']([^"']+?)["'][^>]*>/gi)];
  for (const im of imgs) {
    const u = absolute(im[1], baseUrl);
    if (u && !/logo|icon|avatar|banner|sprite/i.test(u)) return u;
  }
  return "";
}
function absolute(u: string, base: string): string {
  if (!u) return "";
  if (/^(https?:)?\/\//.test(u)) return /^https?:/.test(u) ? u : "https:" + u;
  try { return new URL(u, base).href; } catch { return ""; }
}

function pickTitle(html: string): string {
  let m = html.match(/<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)/i);
  if (!m) m = html.match(/<title[^>]*>([\s\S]*?)<\/title>/i);
  if (m) {
    let t = m[1].replace(/<[^>]+>/g, "").trim();
    t = t.split("—")[0].split("-")[0].split("|")[0].trim();
    if (t) return t;
  }
  m = html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i);
  return m ? m[1].replace(/<[^>]+>/g, "").trim() : "";
}

// Списки: пытаемся взять данные из schema.org (recipe JSON-LD) — это
// самый надёжный способ для кулинарных сайтов.
function extractSchema(html: string) {
  const blocks = [...html.matchAll(/<script[^>]+type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi)];
  for (const b of blocks) {
    try {
      const data = JSON.parse(b[1].trim());
      const items = Array.isArray(data) ? data : [data];
      for (const it of items) {
        const r = it["@graph"]?.find((x: any) => x["@type"] === "Recipe" || (Array.isArray(x["@type"]) && x["@type"].includes("Recipe"))) || (it["@type"] === "Recipe" ? it : it.recipe);
        if (!r) continue;
        const ing = Array.isArray(r.recipeIngredient) ? r.recipeIngredient : [];
        const steps = Array.isArray(r.recipeInstructions)
          ? r.recipeInstructions.map((s: any) => typeof s === "string" ? s : (s.text || s.name || "")).filter(Boolean)
          : [];
        const t = r.totalTime || r.cookTime || r.prepTime || "";
        let minutes = 0;
        const tm = /(\d+)\s*(?:мин|min)/i.exec(t);
        if (tm) minutes = +tm[1];
        else {
          const th = /(\d+)\s*(?:час|часa|ч|h)/i.exec(t);
          if (th) minutes = +th[1] * 60;
        }
        return {
          name: r.name || "",
          image: (Array.isArray(r.image) ? r.image[0] : r.image) || "",
          ingredients: ing.join("\n"),
          steps: steps.join("\n"),
          category: r.recipeCategory || "",
          description: r.description || "",
          time: minutes,
        };
      }
    } catch { /* невалидный JSON-LD — пропускаем */ }
  }
  return null;
}

// Надёжный способ для russianfood.com и подобных: парсим по маркерам.
function extractGeneric(html: string) {
  const text = toText(html);
  const ingKey = /(?:ingredients?|ингредиенты|продукты|состав)/i;
  const stepKey = /(?:instructions?|способ\s+приготовления|приготовление|как\s+приготовить|шаги)/i;
  // Разрезаем текст по ключевым секциям — наилучшее приближение.
  const is = text.search(ingKey);
  const ss = text.search(stepKey);
  let ingredients = "", steps = "";
  if (is >= 0 && ss > is) ingredients = text.slice(is, ss);
  if (ss >= 0) steps = text.slice(ss, ss + 2000);
  return { ingredients, steps };
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method" }, 405);

  let url = "";
  try { ({ url } = await req.json()); } catch { return json({ error: "body" }, 400); }
  if (!/^https?:\/\//.test(url || "")) return json({ error: "invalid url" }, 400);

  try {
    const res = await fetch(url, {
      headers: {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36",
        "Accept": "text/html,application/xhtml+xml",
        "Accept-Language": "ru,en;q=0.8",
      },
      redirect: "follow",
    });
    const html = await res.text();
    const baseUrl = res.url || url;

    let out: any = extractSchema(html) || {};
    if (!out.ingredients && !out.steps) {
      const g = extractGeneric(html);
      out.ingredients = out.ingredients || g.ingredients;
      out.steps = out.steps || g.steps;
    }
    out.name = out.name || pickTitle(html);
    out.image = out.image || pickImage(html, baseUrl);
    out.source_url = url;

    return json(out);
  } catch (e) {
    return json({ error: "fetch", detail: e && e.message }, 502);
  }
});