#!/bin/sh
# Feature entrypoint: runs every time the container starts, however it was
# started. It names the environment, repairs the data volume's owner and
# makes the SSH host key. It must never block or fail the container, so every
# error is swallowed. The server itself is started by the T3 Code app when it
# connects.
if [ -r /usr/local/share/t3-server/config ]; then
  /usr/local/bin/t3-server prepare >/dev/null 2>&1 || true
fi

exec "$@"
