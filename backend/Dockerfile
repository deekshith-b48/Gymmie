# Gymmie backend. One container, one SQLite file on a volume. Run ONE instance only (rate limits and schedulers are in-process).
FROM node:22-slim
ENV NODE_ENV=production DB_FILE=/data/gymmie.sqlite PORT=8787 HOST=0.0.0.0 TRUST_PROXY=1
WORKDIR /app
COPY package.json ./
COPY src ./src
COPY scripts ./scripts
RUN mkdir -p /data && chown -R node:node /data /app
USER node
VOLUME /data
EXPOSE 8787
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:8787/ready').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node", "src/server.js"]
