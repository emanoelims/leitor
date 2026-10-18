#!/bin/sh
set -eu
mkdir -p /data/docker
/usr/local/bin/dind dockerd --host=unix:///var/run/docker.sock --data-root=/data/docker --storage-driver=overlay2 --bridge=none --iptables=false --ip-forward=false --ip-masq=false > /var/log/leitor-docker.log 2>&1 &
for attempt in $(seq 1 60); do
  if docker info > /dev/null 2>&1; then break; fi
  sleep 1
done
docker info > /dev/null
docker container prune --force --filter 'label=leitor.figure=true' > /dev/null
leitor_runtime_digest=$(sha256sum /opt/runner-rootfs.tar.gz | cut -d ' ' -f 1)
leitor_cached_digest=$(docker image inspect --format '{{index .Config.Labels "leitor.runtime.digest"}}' leitor-figure:runtime 2>/dev/null || true)
if [ "$leitor_runtime_digest" != "$leitor_cached_digest" ]; then
  gzip -dc /opt/runner-rootfs.tar.gz | docker import --change 'USER node' --change 'WORKDIR /runner' --change 'ENV HOME=/tmp' --change "LABEL leitor.runtime.digest=$leitor_runtime_digest" --change 'ENTRYPOINT ["timeout","75s","node","/runner/check.mjs"]' - leitor-figure:runtime > /dev/null
fi
docker image prune --force --filter 'label=leitor.runtime.digest' > /dev/null
docker run --rm --label leitor.figure=true --network none --read-only --cap-drop ALL --security-opt no-new-privileges --pids-limit 32 --memory 64m --cpus 1 --entrypoint node leitor-figure:runtime --version > /dev/null
exec node /service/service.mjs
