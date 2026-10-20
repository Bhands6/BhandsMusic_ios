import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import NcmApiDefault from '@neteasecloudmusicapienhanced/api';

/**
 * 网易云接口客户端。
 *
 * 直接复用社区维护的 `@neteasecloudmusicapienhanced/api` ——
 * 网易的请求签名算法一直在变（xeapi），自己实现等于持续维护一个加密库，
 * 不如把这个变化吸收在依赖里，我们只负责超时、重试、缓存和鉴权。
 */

export const UPSTREAM_TIMEOUT_MS = Number(process.env.UPSTREAM_TIMEOUT_MS || 8000);

/** 通用超时包装：settle 后清理计时器，不留 pending timer。 */
export function withTimeout(promise, ms = UPSTREAM_TIMEOUT_MS, label = 'ncm') {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`${label} 超时 ${ms}ms`)), ms);
    promise.then(
      (v) => { clearTimeout(timer); resolve(v); },
      (e) => { clearTimeout(timer); reject(e); },
    );
  });
}

/** 值得重试的瞬时错误：上游断连 / 502 / 超时。 */
function isTransient(error) {
  const message = String(error?.message || error);
  if (/超时|timeout|ECONNRESET|ECONNREFUSED|ETIMEDOUT|socket hang up/i.test(message)) return true;
  if (error?.status === 502 || error?.status === 503) return true;
  return false;
}

const raw = NcmApiDefault;

/**
 * 调一次 + 瞬时失败重试一次（间隔 400ms）。
 * 这些都是幂等读接口，重试没有副作用。
 */
async function callWithRetry(name, query) {
  const fn = raw[name];
  if (typeof fn !== 'function') throw new Error(`未知接口 ${name}`);

  try {
    return await withTimeout(fn.call(raw, query), UPSTREAM_TIMEOUT_MS, name);
  } catch (error) {
    if (!isTransient(error)) throw error;
    await new Promise((r) => setTimeout(r, 400));
    return await withTimeout(fn.call(raw, query), UPSTREAM_TIMEOUT_MS, name);
  }
}

export function ncm(name, query = {}) {
  return callWithRetry(name, query);
}

/**
 * 网易新协议（xeapi）要求先注册公钥，后续 song/url 用它加密。
 * 依赖库只**读** `os.tmpdir()/xeapi_public_key`，从不写 ——
 * 用 HTTP 方式部署时这一步得由我们自己补，否则拿不到播放地址。
 */
const XEAPI_KEY_PATH = path.resolve(os.tmpdir(), 'xeapi_public_key');

export async function ensureXeapiKey() {
  try {
    if (fs.existsSync(XEAPI_KEY_PATH)) return true;
    const res = await withTimeout(raw.register_xeapikey({}), UPSTREAM_TIMEOUT_MS, 'xeapi注册');
    const sk = res?.body?.sk;
    if (!sk) return false;
    fs.writeFileSync(XEAPI_KEY_PATH, JSON.stringify(res.body), 'utf-8');
    return true;
  } catch (error) {
    // 失败不致命：搜索、歌词仍然可用，只是播放地址会缺
    console.warn('[ncm] xeapi 公钥注册失败，播放地址可能不可用:', error.message);
    return false;
  }
}
