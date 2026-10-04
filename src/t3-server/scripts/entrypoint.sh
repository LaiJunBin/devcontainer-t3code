#!/bin/sh
# Feature entrypoint: runs every time the container starts, however it was
# started. It must never block or fail the container, so the server is started
# without waiting and every error is swallowed; 't3-server status' reports it.
CONFIG=/usr/local/share/t3-server/config
if [ -r "$CONFIG" ]; then
  # shellcheck source=/dev/null
  . "$CONFIG"
  /usr/local/bin/t3-server prepare >/dev/null 2>&1 || true
  if [ "${T3_SERVER_AUTOSTART:-true}" = "true" ]; then
    /usr/local/bin/t3-server start --no-wait >/dev/null 2>&1 || true
  fi
fi

exec "$@"
