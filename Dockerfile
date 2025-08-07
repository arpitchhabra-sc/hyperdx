FROM node:${NODE_VERSION}-alpine AS prod

ARG CODE_VERSION

ENV CODE_VERSION=$CODE_VERSION
ENV NODE_ENV production

# Install libs used for the start script
RUN npm install -g concurrently@9.1.0

USER node

# Set up API and App
WORKDIR /app
COPY --chown=node:node --from=builder /app/packages/api/dist ./packages/api
COPY --chown=node:node --from=builder /app/packages/app/.next/standalone ./packages/app
COPY --chown=node:node --from=builder /app/packages/app/.next/static ./packages/app/packages/app/.next/static
COPY --chown=node:node --from=builder /app/packages/app/public ./packages/app/packages/app/public

# Set up start script
COPY --chown=node:node --from=hyperdx ./entry.prod.sh /etc/local/entry.sh
ENTRYPOINT ["sh", "/etc/local/entry.sh"]