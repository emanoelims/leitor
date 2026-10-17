#!/bin/sh
set -eu
/usr/local/bin/dind dockerd --host=unix:///var/run/docker.sock --storage-driver=vfs --bridge=none --iptables=false --ip-forward=false --ip-masq=false > /var/log/leitor-docker.log 2>&1 &
for attempt in $(seq 1 60); do
  if docker info > /dev/null 2>&1; then break; fi
  sleep 1
done
docker info > /dev/null
gzip -dc /opt/runner-rootfs.tar.gz | docker import --change 'USER node' --change 'WORKDIR /runner' --change 'ENV HOME=/tmp' --change 'ENTRYPOINT ["timeout","75s","node","/runner/check.mjs"]' - leitor-figure:runtime > /dev/null
docker run --rm --network none --read-only --cap-drop ALL --security-opt no-new-privileges --pids-limit 32 --memory 64m --cpus 1 --entrypoint node leitor-figure:runtime --version > /dev/null
exec node /service/service.mjs
