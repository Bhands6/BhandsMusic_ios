import 'dotenv/config';
import crypto from 'node:crypto';
import Fastify from 'fastify';
import { ensureXeapiKey, ncm } from './ncm.js';
import { TTLCache, TTL } from './cache.js';

const PORT = Number(process.env.PORT || 3000);
const HOST = process.env.HOST || '0.0.0.0';
const API_KEY = (process.env.API_KEY || '').trim();
const RATE_LIMIT = Number(process.env.RATE_LIMIT_PER_MIN || 120);

const app = Fastify({
  logger: {
    level: process.env.LOG_LEVEL || 'info',
    // 日志里不要出现 cookie 和完整查询串（可能带用户凭证）
    redact: ['req.headers.cookie', 'req.query.cookie', 'req.query.key'],
  },
  trustProxy: process.env.TRUST_PROXY === 'true',
});

const cache = new TTLCache(1000);

// MARK: - 鉴权与限流

/** 简单滑动窗口限流。单实例够用，多实例要靠网关。 */
const hits = new Map();

function rateLimited(ip) {
  const now = Date.now();
  const windowStart = now - 60_000;
  const list = (hits.get(ip) || []).filter((t) => t > windowStart);
  list.push(now);
  hits.set(ip, list);
  return list.length > RATE_LIMIT;
}

// 定期清理，避免 IP 表无限增长
setInterval(() => {
  const windowStart = Date.now() - 60_000;
  for (const [ip, list] of hits) {
    const kept = list.filter((t) => t > windowStart);
    if (kept.length === 0) hits.delete(ip);
    else hits.set(ip, kept);
  }
}, 60_000).unref();

/**
 * 所有业务路由的统一前置检查。
 * `/healthz` 不鉴权 —— 负载均衡和监控要能探活。
 */
function guard(request, reply, done) {
  if (rateLimited(request.ip)) {
    reply.code(429).send({ error: 'rate_limited', message: '请求过于频繁，稍后再试' });
    return;
  }

  if (API_KEY) {
    const provided = request.query.key || request.headers['x-api-key'];
    if (provided !== API_KEY) {
      reply.code(401).send({ error: 'unauthorized', message: '缺少或错误的 API key' });
      return;
    }
  }
  done();
}

// MARK: - 工具

/** 缓存键：公开接口不带 cookie，账号相关接口带。 */
function cacheKey(name, query, { withCookie = false } = {}) {
  const entries = Object.entries(query)
    .filter(([k]) => k !== 'key' && k !== 'cookie' && k !== 'timestamp')
    .sort(([a], [b]) => a.localeCompare(b));
  const base = `${name}?${entries.map(([k, v]) => `${k}=${v}`).join('&')}`;
  if (!withCookie) return base;
  const cookie = String(query.cookie || '');
  const digest = crypto.createHash('sha1').update(cookie).digest('hex').slice(0, 12);
  return `${base}|${digest}`;
}

/** 带缓存地调一次上游，返回上游 body。 */
async function cached(name, query, ttl, options) {
  const key = cacheKey(name, query, options);
  const hit = cache.get(key);
  if (hit) return { ...hit, cached: true };

  const res = await ncm(name, query);
  const body = res?.body ?? res;
  if (ttl > 0) cache.set(key, body, ttl);
  return { ...body, cached: false };
}

function upstreamError(reply, error) {
  // 网易的限流（code 405「操作频繁」）要如实暴露成 429，
  // 客户端才知道该退避重试，而不是当成普通故障
  const upstreamCode = error?.body?.code ?? error?.status;
  if (upstreamCode === 405) {
    app.log.warn({ err: error }, '上游限流');
    reply
      .header('retry-after', '30')
      .code(429)
      .send({ error: 'upstream_rate_limited', message: '网易云限流，请稍后重试' });
    return;
  }

  app.log.warn({ err: error }, '上游调用失败');
  reply.code(502).send({ error: 'upstream_failed', message: error.message });
}

// MARK: - 路由

app.get('/healthz', async () => ({
  ok: true,
  uptime: Math.round(process.uptime()),
  cacheEntries: cache.size,
  authRequired: Boolean(API_KEY),
}));

/** 搜索。`type=1` 是单曲。 */
app.get('/search', { preHandler: guard }, async (request, reply) => {
  const { keywords = '', limit = '20', type = '1' } = request.query;
  if (!String(keywords).trim()) {
    return reply.code(400).send({ error: 'bad_request', message: 'keywords 不能为空' });
  }
  try {
    return await cached('search', { keywords, limit, type }, TTL.search);
  } catch (error) {
    return upstreamError(reply, error);
  }
});

/** 播放地址。`level` 支持 standard / exhigh / lossless。 */
app.get('/song/url/v1', { preHandler: guard }, async (request, reply) => {
  const { id = '', level = 'exhigh' } = request.query;
  if (!id) return reply.code(400).send({ error: 'bad_request', message: 'id 不能为空' });
  try {
    // 地址带时效 token，且 VIP 状态影响可用性 —— 缓存要按 cookie 区分
    return await cached('song_url_v1', { id, level, cookie: request.query.cookie }, TTL.songURL, {
      withCookie: true,
    });
  } catch (error) {
    return upstreamError(reply, error);
  }
});

/** 批量曲目详情。`ids` 用逗号分隔。 */
app.get('/song/detail', { preHandler: guard }, async (request, reply) => {
  const { ids = '' } = request.query;
  if (!ids) return reply.code(400).send({ error: 'bad_request', message: 'ids 不能为空' });
  try {
    return await cached('song_detail', { ids }, TTL.detail);
  } catch (error) {
    return upstreamError(reply, error);
  }
});

/** 歌词（LRC）。 */
app.get('/lyric', { preHandler: guard }, async (request, reply) => {
  const { id = '' } = request.query;
  if (!id) return reply.code(400).send({ error: 'bad_request', message: 'id 不能为空' });
  try {
    return await cached('lyric', { id }, TTL.lyric);
  } catch (error) {
    return upstreamError(reply, error);
  }
});

/** 新歌速递。未登录时的「每日推荐」用它。 */
app.get('/personalized/newsong', { preHandler: guard }, async (request, reply) => {
  const { limit = '30' } = request.query;
  try {
    return await cached('personalized_newsong', { limit }, TTL.newsong);
  } catch (error) {
    return upstreamError(reply, error);
  }
});

/** 每日推荐。需要登录 cookie。 */
app.get('/recommend/songs', { preHandler: guard }, async (request, reply) => {
  try {
    return await cached('recommend_songs', { cookie: request.query.cookie }, TTL.recommend, {
      withCookie: true,
    });
  } catch (error) {
    return upstreamError(reply, error);
  }
});

/** 账号信息。 */
app.get('/user/account', { preHandler: guard }, async (request, reply) => {
  try {
    return await cached('user_account', { cookie: request.query.cookie }, TTL.account, {
      withCookie: true,
    });
  } catch (error) {
    return upstreamError(reply, error);
  }
});

// MARK: - 歌单

/** 用户的歌单列表。`uid` 必填；看自己的（含私密）要带 cookie。 */
app.get('/user/playlist', { preHandler: guard }, async (request, reply) => {
  const { uid = '', limit = '100' } = request.query;
  if (!uid) return reply.code(400).send({ error: 'bad_request', message: 'uid 不能为空' });
  try {
    return await cached('user_playlist', { uid, limit, cookie: request.query.cookie }, TTL.playlist, {
      withCookie: true,
    });
  } catch (error) {
    return upstreamError(reply, error);
  }
});

/** 歌单详情（封面、标题、曲目数）。 */
app.get('/playlist/detail', { preHandler: guard }, async (request, reply) => {
  const { id = '' } = request.query;
  if (!id) return reply.code(400).send({ error: 'bad_request', message: 'id 不能为空' });
  try {
    return await cached('playlist_detail', { id }, TTL.playlist);
  } catch (error) {
    return upstreamError(reply, error);
  }
});

/** 歌单全部曲目。分页由 limit/offset 控制。 */
app.get('/playlist/track/all', { preHandler: guard }, async (request, reply) => {
  const { id = '', limit = '100', offset = '0' } = request.query;
  if (!id) return reply.code(400).send({ error: 'bad_request', message: 'id 不能为空' });
  try {
    return await cached('playlist_track_all', { id, limit, offset }, TTL.playlist);
  } catch (error) {
    return upstreamError(reply, error);
  }
});

// MARK: - 扫码登录

app.get('/login/qr/key', { preHandler: guard }, async (request, reply) => {
  try {
    const res = await ncm('login_qr_key', { timestamp: Date.now() });
    return res?.body ?? res;
  } catch (error) {
    return upstreamError(reply, error);
  }
});

app.get('/login/qr/create', { preHandler: guard }, async (request, reply) => {
  const { key = '', qrimg = 'true' } = request.query;
  if (!key) return reply.code(400).send({ error: 'bad_request', message: 'key 不能为空' });
  try {
    const res = await ncm('login_qr_create', { key, qrimg });
    return res?.body ?? res;
  } catch (error) {
    return upstreamError(reply, error);
  }
});

/**
 * 轮询扫码状态：800 过期 / 801 等待 / 802 已扫待确认 / 803 成功。
 * 803 时把 cookie 一并返回 —— 上游有时放在 body 里，有时放在响应的 cookie 字段，
 * 两个都兜一下。
 */
app.get('/login/qr/check', { preHandler: guard }, async (request, reply) => {
  const { key = '' } = request.query;
  if (!key) return reply.code(400).send({ error: 'bad_request', message: 'key 不能为空' });
  try {
    const res = await ncm('login_qr_check', { key, timestamp: Date.now() });
    const body = res?.body ?? res;
    return { ...body, cookie: body?.cookie || res?.cookie || undefined };
  } catch (error) {
    return upstreamError(reply, error);
  }
});

// MARK: - 启动

const start = async () => {
  const ok = await ensureXeapiKey();
  app.log.info({ xeapiKey: ok }, '网易云公钥就绪');

  await app.listen({ port: PORT, host: HOST });
  app.log.info(
    { authRequired: Boolean(API_KEY), rateLimitPerMin: RATE_LIMIT },
    'BhandsMusic 后端已启动',
  );
};

// 容器里收到 SIGTERM 要优雅退出，别把在途请求砍断
for (const signal of ['SIGTERM', 'SIGINT']) {
  process.on(signal, async () => {
    app.log.info({ signal }, '正在关闭');
    await app.close();
    process.exit(0);
  });
}

start().catch((error) => {
  app.log.error(error, '启动失败');
  process.exit(1);
});
