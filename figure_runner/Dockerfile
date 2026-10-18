FROM node:22.23.3-bookworm-slim@sha256:c3de60bf2f9dd0ac6370e6117950ff62d6e339527e7472301c9c78a017978392
RUN apt-get update && apt-get install -y --no-install-recommends chromium fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /runner
COPY figure_runner/package*.json ./
RUN npm ci --ignore-scripts && npm rebuild esbuild
COPY figure_runner/*.mjs ./
COPY assets/vendor/anatomy/ ./kit/
COPY assets/js/figures/kit/ ./leitor/
USER node
ENV HOME=/tmp
ENTRYPOINT ["timeout", "75s", "node", "/runner/check.mjs"]
