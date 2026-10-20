# 多阶段构建：装依赖 → 只带运行期文件
FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev || npm install --omit=dev

FROM node:22-alpine
WORKDIR /app
ENV NODE_ENV=production

# 用非 root 跑，容器逃逸时损失小一点
RUN addgroup -S app && adduser -S app -G app

COPY --from=deps /app/node_modules ./node_modules
COPY package.json ./
COPY src ./src

# xeapi 公钥会写到 /tmp，确保 app 用户可写
RUN mkdir -p /tmp && chown -R app:app /app /tmp
USER app

EXPOSE 3000
ENV HOST=0.0.0.0 PORT=3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||3000)+'/healthz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "src/index.js"]
