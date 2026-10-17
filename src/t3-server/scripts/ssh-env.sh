# shellcheck shell=sh
# Installed as /etc/profile.d/t3-server-ssh-env.sh by the t3-server dev
# container feature. Sourced by login shells.
#
# An SSH login starts from a clean environment, and /etc/profile then resets
# PATH. The T3 Code app starts its server from such a login shell, so without
# this the server would miss what the container's own processes see: tools
# that features put on PATH, and variables such as CLAUDE_CONFIG_DIR.
# ssh-session saves the container's environment for each session; this puts
# it back. Only in sessions of that sshd, which sets T3_SERVER_SSH_SESSION.
if [ -n "${T3_SERVER_SSH_SESSION:-}" ] && [ -r /run/t3-server/session-env ]; then
  # shellcheck source=/dev/null
  . /run/t3-server/session-env
fi
