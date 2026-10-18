FROM node:22.23.3-bookworm-slim@sha256:c3de60bf2f9dd0ac6370e6117950ff62d6e339527e7472301c9c78a017978392 AS runner
RUN apt-get update && apt-get install -y --no-install-recommends chromium fonts-dejavu-core && rm -rf /var/lib/apt/lists/*
WORKDIR /runner
COPY figure_runner/package*.json ./
RUN npm ci --ignore-scripts && npm rebuild esbuild
COPY figure_runner/*.mjs ./
COPY assets/vendor/anatomy/ ./kit/
COPY assets/js/figures/kit/ ./leitor/

FROM docker:29-dind@sha256:3e5756e2b6dad6a5f1f5deacf0a19f9eaa2581b76ae092b2d4a118162e1d4d4e AS pack
COPY --from=runner / /rootfs/
RUN tar -C /rootfs -czf /runner-rootfs.tar.gz .

FROM docker:29-dind@sha256:3e5756e2b6dad6a5f1f5deacf0a19f9eaa2581b76ae092b2d4a118162e1d4d4e
RUN apk add --no-cache nodejs
COPY --from=pack /runner-rootfs.tar.gz /opt/runner-rootfs.tar.gz
COPY figure_service/service.mjs /service/service.mjs
COPY --chmod=755 figure_service/start.sh /service/start.sh
ENV PORT=8081
VOLUME ["/data"]
ENTRYPOINT ["/service/start.sh"]
