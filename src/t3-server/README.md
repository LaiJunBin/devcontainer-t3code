# T3 Code server (`t3-server`)

English | [繁體中文](README.zh-TW.md)

Runs a [T3 Code](https://github.com/pingdotgg/t3code) server inside a dev container, so the T3 Code desktop app can use that container as an environment. Agents then work inside the container, with the isolation the container already gives the project.

The container publishes no port. The desktop app reaches the server over SSH carried by `docker exec`, and reuses the server the feature already started.

This is an unofficial, community feature. It is not affiliated with or supported by the T3 Code maintainers.

## Usage

```jsonc
{
  "features": {
    "ghcr.io/laijunbin/devcontainer-t3code/t3-server:0": {}
  }
}
```

That is the whole project-side change. The dev container needs a non-root `remoteUser`, and a provider CLI (see [Providers](#providers)).

On the machine that runs Docker, give the desktop app's `ssh` a way into the container. For Docker inside WSL with T3 Code on Windows, the [`t3-dev`](../../host/t3-dev) helper in this repository does it ([how to get it](../../README.md#quick-start-windows-docker-in-wsl)):

```bash
t3-dev setup    # once
```

From then on the list of hosts follows your containers by itself. Where the WSL distro has no user-level systemd, run `t3-dev sync` after starting a new project's container.

Then in T3 Code: **Settings → Connections → Add environment → SSH**, and pick `t3-<folder name>`.

For other setups, see [Connecting without the helper](#connecting-without-the-helper).

## Options

| Option      | Default     | Meaning                                                                                              |
| ----------- | ----------- | ---------------------------------------------------------------------------------------------------- |
| `version`   | `0.0.45`    | T3 Code release to install. Must have a pinned hash in `versions.sh`.                                |
| `autostart` | `true`      | Start the server whenever the container starts.                                                      |
| `ssh`       | `true`      | Install the `docker exec`-only SSH entry point. Makes the remote user's password empty (see [Security notes](#security-notes)). |
| `host`      | `127.0.0.1` | Address the server listens on in the container. `0.0.0.0` is only for [publishing the port](#publishing-a-port-instead). |
| `strict`    | `true`      | Fail the build when the image cannot run the feature. `false` skips the feature instead (see [For every dev container](#for-every-dev-container)). |

`T3CODE_PORT` (default `3773`) and `T3CODE_TELEMETRY_ENABLED` (default `false`) can be overridden through the project's `containerEnv`. So can `T3_SERVER_LABEL`, the name T3 Code shows for the environment; by default it is `t3-<project folder>`.

## Commands in the container

| Command                      | Purpose                                                                    |
| ---------------------------- | -------------------------------------------------------------------------- |
| `t3-server status`           | Is it running and answering? Exit code 0 only if both.                     |
| `t3-server start`            | Start it and wait until it answers (up to 60 seconds).                     |
| `t3-server stop` / `restart` | Stop or restart it.                                                        |
| `t3-server logs [-n N]`      | Show the log with pairing secrets removed.                                 |
| `t3-server label`            | Print the name T3 Code shows for this environment.                         |
| `t3-pair [PORT\|ORIGIN]`     | Mint a pairing link; only needed when [publishing a port](#publishing-a-port-instead). |

They can be run as the server's user or as root; root drops to the server's user.

## What the feature does

- **At image build:** downloads the release archive from the official GitHub release, checks it against a SHA-256 pinned in this feature, and installs it to `/opt/t3-server`. Nothing is downloaded when a container starts.
- **Data:** threads, history and pairing state live in a named volume per dev container, mounted at `/var/lib/t3-server` with mode `0700`. `~/.t3` of the remote user links to it.
- **Startup:** the feature's entrypoint starts the server in the background without delaying the container, from `/`, as the remote user, with product telemetry off, listening on loopback.
- **Name:** T3 Code would show the container ID as the environment's name. The feature writes `t3-<folder>` instead, as `PRETTY_HOSTNAME` in `/etc/machine-info`, which T3 Code prefers. The folder is the one mounted at `/workspaces/<folder>`, lowercased, with every character outside `a-z`, `0-9` and `-` replaced by `-`. `t3-dev` names the SSH host from the folder in the same way, so the name you pick when adding the environment is the name it then shows. An existing `/etc/machine-info` that the feature did not write is left alone. `t3-server label` prints the name in use.
- **SSH entry point:** `/usr/local/share/t3-server/ssh-session` serves one SSH session over stdin/stdout. No SSH daemon runs and no port is opened. Its host key is kept in the data volume, and it uses its own configuration file; the image's system SSH configuration is not changed.
- **Reuse by the client:** T3 Code's SSH mode looks in `~/.t3` for a running server and for an installed runtime of its own version. It finds both, so it neither starts a second server nor downloads one.

Why the server is started by the feature and not by the client: a server only serves diffs for directories under the one it was launched from. The client launches from the home directory, which leaves the Diff panel empty for a project under `/workspaces`. The feature launches from `/`.

It does not install or sign in to providers, persist provider logins, update the server, or restart it after a crash.

## Compatibility

### Images

| Requirement  | Detail                                                                                                   |
| ------------ | -------------------------------------------------------------------------------------------------------- |
| C library    | glibc. Alpine and other musl images are rejected at build time, because T3 Code publishes no musl build. |
| Architecture | x64 and arm64, the two Linux builds T3 Code publishes.                                                   |
| User         | A non-root `remoteUser` when `ssh` is on.                                                                |
| Packages     | `curl` or `wget`, `tar`, `gzip`, `sha256sum`, `bash`, CA certificates, `libatomic`, `runuser` or `setpriv`, and for `ssh` an OpenSSH server and `passwd`. |

Missing packages are installed automatically on apt-based images (Debian, Ubuntu) and dnf-based images (Fedora, RHEL family). On anything else the build stops and lists what to add to the base image. Slim images work.

The **Test** workflow in this repository builds a container with the feature and runs the test suite on x64 and arm64 runners, for the images in its matrix and the variants in `test/t3-server/scenarios.json`. Those are the setups known to work; check the latest run before relying on one that is not among them.

The remote user's UID may differ from the one in the image: dev container tools change it to match the host user. The data volume's owner is repaired at container start when the entrypoint runs as root, or through password-less `sudo` otherwise.

### Dev container tools

The server is started by the feature's `entrypoint`, which the Dev Containers specification leaves to each tool to run. VS Code runs it. If `t3-server status` says "not running" right after the container starts, your tool did not; add this to the project:

```jsonc
"postStartCommand": "t3-server start"
```

The command is idempotent, so it is safe to keep even where the entrypoint works.

### T3 Code client versions

The desktop app updates itself; the server in the container only changes when you change the `version` option. A client reuses whatever server is already running, so a newer client talks to the older server through T3 Code's capability negotiation. This feature is tested only with a client of the same version.

## Providers

T3 Code drives provider CLIs that must already be in the container and on the `PATH` the container starts with. For Claude Code, the official feature works:

```jsonc
"features": {
  "ghcr.io/anthropics/devcontainer-features/claude-code:1.0": {},
  "ghcr.io/laijunbin/devcontainer-t3code/t3-server:0": {}
}
```

Sign in inside the container as usual. Whether that login survives a rebuild depends on the project's own mounts; this feature does not touch provider credentials.

## For every dev container

VS Code can add a feature to every dev container you open, without touching any project. In your user settings:

```jsonc
"dev.containers.defaultFeatures": {
  "ghcr.io/laijunbin/devcontainer-t3code/t3-server:0": { "strict": false }
}
```

Keep `"strict": false` here. Applied to every container, the feature will meet images it cannot support: Alpine, a root-only image, one without a package manager. With `strict` off it prints why and installs nothing, and the container builds as it would have without it. A hash mismatch or an unknown `version` still fails the build.

Things to know:

- This is a VS Code setting. The `devcontainer` CLI and other tools ignore it.
- The provider CLI is still the project's or your own business; add its feature to the same setting if you want it everywhere.
- If a project keeps a `devcontainer-lock.json`, VS Code may record your default features in it. Check before committing that file.
- A container picks the feature up the next time it is rebuilt.

## Connecting without the helper

Anything that can run `docker exec` on the Docker host can carry the connection. An SSH client configuration needs one line per container:

```
Host t3-myproject
    User vscode
    ProxyCommand docker exec -i -u root <container> /usr/local/share/t3-server/ssh-session
    PubkeyAuthentication no
```

`User` is the dev container's remote user. On Windows with Docker in WSL, prefix the command with `wsl.exe -d <distro> --`. `t3-dev` writes exactly these entries and resolves the container by its workspace folder, so they survive rebuilds.

## Publishing a port instead

Without SSH, publish the server and pair manually:

```jsonc
"features": { "ghcr.io/laijunbin/devcontainer-t3code/t3-server:0": { "host": "0.0.0.0", "ssh": false } },
"runArgs": ["-p", "127.0.0.1:38101:3773"]
```

Run `t3-pair 38101` in the container and paste the link into **Add environment**. Keep the `127.0.0.1:` prefix, and give every project its own host port. With VS Code on Windows and Docker in WSL, VS Code may take the published port on the Windows side and keep it after its window closes; the SSH route does not have this problem.

## Troubleshooting

| Symptom                                           | Cause and fix                                                                                                                                        |
| ------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| Build fails with `has no pinned hash`             | The requested `version` is not in `versions.sh`. Use a listed version, or add the hashes (see the repository README).                                |
| Build sits at `downloading t3-…` for a long time  | The server archive is about 70 MB and comes from GitHub's release storage, which is sometimes slow. The build log prints `downloaded N MB so far` every 20 seconds; a connection that stops moving is dropped and retried, and the build fails after several tries rather than hanging. It happens once per feature version per project image. |
| Build fails with `hash mismatch`                  | The downloaded archive is not the one this feature pinned. Do not work around it; check the release and report it.                                   |
| Build fails with `does not use glibc`             | The base image is musl-based. Use a glibc image.                                                                                                     |
| Build fails with `needs a non-root remoteUser`    | Set `remoteUser` in `devcontainer.json`, or use `"ssh": false`.                                                                                      |
| Build fails with `~/.t3 already exists`           | Something else provides `~/.t3` (a mount, or files in the image). Remove it; the feature links that path to its own volume.                          |
| `t3-server status`: not running after start       | See [Dev container tools](#dev-container-tools).                                                                                                     |
| `t3-server start`: `is not writable`              | The data volume belongs to another UID and could not be repaired, which needs root or password-less `sudo`. Run `t3-server start` once as root (`docker exec -u root <container> t3-server start`). |
| `t3-dev sync` lists nothing                       | The container is not running, was built without the feature, has `"ssh": false`, or the feature skipped itself (`"strict": false`; the build log says why). |
| SSH: `no running dev container for ...`           | The container stopped. Start it; no re-sync is needed.                                                                                               |
| SSH: host key changed                             | The data volume was recreated. Run `t3-dev sync`, which forgets the old key.                                                                         |
| The Diff panel shows no changes that `git status` shows | A second server, launched by the client from the home directory, is answering. Run `t3-server status`; if the feature's server is not running, start it and reconnect. |
| The environment is named after the container ID   | The project is not mounted under `/workspaces`, or the image has its own `/etc/machine-info`. Set `T3_SERVER_LABEL` in `containerEnv`, then `t3-server restart`. |
| The provider shows as not installed               | Its CLI is not on the server's `PATH`. Run `t3-server restart` after installing it; the server reads `PATH` when it starts.                          |

## Security notes

- **Pinned hashes.** The official installer compares the archive against a checksum file from the same release. This feature compares it against a hash committed in this repository, so a release that is replaced later fails the build instead of installing. There is no option to skip the check.
- **No listening surface.** The server listens on loopback inside the container and nothing is published. Other containers and the host cannot connect to it; the only way in is `docker exec`.
- **Password-less SSH, and why.** The SSH entry point accepts the remote user without a key or password. It is reachable only through `docker exec`, which already grants full access to the container, so a key would not keep anyone out. To make this work the feature empties the remote user's password. The image's system SSH configuration keeps `PermitEmptyPasswords` at its default of `no`, so an SSH daemon you run yourself still refuses that login. Do not point another SSH daemon at `/usr/local/share/t3-server/sshd_config`, and do not publish a port to it.
- **The raw log contains an administrative pairing token** from startup, as text and as a QR code. The file is mode `0600` in the data volume and `t3-server logs` filters all of it out. Do not share the raw file.
- **Default permission mode.** T3 Code starts new threads in Full access. Every environment has its own settings, so change the default in each new one.
- **What the container boundary gives you.** Agents can read everything in the container, including provider logins mounted into it. They cannot reach the host's files or Docker unless the project mounts them.
