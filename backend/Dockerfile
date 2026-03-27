# ── Build / deps stage ──────────────────────────────────────────────────────────
FROM node:20-alpine AS base

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev

COPY . .
RUN mkdir -p uploads logs

# ── Production stage ────────────────────────────────────────────────────────────
FROM base AS production

ENV NODE_ENV=production
ENV PORT=5000

RUN addgroup -S appgroup && adduser -S appuser -G appgroup
RUN chown -R appuser:appgroup /app
USER appuser

EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
  CMD node -e "require('http').get('http://localhost:5000/health', r => process.exit(r.statusCode===200?0:1)).on('error', ()=>process.exit(1))"

CMD ["node", "server.js"]




