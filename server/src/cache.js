/**
 * 极简 TTL 缓存。
 *
 * 为什么需要：搜索和歌词是重复率极高的只读请求，而网易上游有频率限制。
 * 缓存一层能把上游压力降一个量级，也能让 App 的重复搜索瞬间返回。
 *
 * 为什么不用 Redis：单机内存足够，且省掉一个部署依赖。
 * 要多实例时再换 —— 缓存本来就是"丢了也不影响正确性"的东西。
 */
export class TTLCache {
  #store = new Map();
  #max;

  constructor(max = 500) {
    this.#max = max;
  }

  get(key) {
    const hit = this.#store.get(key);
    if (!hit) return undefined;
    if (hit.expiresAt <= Date.now()) {
      this.#store.delete(key);
      return undefined;
    }
    // 简单 LRU：命中后挪到队尾
    this.#store.delete(key);
    this.#store.set(key, hit);
    return hit.value;
  }

  set(key, value, ttlMs) {
    if (ttlMs <= 0) return;
    // 超容量就淘汰最旧的一条（Map 保持插入顺序）
    if (this.#store.size >= this.#max) {
      const oldest = this.#store.keys().next().value;
      this.#store.delete(oldest);
    }
    this.#store.set(key, { value, expiresAt: Date.now() + ttlMs });
  }

  get size() {
    return this.#store.size;
  }
}

/** 各类接口的缓存时长。播放地址带时效 token，不能缓存太久。 */
export const TTL = {
  search: 5 * 60 * 1000,
  detail: 30 * 60 * 1000,
  lyric: 60 * 60 * 1000,
  songURL: 15 * 60 * 1000,
  newsong: 10 * 60 * 1000,
  recommend: 10 * 60 * 1000,
  account: 60 * 1000,
  playlist: 10 * 60 * 1000,
};
