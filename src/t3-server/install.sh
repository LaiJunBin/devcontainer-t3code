#!/bin/sh
# Dev container feature install script. Runs as root while the image is built.
#
# The feature does not install T3 Code itself. The T3 Code desktop app, when
# it connects over SSH, downloads the server of its own version into ~/.t3 and
# starts it, and replaces it after the app updates. This script prepares what
# that needs: an SSH entry point reachable only through `docker exec`, a data
# volume behind ~/.t3, and the tools the app's installer uses.
set -eu

STRICT="${STRICT:-true}"
REMOTE_USER="${_REMOTE_USER:-root}"
REMOTE_USER_HOME="${_REMOTE_USER_HOME:-/root}"

SHARE_DIR=/usr/local/share/t3-server
DATA_DIR=/var/lib/t3-server
PROFILE_SCRIPT=/etc/profile.d/t3-server-ssh-env.sh
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

case "$STRICT" in
  true | false) ;;
  *) fail "strict must be true or false, got '${STRICT}'" ;;
esac

# Options of 0.3 and earlier, when the feature installed and ran the server.
# They have no effect any more; say so rather than ignore them silently.
for removed in VERSION AUTOSTART HOST SSH; do
  eval "value=\${${removed}:-}"
  if [ -n "$value" ]; then
    echo "t3-server feature: the '$(echo "$removed" | tr '[:upper:]' '[:lower:]')' option was removed in 1.0.0 and is ignored; the T3 Code app now installs and starts the server" >&2
  fi
done

# Written into sourced or parsed config files, so keep it literal.
case "$REMOTE_USER" in
  "" | *[!A-Za-z0-9._-]*) fail "unexpected remote user name '${REMOTE_USER}'" ;;
esac
if [ "$REMOTE_USER" = "root" ]; then
  unsupported "the SSH entry point needs a non-root remoteUser; set remoteUser in devcontainer.json"
fi
id "$REMOTE_USER" >/dev/null 2>&1 || unsupported "the remote user '${REMOTE_USER}' does not exist in the image"

# The home directory sshd gives the user is the one in the user database, and
# that is where the app looks for ~/.t3. _REMOTE_USER_HOME is worked out from
# the base image before any feature runs, so for a user that a feature such
# as common-utils creates it can point somewhere else, often /root.
passwd_home="$(getent passwd "$REMOTE_USER" 2>/dev/null | cut -d: -f6)"
if [ -n "$passwd_home" ] && [ "$passwd_home" != "$REMOTE_USER_HOME" ]; then
  echo "t3-server feature: using ${REMOTE_USER}'s home directory ${passwd_home} from the user database instead of ${REMOTE_USER_HOME}"
  REMOTE_USER_HOME="$passwd_home"
fi
# Also written into config files.
case "$REMOTE_USER_HOME" in
  /*) ;;
  *) fail "remote user home must be an absolute path, got '${REMOTE_USER_HOME}'" ;;
esac
case "$REMOTE_USER_HOME" in
  *[!A-Za-z0-9._/-]*) fail "unexpected characters in remote user home '${REMOTE_USER_HOME}'" ;;
esac

[ "$(uname -s)" = "Linux" ] || unsupported "only Linux containers are supported"
case "$(uname -m)" in
  x86_64 | amd64 | aarch64 | arm64) ;;
  *) unsupported "unsupported architecture $(uname -m); T3 Code publishes x64 and arm64 builds only" ;;
esac
# The server the app downloads is linked against glibc.
if ! getconf GNU_LIBC_VERSION >/dev/null 2>&1; then
  unsupported "this image does not use glibc (Alpine and other musl images are not supported)"
fi

# What the app's installer and these scripts need, as distro-neutral names.
needs=""
command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || needs="${needs} curl"
command -v tar >/dev/null 2>&1 || needs="${needs} tar"
command -v gzip >/dev/null 2>&1 || needs="${needs} gzip"
command -v sha256sum >/dev/null 2>&1 || needs="${needs} sha256sum"
command -v bash >/dev/null 2>&1 || needs="${needs} bash"
[ -e /etc/ssl/certs/ca-certificates.crt ] || [ -e /etc/pki/tls/certs/ca-bundle.crt ] || needs="${needs} certificates"
# The server executable links against libatomic, which minimal images leave out.
ldconfig -p 2>/dev/null | grep -q "libatomic\.so\.1" || needs="${needs} libatomic"
# The entrypoint runs as root and has to drop to the user.
command -v runuser >/dev/null 2>&1 || command -v setpriv >/dev/null 2>&1 || needs="${needs} runuser"
[ -x /usr/sbin/sshd ] && command -v ssh-keygen >/dev/null 2>&1 || needs="${needs} sshd"
command -v passwd >/dev/null 2>&1 || needs="${needs} passwd"

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

# What 0.3 and earlier installed into the image, in case this layer sits on
# an image built with it.
rm -rf /opt/t3-server
rm -f /usr/local/bin/t3 /usr/local/bin/t3-pair

mkdir -p "$SHARE_DIR"
install -m 0755 "${FEATURE_DIR}/scripts/entrypoint.sh" "${SHARE_DIR}/entrypoint.sh"
install -m 0755 "${FEATURE_DIR}/scripts/ssh-session" "${SHARE_DIR}/ssh-session"
install -m 0755 "${FEATURE_DIR}/scripts/t3-server" /usr/local/bin/t3-server
install -m 0644 "${FEATURE_DIR}/scripts/ssh-env.sh" "$PROFILE_SCRIPT"
# T3_SERVER_AUTOSTART and T3_SERVER_SSH stay for t3-dev, which reads them:
# the server is not started by the feature, and SSH is always on.
cat >"${SHARE_DIR}/config" <<EOF
# Written by the t3-server dev container feature at image build time.
T3_SERVER_USER='${REMOTE_USER}'
T3_SERVER_USER_HOME='${REMOTE_USER_HOME}'
T3_SERVER_DATA_DIR='${DATA_DIR}'
T3_SERVER_SSH='true'
T3_SERVER_AUTOSTART='false'
EOF
chmod 0644 "${SHARE_DIR}/config"

# The data volume is mounted here. A new named volume takes its ownership and
# mode from this directory, so nothing needs root to use it.
mkdir -p "$DATA_DIR"
chown "${REMOTE_USER}:$(id -gn "$REMOTE_USER")" "$DATA_DIR"
chmod 0700 "$DATA_DIR"

# ~/.t3 is where the app installs the server and where the server keeps its
# data. Pointing it at the volume keeps threads, settings and the downloaded
# server across rebuilds.
t3_home="${REMOTE_USER_HOME}/.t3"
if [ -L "$t3_home" ] || [ ! -e "$t3_home" ]; then
  mkdir -p "$REMOTE_USER_HOME"
  ln -sfn "$DATA_DIR" "$t3_home"
  chown -h "${REMOTE_USER}:$(id -gn "$REMOTE_USER")" "$t3_home"
else
  unsupported "${t3_home} already exists in the image; remove it or the mount that provides it, so the feature can link it to ${DATA_DIR}"
fi

# Only ever used by ssh-session, which is reached through `docker exec`. The
# system sshd configuration is left untouched.
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
SetEnv T3CODE_TELEMETRY_ENABLED=false T3_SERVER_SSH_SESSION=1
EOF
chmod 0644 "${SHARE_DIR}/sshd_config"
# Password-less login through that one sshd only: the system sshd, if any,
# keeps PermitEmptyPasswords at its default of "no".
passwd -d "$REMOTE_USER" >/dev/null

echo "t3-server feature: SSH entry point for '${REMOTE_USER}' installed; the T3 Code app installs the server on first connect"
