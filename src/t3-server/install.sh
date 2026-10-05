#!/bin/sh
# Dev container feature install script. Runs as root while the image is built.
set -eu

VERSION="${VERSION:-0.0.45}"
AUTOSTART="${AUTOSTART:-true}"
HOST="${HOST:-127.0.0.1}"
SSH="${SSH:-true}"
STRICT="${STRICT:-true}"
REMOTE_USER="${_REMOTE_USER:-root}"
REMOTE_USER_HOME="${_REMOTE_USER_HOME:-/root}"
# Mirror for release archives; the pinned hash still has to match.
RELEASE_BASE_URL="${T3_SERVER_RELEASE_BASE_URL:-https://github.com/pingdotgg/t3code/releases/download}"

INSTALL_ROOT=/opt/t3-server
SHARE_DIR=/usr/local/share/t3-server
DATA_DIR=/var/lib/t3-server
FEATURE_DIR="$(cd "$(dirname "$0")" && pwd)"

fail() {
  echo "t3-server feature: $1" >&2
  exit 1
}

# For things the image cannot support. With "strict": false the feature steps
# aside instead of failing the build, which is what you want when it is applied
# to every dev container through VS Code's dev.containers.defaultFeatures.
# The entrypoint path is fixed in devcontainer-feature.json, so a pass-through
# one is still installed.
unsupported() {
  [ "$STRICT" = "false" ] || fail "$1"
  echo "t3-server feature: skipped, nothing installed: $1" >&2
  mkdir -p "$SHARE_DIR"
  printf '#!/bin/sh\nexec "$@"\n' >"${SHARE_DIR}/entrypoint.sh"
  chmod 0755 "${SHARE_DIR}/entrypoint.sh"
  exit 0
}

[ "$(id -u)" -eq 0 ] || fail "install.sh must run as root"

case "$VERSION" in
  *[!0-9.]* | "" | .* | *. | *..*) fail "version must look like 0.0.45, got '${VERSION}'" ;;
esac
case "$AUTOSTART" in
  true | false) ;;
  *) fail "autostart must be true or false, got '${AUTOSTART}'" ;;
esac
case "$SSH" in
  true | false) ;;
  *) fail "ssh must be true or false, got '${SSH}'" ;;
esac
case "$STRICT" in
  true | false) ;;
  *) fail "strict must be true or false, got '${STRICT}'" ;;
esac
case "$HOST" in
  127.0.0.1 | 0.0.0.0) ;;
  *) fail "host must be 127.0.0.1 or 0.0.0.0, got '${HOST}'" ;;
esac

# These two are written into sourced or parsed config files, so keep them literal.
case "$REMOTE_USER" in
  "" | *[!A-Za-z0-9._-]*) fail "unexpected remote user name '${REMOTE_USER}'" ;;
esac
case "$REMOTE_USER_HOME" in
  /*) ;;
  *) fail "remote user home must be an absolute path, got '${REMOTE_USER_HOME}'" ;;
esac
case "$REMOTE_USER_HOME" in
  *[!A-Za-z0-9._/-]*) fail "unexpected characters in remote user home '${REMOTE_USER_HOME}'" ;;
esac
if [ "$SSH" = "true" ] && [ "$REMOTE_USER" = "root" ]; then
  unsupported "the ssh option needs a non-root remoteUser; set remoteUser in devcontainer.json or use \"ssh\": false"
fi

[ "$(uname -s)" = "Linux" ] || unsupported "only Linux containers are supported"
case "$(uname -m)" in
  x86_64 | amd64) arch=x64 ;;
  aarch64 | arm64) arch=arm64 ;;
  *) unsupported "unsupported architecture $(uname -m)" ;;
esac
# The published executable is linked against glibc.
if ! getconf GNU_LIBC_VERSION >/dev/null 2>&1; then
  unsupported "this image does not use glibc (Alpine and other musl images are not supported)"
fi

# shellcheck source=/dev/null
. "${FEATURE_DIR}/versions.sh"
expected="$(t3_server_archive_sha256 "$VERSION" "$arch")" ||
  fail "T3 Code ${VERSION} (${arch}) has no pinned hash in this feature; use a listed version or update the feature"

# What the install and the runtime scripts need, as distro-neutral names.
needs=""
command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || needs="${needs} curl"
command -v tar >/dev/null 2>&1 || needs="${needs} tar"
command -v gzip >/dev/null 2>&1 || needs="${needs} gzip"
command -v sha256sum >/dev/null 2>&1 || needs="${needs} sha256sum"
command -v bash >/dev/null 2>&1 || needs="${needs} bash"
[ -e /etc/ssl/certs/ca-certificates.crt ] || [ -e /etc/pki/tls/certs/ca-bundle.crt ] || needs="${needs} certificates"
# The executable links against libatomic, which minimal images leave out.
ldconfig -p 2>/dev/null | grep -q "libatomic\.so\.1" || needs="${needs} libatomic"
# The entrypoint may run as root and has to drop to the server's user.
if [ "$REMOTE_USER" != "root" ]; then
  command -v runuser >/dev/null 2>&1 || command -v setpriv >/dev/null 2>&1 || needs="${needs} runuser"
fi
if [ "$SSH" = "true" ]; then
  [ -x /usr/sbin/sshd ] && command -v ssh-keygen >/dev/null 2>&1 || needs="${needs} sshd"
  command -v passwd >/dev/null 2>&1 || needs="${needs} passwd"
fi

# Maps a need to this distro family's package name.
package_for() {
  case "$1:$2" in
    apt:sha256sum | dnf:sha256sum) echo coreutils ;;
    apt:certificates | dnf:certificates) echo ca-certificates ;;
    apt:libatomic) echo libatomic1 ;;
    dnf:libatomic) echo libatomic ;;
    apt:runuser | dnf:runuser) echo util-linux ;;
    apt:sshd | dnf:sshd) echo openssh-server ;;
    dnf:passwd) echo shadow-utils ;;
    *) echo "$2" ;;
  esac
}

if [ -n "$needs" ]; then
  if command -v apt-get >/dev/null 2>&1; then
    family=apt
  elif command -v dnf >/dev/null 2>&1 || command -v microdnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
    family=dnf
  else
    unsupported "this image is missing:${needs}. Add them to the base image; only apt- and dnf-based images are set up automatically"
  fi
  packages=""
  for need in $needs; do
    packages="${packages} $(package_for "$family" "$need")"
  done
  echo "t3-server feature: installing${packages}"
  # shellcheck disable=SC2086 # word splitting is intended: a list of package names
  if [ "$family" = "apt" ]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends $packages
    rm -rf /var/lib/apt/lists/*
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y $packages && dnf clean all
  elif command -v microdnf >/dev/null 2>&1; then
    microdnf install -y $packages && microdnf clean all
  else
    yum install -y $packages && yum clean all
  fi
fi

archive="t3-${VERSION}-linux-${arch}.tar.gz"
url="${RELEASE_BASE_URL}/v${VERSION}/${archive}"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT

# A connection that stalls must not hang the image build: give up on one that
# moves less than 1 kB/s for 30 seconds, then retry, continuing the partial
# file. The hash check below covers whatever a resumed download produces.
echo "t3-server feature: downloading ${archive} (about 70 MB) from ${RELEASE_BASE_URL}"
# On a slow link this is the step a build sits on, so say how far it is: a
# silent build looks hung.
(
  while sleep 20; do
    size="$(wc -c <"${staging}/${archive}" 2>/dev/null || echo 0)"
    echo "t3-server feature: downloaded $((size / 1048576)) MB so far"
  done
) &
progress_pid=$!
download_status=0
if command -v curl >/dev/null 2>&1; then
  curl -fsSL --connect-timeout 20 --speed-limit 1024 --speed-time 30 \
    --retry 4 --retry-delay 2 -C - -o "${staging}/${archive}" "$url" || download_status=$?
else
  wget -q --timeout=30 --tries=5 --continue -O "${staging}/${archive}" "$url" || download_status=$?
fi
kill "$progress_pid" 2>/dev/null || true
wait "$progress_pid" 2>/dev/null || true
if [ "$download_status" -ne 0 ]; then
  unsupported "could not download ${url} (stalled or unreachable after several tries)"
fi

actual="$(sha256sum "${staging}/${archive}" | cut -d' ' -f1)"
if [ "$actual" != "$expected" ]; then
  fail "hash mismatch for ${archive}: expected ${expected}, got ${actual}. Nothing was installed"
fi

mkdir -p "${staging}/unpacked"
tar -xzf "${staging}/${archive}" -C "${staging}/unpacked" --strip-components=1 --no-same-owner
if ! run_output="$("${staging}/unpacked/t3" --version 2>&1)"; then
  echo "$run_output" >&2
  ldd "${staging}/unpacked/t3" 2>/dev/null | grep "not found" >&2 || true
  unsupported "the verified executable does not run in this image (see the lines above)"
fi
# Same marker the official installer writes. With it, a T3 Code client of the
# same version that connects over SSH uses this copy instead of downloading.
printf '%s\n' "$VERSION" >"${staging}/unpacked/.install-complete"

target="${INSTALL_ROOT}/versions/${VERSION}"
rm -rf "$target"
mkdir -p "${INSTALL_ROOT}/versions"
mv "${staging}/unpacked" "$target"
chown -R root:root "$INSTALL_ROOT"
chmod -R go-w "$INSTALL_ROOT"
ln -sfn "${target}/t3" /usr/local/bin/t3

mkdir -p "$SHARE_DIR"
install -m 0755 "${FEATURE_DIR}/scripts/entrypoint.sh" "${SHARE_DIR}/entrypoint.sh"
install -m 0755 "${FEATURE_DIR}/scripts/t3-server" /usr/local/bin/t3-server
install -m 0755 "${FEATURE_DIR}/scripts/t3-pair" /usr/local/bin/t3-pair
cat >"${SHARE_DIR}/config" <<EOF
# Written by the t3-server dev container feature at image build time.
T3_SERVER_VERSION='${VERSION}'
T3_SERVER_USER='${REMOTE_USER}'
T3_SERVER_USER_HOME='${REMOTE_USER_HOME}'
T3_SERVER_AUTOSTART='${AUTOSTART}'
T3_SERVER_DATA_DIR='${DATA_DIR}'
T3_SERVER_HOST='${HOST}'
T3_SERVER_PORT='3773'
T3_SERVER_SSH='${SSH}'
EOF
chmod 0644 "${SHARE_DIR}/config"

# The data volume is mounted here. A new named volume takes its ownership and
# mode from this directory, so the server never needs root to use it.
mkdir -p "$DATA_DIR"
if id "$REMOTE_USER" >/dev/null 2>&1; then
  chown "${REMOTE_USER}:$(id -gn "$REMOTE_USER")" "$DATA_DIR"
else
  echo "t3-server feature: user '${REMOTE_USER}' does not exist yet; ${DATA_DIR} stays owned by root" >&2
fi
chmod 0700 "$DATA_DIR"

# T3 Code's default home is ~/.t3, and that is where a client connecting over
# SSH looks for a server it can reuse. Point it at the data volume.
t3_home="${REMOTE_USER_HOME}/.t3"
if [ -L "$t3_home" ] || [ ! -e "$t3_home" ]; then
  mkdir -p "$REMOTE_USER_HOME"
  ln -sfn "$DATA_DIR" "$t3_home"
  if id "$REMOTE_USER" >/dev/null 2>&1; then
    chown -h "${REMOTE_USER}:$(id -gn "$REMOTE_USER")" "$t3_home"
  fi
else
  unsupported "${t3_home} already exists in the image; remove it or the mount that provides it, so the feature can link it to ${DATA_DIR}"
fi

if [ "$SSH" = "true" ]; then
  id "$REMOTE_USER" >/dev/null 2>&1 || unsupported "the ssh option needs the user '${REMOTE_USER}' to exist in the image"
  install -m 0755 "${FEATURE_DIR}/scripts/ssh-session" "${SHARE_DIR}/ssh-session"
  # Only ever used by ssh-session, which is reached through \`docker exec\`.
  # The system sshd configuration is left untouched.
  cat >"${SHARE_DIR}/sshd_config" <<EOF
# Written by the t3-server dev container feature. Used only by:
#   docker exec -i -u root <container> ${SHARE_DIR}/ssh-session
HostKey ${DATA_DIR}/ssh/ssh_host_ed25519_key
PidFile none
UsePAM no
AllowUsers ${REMOTE_USER}
PermitRootLogin no
PubkeyAuthentication no
KbdInteractiveAuthentication no
PasswordAuthentication yes
PermitEmptyPasswords yes
PrintMotd no
AllowTcpForwarding local
X11Forwarding no
SetEnv T3CODE_TELEMETRY_ENABLED=false
EOF
  chmod 0644 "${SHARE_DIR}/sshd_config"
  # Password-less login through that one sshd only: the system sshd, if any,
  # keeps PermitEmptyPasswords at its default of "no".
  passwd -d "$REMOTE_USER" >/dev/null
else
  # Leave nothing behind from a layer that had the option on.
  rm -f "${SHARE_DIR}/ssh-session" "${SHARE_DIR}/sshd_config"
fi

echo "t3-server feature: installed T3 Code ${VERSION} (${arch}), server user '${REMOTE_USER}', host ${HOST}, ssh ${SSH}"
