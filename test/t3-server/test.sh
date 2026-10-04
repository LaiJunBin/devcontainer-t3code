#!/bin/bash
# Checks for a container built with the feature. Runs for the default options
# and, through the scenario scripts next to it, for the variants in
# scenarios.json. It adapts to what the feature's config says was installed.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

PID_FILE=/var/lib/t3-server/server.pid
# shellcheck source=/dev/null
. /usr/local/share/t3-server/config

# /proc/<pid>/cwd and environ are readable only by the process owner (root
# included, unless it has CAP_SYS_PTRACE), so read them as that user.
as_server_user() {
  if [ "$(id -un)" = "$T3_SERVER_USER" ]; then
    "$@"
  else
    runuser -u "$T3_SERVER_USER" -- "$@"
  fi
}

server_cwd_is_root() {
  [ "$(as_server_user readlink "/proc/$(cat "$PID_FILE")/cwd")" = "/" ]
}

server_telemetry_is_off() {
  as_server_user cat "/proc/$(cat "$PID_FILE")/environ" | tr '\0' '\n' |
    grep -Fxq "T3CODE_TELEMETRY_ENABLED=false"
}

server_user_matches_config() {
  [ "$(stat -c %U "/proc/$(cat "$PID_FILE")")" = "$T3_SERVER_USER" ]
}

data_dir_belongs_to_server_user() {
  [ "$(stat -c %U /var/lib/t3-server)" = "$T3_SERVER_USER" ] &&
    [ "$(stat -c %a /var/lib/t3-server)" = "700" ]
}

server_home_is_linked() {
  [ "$(readlink -f "${T3_SERVER_USER_HOME}/.t3")" = "/var/lib/t3-server" ]
}

runtime_is_linked() {
  local dir="/var/lib/t3-server/runtime/versions/${T3_SERVER_VERSION}"
  as_server_user test -x "${dir}/t3" &&
    [ "$(as_server_user cat "${dir}/.install-complete")" = "$T3_SERVER_VERSION" ]
}

listens_on_configured_host() {
  grep -Fq "\"host\":\"${T3_SERVER_HOST}\"" /var/lib/t3-server/userdata/server-runtime.json
}

# After a container restart the pid file in the volume names a pid that now
# belongs to some other live process. The server must still start.
starts_despite_stale_pid_file() {
  t3-server stop >/dev/null
  sleep 300 &
  local other=$!
  if [ "$(id -un)" = "$T3_SERVER_USER" ]; then
    echo "$other" >"$PID_FILE"
  else
    echo "$other" | runuser -u "$T3_SERVER_USER" -- tee "$PID_FILE" >/dev/null
  fi
  local result=0
  t3-server start >/dev/null && t3-server status >/dev/null || result=1
  kill "$other" 2>/dev/null || true
  return "$result"
}

check "t3 is the pinned version" bash -c "t3 --version | grep -F '${T3_SERVER_VERSION}'"
check "install tree is not writable by others" bash -c "[ -z \"\$(find /opt/t3-server -perm /022 -print -quit)\" ]"
check "server starts and answers" bash -c "t3-server start && t3-server status"
check "data dir is private and owned by the server user" data_dir_belongs_to_server_user
check "start is idempotent" bash -c "t3-server start | grep -F 'already running'"
check "server runs from /" server_cwd_is_root
check "telemetry is off for the server" server_telemetry_is_off
check "server runs as the configured user" server_user_matches_config
check "log is private" bash -c "[ \"\$(stat -c %a /var/lib/t3-server/server.log)\" = '600' ]"
check "logs hide pairing secrets" bash -c "! t3-server logs -n 500 | grep -e 'Token:' -e 'Pairing URL:' -e '[█▀▄]'"
check "pairing link is rewritten" bash -c "t3-pair 38101 | grep -F 'http://127.0.0.1:38101/'"
check "server listens on the configured address" listens_on_configured_host
check "home links to the data volume" server_home_is_linked
check "image runtime is offered to SSH clients" runtime_is_linked
if [ "$T3_SERVER_SSH" = "true" ]; then
  check "ssh host key is in the data volume" bash -c "[ \"\$(stat -c %a /var/lib/t3-server/ssh/ssh_host_ed25519_key)\" = 600 ]"
  check "ssh entry point is installed" test -x /usr/local/share/t3-server/ssh-session
else
  check "no ssh entry point without the ssh option" bash -c "! test -e /usr/local/share/t3-server/ssh-session"
fi
check "no sshd daemon is running" bash -c "! pgrep -x sshd"
check "a stale pid file does not block the start" starts_despite_stale_pid_file
check "server stops" bash -c "t3-server stop && ! t3-server status"

reportResults
