FROM node:22-alpine
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev || npm install --omit=dev
COPY src ./src
ENV NODE_ENV=production
EXPOSE 3000
USER node
# Node 22.18+ runs TypeScript directly (type stripping), so there is no build step.
CMD ["node", "src/index.ts"]
