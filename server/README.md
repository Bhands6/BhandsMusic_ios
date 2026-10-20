# BhandsMusic 后端

网易云接口代理。**路径和 [NeteaseCloudMusicApi](https://github.com/88lin/api-enhanced) 保持一致** ——
App 只要改 `baseURL` 就能切过来，客户端代码不用动。

## 它解决什么

自己实现网易的请求签名不现实（xeapi 协议一直在变，改一次客户端就得发版）。
这个服务把变化吸收在服务端，同时补上三件自建服务必须有的事：

| | |
|---|---|
| **鉴权** | 设了 `API_KEY` 就必须带 `?key=`，否则 401 |
| **限流** | 单 IP 每分钟上限，超了 429 |
| **缓存** | 搜索 5 分钟、歌词 1 小时、播放地址 15 分钟（带时效 token，不能久存） |

服务是**无状态**的 —— 登录 cookie 由客户端每次带上来，服务端不存会话，
所以可以直接多实例横向扩展。

## 本地跑

```bash
cd server
cp .env.example .env        # 按需改 API_KEY
npm install
npm start                   # http://localhost:3000
```

首次启动会自动注册网易的 xeapi 公钥（不注册的话 `/song/url/v1` 拿不到播放地址）。

验证：

```bash
curl localhost:3000/healthz
curl "localhost:3000/search?keywords=民谣&limit=3"
```

## 接口

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/healthz` | 探活，**不需要鉴权** |
| GET | `/search` | `keywords` `limit` `type=1` |
| GET | `/song/url/v1` | `id` `level=standard\|exhigh\|lossless` |
| GET | `/song/detail` | `ids` 逗号分隔 |
| GET | `/lyric` | `id`，返回 LRC |
| GET | `/personalized/newsong` | `limit`，新歌速递 |
| GET | `/recommend/songs` | 需要 cookie，账号级每日推荐 |
| GET | `/user/account` | 需要 cookie |
| GET | `/login/qr/key` | 扫码登录：取 unikey |
| GET | `/login/qr/create` | `key` `qrimg=true` |
| GET | `/login/qr/check` | `key`，轮询 800/801/802/803 |

所有接口都接受 `cookie` 参数并原样透传给网易 —— 登录态由客户端持有。

## 部署

### Docker Compose（推荐）

```bash
cd server
cp .env.example .env
# 编辑 .env，务必设置 API_KEY
docker compose up -d --build
docker compose logs -f
```

默认只绑 `127.0.0.1:3000`，让反向代理接外面。要直接暴露就改 `docker-compose.yml` 里的端口映射。

### 反向代理（Caddy 示例）

```
api.your-domain.com {
    reverse_proxy 127.0.0.1:3000
}
```

Caddy 会自动签 HTTPS。**用 HTTPS 的话 App 那边不用配 ATS 例外。**

如果代理在服务前面，记得在 `.env` 里设 `TRUST_PROXY=true`，否则限流会把所有请求当成同一个 IP。

### 不用 Docker

```bash
npm install --omit=dev
NODE_ENV=production PORT=3000 node src/index.js
```

建议用 `systemd` 或 `pm2` 托管。

## 环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `PORT` | 3000 | 监听端口 |
| `HOST` | 0.0.0.0 | 容器里必须是 0.0.0.0 |
| `API_KEY` | 空 | **留空 = 不鉴权，任何人都能用你的服务器** |
| `RATE_LIMIT_PER_MIN` | 120 | 单 IP 每分钟请求上限 |
| `UPSTREAM_TIMEOUT_MS` | 8000 | 上游超时 |
| `TRUST_PROXY` | false | 在反向代理后面时开 |

## 安全提醒

1. **公网部署必须设 `API_KEY`。** 不设等于把接口开放给所有人，你的服务器会成为别人的免费代理。
2. **不要提交 `.env`。** 已在 `.gitignore` 里。
3. 日志默认脱敏了 `cookie` 和 `key`，别自己往日志里打。

## 合规

网易云是非官方接口，仅供个人学习使用。曲库版权归网易云所有，
用这个服务承载上架应用会被审核拒绝，也不符合网易云的服务条款。
