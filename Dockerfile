# Multi-stage Dockerfile for HyperDX
# This builds both API and App services

## Base stage for common dependencies
FROM node:22.16.0-alpine AS base
WORKDIR /app

COPY .yarn ./.yarn
COPY .yarnrc.yml yarn.lock package.json nx.json .prettierrc .prettierignore ./
COPY ./packages/common-utils ./packages/common-utils

## API Build
FROM base AS api-base
COPY ./packages/api/jest.config.js ./packages/api/tsconfig.json ./packages/api/package.json ./packages/api/
RUN yarn install --mode=skip-build && yarn cache clean

FROM api-base AS api-builder
ENV NX_DAEMON false
COPY ./packages/api/src ./packages/api/src
RUN npx nx run-many --target=build --projects=@hyperdx/common-utils,@hyperdx/api
RUN rm -rf node_modules && yarn workspaces focus @hyperdx/api --production

FROM node:22.16.0-alpine AS api-prod
ARG CODE_VERSION
ARG PORT=8000
ENV CODE_VERSION=$CODE_VERSION
ENV NODE_ENV=production
ENV PORT=$PORT
EXPOSE ${PORT}
USER node
WORKDIR /app
COPY --chown=node:node --from=api-builder /app/packages/api/dist ./
ENTRYPOINT ["node", "-r", "./tracing", "./index"]

## App Build  
FROM base AS app-base
RUN apk add --no-cache libc6-compat
COPY ./packages/app/jest.config.js ./packages/app/tsconfig.json ./packages/app/tsconfig.test.json ./packages/app/package.json ./packages/app/next.config.js ./packages/app/mdx.d.ts ./packages/app/.eslintrc.js ./packages/app/
RUN yarn install --mode=skip-build && yarn cache clean

FROM app-base AS app-builder
ARG OTEL_EXPORTER_OTLP_ENDPOINT
ARG OTEL_SERVICE_NAME
ARG IS_LOCAL_MODE
ENV NEXT_PUBLIC_OTEL_EXPORTER_OTLP_ENDPOINT $OTEL_EXPORTER_OTLP_ENDPOINT
ENV NEXT_PUBLIC_OTEL_SERVICE_NAME $OTEL_SERVICE_NAME
ENV NEXT_PUBLIC_IS_LOCAL_MODE $IS_LOCAL_MODE
ENV NX_DAEMON false

COPY ./packages/app/src ./packages/app/src
COPY ./packages/app/pages ./packages/app/pages
COPY ./packages/app/public ./packages/app/public
COPY ./packages/app/styles ./packages/app/styles
COPY ./packages/app/types ./packages/app/types
RUN npx nx run-many --target=build --projects=@hyperdx/common-utils,@hyperdx/app 
RUN rm -rf node_modules && yarn workspaces focus @hyperdx/app --production

FROM node:22.16.0-alpine AS app-prod
ARG PORT=8080
ENV NODE_ENV=production
ENV PORT=$PORT
ENV NEXT_TELEMETRY_DISABLED=1
WORKDIR /app

RUN addgroup -g 1001 -S nodejs
RUN adduser -S nextjs -u 1001

COPY --from=app-builder /app/packages/app/next.config.js ./
COPY --from=app-builder --chown=nextjs:nodejs /app/packages/app/public ./public
COPY --from=app-builder --chown=nextjs:nodejs /app/packages/app/.next ./.next
COPY --from=app-builder /app/node_modules ./node_modules
COPY --from=app-builder /app/packages/app/package.json ./package.json

USER nextjs
EXPOSE ${PORT}
CMD ["sh", "-c", "node_modules/.bin/next start -p ${PORT}"]

## Final stage - choose which service to run
FROM api-prod AS final-api
FROM app-prod AS final-app

# Default to API
FROM final-app AS final 