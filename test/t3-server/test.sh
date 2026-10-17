#!/bin/bash
# Checks for a container built with the feature. Runs for the default options
# and, through the scenario scripts next to it, for the variants in
# scenarios.json. A scenario script may set T3_TEST_SCENARIO first.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

# shellcheck source=/dev/null
. /usr/local/share/t3-server/config
SESSION=/usr/local/share/t3-server/ssh-session
DATA_DIR=/var/lib/t3-server

# The release the app_launch scenario installs the way the T3 Code app does.
# Only the test uses it; the feature itself installs no server.
APP_VERSION=0.1.0
APP_SHA256_X64=f7703ff1bb8f6243580058b3ccf2c02abb62eba4b991e26bbb1da22f4b56d9b1
APP_SHA256_ARM64=2d07751a918252b6fa2d38119fe44c5149b62a4d684894af5c2853e8b2a94e81
APP_PORT=3773

as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo -n "$@"
  fi
}

can_be_root() {
  [ "$(id -u)" -eq 0 ] || sudo -n true 2>/dev/null
}

# An SSH session through the feature's entry point, the way t3-dev and the
# T3 Code app reach it, but with ssh-session started by sudo instead of
# `docker exec`. It is handed this process's environment, as docker exec
# hands it the container's.
ssh_run() {
  ssh -F /dev/null -o BatchMode=yes -o LogLevel=ERROR \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ProxyCommand="sudo -n -E env PATH=\"$PATH\" $SESSION" \
    "${T3_SERVER_USER}@t3-test" "$@"
}

ssh_possible() {
  command -v ssh >/dev/null 2>&1 && can_be_root
}

data_dir_belongs_to_the_user() {
  [ "$(stat -c %U "$DATA_DIR")" = "$T3_SERVER_USER" ] &&
    [ "$(stat -c %a "$DATA_DIR")" = "700" ]
}

# The home directory has to be the user's own, the one sshd logs in to.
home_links_to_the_data_volume() {
  local passwd_home
  passwd_home="$(getent passwd "$T3_SERVER_USER" | cut -d: -f6)"
  echo "config home: ${T3_SERVER_USER_HOME}, user database: ${passwd_home}, ~/.t3 -> $(readlink "${passwd_home}/.t3" 2>&1)"
  [ "$T3_SERVER_USER_HOME" = "$passwd_home" ] &&
    [ "$(readlink -f "${T3_SERVER_USER_HOME}/.t3")" = "$DATA_DIR" ]
}

no_server_in_the_image() {
  ! command -v t3 >/dev/null 2>&1 && [ ! -e /opt/t3-server ] && [ ! -e /usr/local/bin/t3-pair ]
}

# What the app's installer needs in the container.
app_installer_can_run() {
  { command -v curl || command -v wget; } >/dev/null &&
    command -v tar >/dev/null && command -v gzip >/dev/null && command -v sha256sum >/dev/null &&
    ldconfig -p | grep -q "libatomic\.so\.1"
}

# t3-dev reads these two to know the server is not started by the feature.
config_tells_t3_dev_the_mode() {
  [ "$T3_SERVER_SSH" = "true" ] && [ "$T3_SERVER_AUTOSTART" = "false" ]
}

# The project is mounted at /workspaces/<folder>. T3 Code should show
# t3-<folder> for the environment, the same name t3-dev gives the SSH host,
# instead of the container ID.
expected_label() {
  local folder
  folder="$(awk '$5 ~ /^\/workspaces\/[^\/]+$/ { n = split($5, part, "/"); print part[n]; exit }' /proc/self/mountinfo)"
  [ -n "$folder" ] || return 0
  printf 't3-%s' "$(printf '%s' "$folder" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-' '-')"
}

environment_label_follows_the_workspace() {
  local expected
  expected="$(expected_label)"
  [ -n "$expected" ] || return 0
  [ "$(t3-server label)" = "$expected" ] || return 1
  grep -qxF "PRETTY_HOSTNAME=\"${expected}\"" /etc/machine-info
}

sshd_config_is_valid() {
  as_root mkdir -p /run/sshd
  as_root /usr/sbin/sshd -t -f /usr/local/share/t3-server/sshd_config
}

# The login shell the app starts its server from gets the container's
# environment back, with telemetry off and HOME pointing at the user.
login_shell_has_the_container_environment() {
  local out want_path entry
  out="$(ssh_run sh -l -s <<'EOF'
printf '%s\n' "PATH=$PATH" "HOME=$HOME" "MARK=${T3_TEST_MARK:-}" \
  "TELEMETRY=${T3CODE_TELEMETRY_ENABLED:-}" "T3HOME=$(readlink -f "$HOME/.t3")"
EOF
)"
  echo "$out"
  grep -qxF "TELEMETRY=false" <<<"$out" || return 1
  grep -qxF "HOME=${T3_SERVER_USER_HOME}" <<<"$out" || return 1
  grep -qxF "T3HOME=${DATA_DIR}" <<<"$out" || return 1
  if [ -n "${T3_TEST_MARK:-}" ]; then
    grep -qxF "MARK=${T3_TEST_MARK}" <<<"$out" || return 1
  fi
  want_path="$(sed -n 's/^PATH=//p' <<<"$out")"
  local IFS=:
  for entry in $PATH; do
    [[ ":${want_path}:" == *":${entry}:"* ]] || {
      echo "missing from the session PATH: ${entry}"
      return 1
    }
  done
}

session_env_is_private() {
  [ "$(as_root stat -c '%U %a' /run/t3-server/session-env)" = "${T3_SERVER_USER} 600" ]
}

# Installs and starts the server over SSH the way the T3 Code app's launcher
# does: into ~/.t3/runtime/versions/<version>, from the home directory, with
# --base-dir ~/.t3, detached, logging under ~/.t3/ssh-launch/.
app_style_launch() {
  local arch sha
  case "$(uname -m)" in
    x86_64 | amd64) arch=x64 sha="$APP_SHA256_X64" ;;
    *) arch=arm64 sha="$APP_SHA256_ARM64" ;;
  esac
  ssh_run sh -l -s <<EOF
set -eu
dir="\$HOME/.t3/runtime/versions/${APP_VERSION}"
mkdir -p "\$dir" "\$HOME/.t3/ssh-launch/test"
cd "\$(mktemp -d)"
curl -fsSL --retry 4 -o t3.tar.gz "https://github.com/pingdotgg/t3code/releases/download/v${APP_VERSION}/t3-${APP_VERSION}-linux-${arch}.tar.gz"
echo "${sha}  t3.tar.gz" | sha256sum -c -
tar -xzf t3.tar.gz -C "\$dir" --strip-components=1
echo "${APP_VERSION}" >"\$dir/.install-complete"
cd "\$HOME"
nohup env T3CODE_NO_BROWSER=1 "\$dir/t3" serve --host 127.0.0.1 --port ${APP_PORT} --base-dir "\$HOME/.t3" \
  >>"\$HOME/.t3/ssh-launch/test/server.log" 2>&1 </dev/null &
EOF
  local tries=0
  until t3-server status >/dev/null 2>&1; do
    tries=$((tries + 1))
    [ "$tries" -lt 90 ] || {
      t3-server logs -n 40 || true
      return 1
    }
    sleep 1
  done
  t3-server status
}

server_pid() {
  sed -n 's/.*"pid"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "${DATA_DIR}/userdata/server-runtime.json" | head -n 1
}

app_server_sees_the_container_environment() {
  local environ
  environ="$(tr '\0' '\n' <"/proc/$(server_pid)/environ")"
  grep -qxF "T3CODE_TELEMETRY_ENABLED=false" <<<"$environ" || return 1
  if [ -n "${T3_TEST_MARK:-}" ]; then
    grep -qxF "T3_TEST_MARK=${T3_TEST_MARK}" <<<"$environ" || return 1
  fi
}

app_server_reports_version_and_name() {
  local status expected
  status="$(t3-server status)"
  grep -qF "T3 Code ${APP_VERSION}" <<<"$status" || return 1
  expected="$(expected_label)"
  [ -z "$expected" ] || grep -qF "named '${expected}'" <<<"$status"
}

if [ "${T3_TEST_SCENARIO:-}" = "compose" ]; then
  # A Compose project is not mounted under /workspaces, so the feature has no
  # name for it; t3-dev names it (see the repository README). The entrypoint
  # still has to have prepared the volume.
  check "the project is not under /workspaces" bash -c "! awk '\$5 ~ /^\\/workspaces\\// { f = 1 } END { exit !f }' /proc/self/mountinfo"
  check "no name without a /workspaces mount" bash -c "[ -z \"\$(t3-server label)\" ]"
fi

check "no T3 Code server is installed in the image" no_server_in_the_image
check "the app's installer has what it needs" app_installer_can_run
check "config tells t3-dev the server is the app's" config_tells_t3_dev_the_mode
check "data dir is private and owned by the user" data_dir_belongs_to_the_user
check "home links to the data volume" home_links_to_the_data_volume
check "the entrypoint made the ssh host key" bash -c "[ \"\$(stat -c %a ${DATA_DIR}/ssh/ssh_host_ed25519_key)\" = 600 ]"
check "ssh entry point is installed" test -x "$SESSION"
check "login shells restore the saved environment" test -r /etc/profile.d/t3-server-ssh-env.sh
check "environment label follows the workspace folder" environment_label_follows_the_workspace
check "no sshd daemon is running" bash -c "! pgrep -x sshd"
check "status says nothing runs before the app connects" bash -c "t3-server status; [ \$? -eq 3 ]"
# A postStartCommand from 0.x runs 't3-server start'; it must not fail.
check "start succeeds without doing anything" bash -c "t3-server start | grep -q 'nothing to do' && ! t3-server status >/dev/null"

if can_be_root; then
  check "sshd accepts its configuration" sshd_config_is_valid
fi
if ssh_possible; then
  check "an SSH login shell has the container's environment" login_shell_has_the_container_environment
  check "the saved environment is readable by the user only" session_env_is_private
fi

if [ "${T3_TEST_SCENARIO:-}" = "app_launch" ]; then
  check "a server started over SSH like the app does comes up" app_style_launch
  check "that server sees the container's environment and has telemetry off" app_server_sees_the_container_environment
  check "status reports its version and name" app_server_reports_version_and_name
  check "logs hide pairing secrets" bash -c "t3-server logs -n 500 >/dev/null && ! t3-server logs -n 500 | grep -e 'Token:' -e 'Pairing URL:' -e '[█▀▄]'"
  check "stop stops it" bash -c "t3-server stop && ! t3-server status"
fi

reportResults
