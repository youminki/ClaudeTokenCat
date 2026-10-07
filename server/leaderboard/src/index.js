// TokenCat 미니게임 순위 서버 (Cloudflare Workers + D1).
//   POST   /v1/runs                 판 기록 올리기 → 내 순위
//   GET    /v1/leaderboard          순위표 (?period=all|week, ?limit). 내 줄은 X-Player 헤더로 찾는다.
//   PUT    /v1/players/:id          닉네임 바꾸기
//   DELETE /v1/players/:id          내 기록 지우기
// 매일 한 번(예약 작업) 주간 순위에 쓰지 않는 오래된 판과 제출 횟수 기록을 지운다.
import { checkRun, cleanNickname, isPlayerID, SUBMIT_INTERVAL_MS, SUBMITS_PER_MINUTE } from "./rules.js";

const WEEK_MS = 7 * 24 * 60 * 60 * 1000;
const MAX_BODY = 2048;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    try {
      if (request.method === "POST" && url.pathname === "/v1/runs") return await submitRun(request, env);
      if (request.method === "GET" && url.pathname === "/v1/leaderboard") return await leaderboard(request, url, env);
      const player = url.pathname.match(/^\/v1\/players\/([^/]+)$/)?.[1];
      if (player && request.method === "PUT") return await rename(player, request, env);
      if (player && request.method === "DELETE") return await forget(player, env);
      return json({ error: "not found" }, 404);
    } catch (error) {
      if (error instanceof TooLarge) return json({ error: "too large" }, 413);
      console.error(error);
      return json({ error: "server error" }, 500);
    }
  },

  async scheduled(_event, env) {
    const now = Date.now();
    await env.DB.batch([
      env.DB.prepare("DELETE FROM runs WHERE created_at < ?").bind(now - WEEK_MS - 24 * 60 * 60 * 1000),
      env.DB.prepare("DELETE FROM submit_hits WHERE minute < ?").bind(Math.floor(now / 60_000) - 60),
    ]);
  },
};

class TooLarge extends Error {}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}

/// 헤더를 믿지 않고 읽은 만큼 세어 MAX_BODY를 넘으면 끊는다.
async function readJSON(request) {
  if (!request.body) return null;
  const reader = request.body.getReader();
  const chunks = [];
  let size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > MAX_BODY) {
      await reader.cancel();
      throw new TooLarge();
    }
    chunks.push(value);
  }
  try {
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.byteLength;
    }
    return JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    return null;
  }
}

/// IP는 하루마다 바뀌는 소금과 함께 해시해 1분 단위 횟수만 센다. 원래 IP는 남기지 않는다.
async function overIPLimit(request, env, now) {
  const ip = request.headers.get("cf-connecting-ip") ?? "unknown";
  const day = Math.floor(now / 86_400_000);
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`${day}:${ip}`));
  const key = [...new Uint8Array(digest).slice(0, 12)].map((b) => b.toString(16).padStart(2, "0")).join("");
  const minute = Math.floor(now / 60_000);
  const row = await env.DB.prepare(
    `INSERT INTO submit_hits (key, minute, count) VALUES (?, ?, 1)
     ON CONFLICT(key, minute) DO UPDATE SET count = count + 1 RETURNING count`,
  ).bind(key, minute).first();
  return row.count > SUBMITS_PER_MINUTE;
}

async function submitRun(request, env) {
  const body = await readJSON(request);
  if (!body) return json({ error: "bad json" }, 400);
  const { player, score, coins, durationMs, rules, version } = body;
  if (!isPlayerID(player)) return json({ error: "bad player" }, 400);
  const nickname = cleanNickname(body.nickname);
  if (!nickname) return json({ error: "bad nickname" }, 400);
  const problem = checkRun({ score, coins, durationMs, rules });
  if (problem) return json({ error: problem }, 422);

  const now = Date.now();
  if (await overIPLimit(request, env, now)) return json({ error: "too fast" }, 429);

  // 3초 제한을 쓰기 조건으로 걸어, 동시에 온 요청도 하나만 통과한다
  const upsert = await env.DB.prepare(
    `INSERT INTO players (id, nickname, best, best_at, last_submit, created_at) VALUES (?1, ?2, ?3, ?4, ?4, ?4)
     ON CONFLICT(id) DO UPDATE SET nickname = ?2, last_submit = ?4,
       best_at = CASE WHEN ?3 > players.best THEN ?4 ELSE players.best_at END,
       best = MAX(players.best, ?3)
     WHERE ?4 - players.last_submit >= ?5`,
  ).bind(player, nickname, score, now, SUBMIT_INTERVAL_MS).run();
  if (upsert.meta.changes === 0) return json({ error: "too fast" }, 429);

  const appVersion = typeof version === "string" ? version.slice(0, 32) : null;
  await env.DB.prepare(
    "INSERT INTO runs (player_id, score, coins, duration_ms, app_version, created_at) VALUES (?, ?, ?, ?, ?, ?)",
  ).bind(player, score, coins, durationMs, appVersion, now).run();
  const { best } = await env.DB.prepare("SELECT best FROM players WHERE id = ?").bind(player).first();
  const row = await env.DB.prepare(
    "SELECT (SELECT COUNT(*) FROM players WHERE best > ?1) + 1 AS rank, (SELECT COUNT(*) FROM players WHERE best > 0) AS total",
  ).bind(best).first();
  return json({ best, rank: row.rank, total: row.total });
}

async function leaderboard(request, url, env) {
  const limit = Math.min(Math.max(Number.parseInt(url.searchParams.get("limit") ?? "20", 10) || 20, 1), 100);
  const week = url.searchParams.get("period") === "week";
  const player = request.headers.get("x-player");

  // 기간 안의 사람별 최고 점수. 이번 주는 최근 7일에 올린 판만 본다.
  const [board, params] = week
    ? [
        `SELECT p.id, p.nickname, MAX(r.score) AS score FROM runs r JOIN players p ON p.id = r.player_id
         WHERE r.created_at >= ? GROUP BY r.player_id`,
        [Date.now() - WEEK_MS],
      ]
    : ["SELECT id, nickname, best AS score FROM players WHERE best > 0", []];

  const { results } = await env.DB.prepare(`SELECT * FROM (${board}) ORDER BY score DESC, id LIMIT ?`)
    .bind(...params, limit).all();
  // 같은 점수는 같은 등수
  let rank = 0;
  let previous = null;
  const entries = results.map((row, index) => {
    if (row.score !== previous) {
      rank = index + 1;
      previous = row.score;
    }
    return { rank, nickname: row.nickname, score: row.score, you: row.id === player };
  });

  const { total } = await env.DB.prepare(`SELECT COUNT(*) AS total FROM (${board})`).bind(...params).first();
  let you = null;
  if (isPlayerID(player)) {
    const mine = await env.DB.prepare(`SELECT score FROM (${board}) WHERE id = ?`).bind(...params, player).first();
    if (mine) {
      const { above } = await env.DB.prepare(`SELECT COUNT(*) AS above FROM (${board}) WHERE score > ?`)
        .bind(...params, mine.score).first();
      you = { rank: above + 1, score: mine.score };
    }
  }
  return json({ period: week ? "week" : "all", total, entries, you });
}

async function rename(player, request, env) {
  if (!isPlayerID(player)) return json({ error: "bad player" }, 400);
  const nickname = cleanNickname((await readJSON(request))?.nickname);
  if (!nickname) return json({ error: "bad nickname" }, 400);
  await env.DB.prepare("UPDATE players SET nickname = ? WHERE id = ?").bind(nickname, player).run();
  return json({ nickname });
}

async function forget(player, env) {
  if (!isPlayerID(player)) return json({ error: "bad player" }, 400);
  await env.DB.batch([
    env.DB.prepare("DELETE FROM runs WHERE player_id = ?").bind(player),
    env.DB.prepare("DELETE FROM players WHERE id = ?").bind(player),
  ]);
  return json({ deleted: true });
}
