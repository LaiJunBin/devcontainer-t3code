# devcontainer-t3code

Use a dev container as a [T3 Code](https://github.com/pingdotgg/t3code) environment: agents run inside the container, and the T3 Code desktop app drives them. The container publishes no port.

Unofficial; not affiliated with or supported by the T3 Code maintainers.

Two parts:

| Part                                   | Where it runs        | What it does                                                                                   |
| -------------------------------------- | -------------------- | ---------------------------------------------------------------------------------------------- |
| [`t3-server`](src/t3-server/README.md) | in the dev container | A dev container feature: installs a hash-verified T3 Code server, starts it, and offers an SSH entry point that is only reachable through `docker exec`. |
| [`t3-dev`](host/t3-dev)                | on the Docker host   | Registers each such container as an SSH host for the desktop app. Written for Docker inside WSL with T3 Code on Windows. |

## Quick start (Windows, Docker in WSL)

1. Add the feature to the project's `devcontainer.json`:

   ```jsonc
   "features": {
     "ghcr.io/laijunbin/devcontainer-t3code/t3-server:0": {}
   }
   ```

2. Once, in WSL, from a checkout of this repository:

   ```bash
   host/t3-dev setup
   ```

3. Start the dev container.

4. In T3 Code: **Settings → Connections → Add environment → SSH**, and pick `t3-<folder name>`.

To skip step 1 for every project, see [For every dev container](src/t3-server/README.md#for-every-dev-container).

Options, compatibility, other setups, troubleshooting and security notes are in the [feature README](src/t3-server/README.md).

## `t3-dev`

| Command         | Does                                                                                                   |
| --------------- | ------------------------------------------------------------------------------------------------------ |
| `t3-dev setup`  | Copies itself to `~/.local/bin`, adds one `Include` line to the Windows user's `.ssh/config` (a copy of the file as it was is kept once, as `config.before-t3`), and installs a user-level systemd service that runs `t3-dev watch`. |
| `t3-dev sync`   | Writes one SSH host per running dev container that has the feature, into a file it owns next to that config. Hosts of stopped containers stay listed while their folder exists. |
| `t3-dev watch`  | Runs `sync` whenever a container starts or stops. This is what the service runs.                       |
| `t3-dev list`   | Shows the hosts and whether each one's container is running.                                           |
| `t3-dev remove` | Stops the service and takes the `Include` line and its own files out again.                            |

It changes nothing else on Windows. `remove` edits the SSH config as it is at that moment and deletes only the line `setup` added, so whatever you or other tools wrote to the file in between is kept; the backup is never copied back.

Without user-level systemd in the WSL distro, `setup` says so and you run `t3-dev sync` yourself after starting a new project's container.

Containers are matched by workspace folder, in either the form VS Code records for WSL folders or the plain Linux form.

## Support

Maintained on a best-effort basis. What is known to work is what the **Test** workflow builds and tests: the images in its matrix, on x64 and arm64. `t3-dev` is exercised by hand on Windows 11 with Docker in WSL 2. Reports for other setups are welcome, with the image name and the output; fixes may or may not follow.

## Maintaining

### Supporting a new T3 Code version

1. Download `t3-<version>-linux-x64.tar.gz` and `t3-<version>-linux-arm64.tar.gz` from the official release page.
2. Run `sha256sum` on both and add the two lines to `src/t3-server/versions.sh`. Compute the hashes yourself; do not copy them from the release's `SHA256SUMS`, which is what the pin is meant to be independent of.
3. Update the default and `proposals` of the `version` option, the version in `test/t3-server/test.sh`, and bump the feature's own `version` in `devcontainer-feature.json`.
4. Push, wait for the **Test** workflow to pass, then run the **Release** workflow.

### Workflows

| Workflow    | Trigger                     | Does                                                                                                                      |
| ----------- | --------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| **Test**    | every push and pull request | `shellcheck`, then builds a container with the feature per image and architecture and runs `test/t3-server/test.sh` in it |
| **Release** | manual, from `main` only    | publishes `src/*` to `ghcr.io/<owner>/<repo>/<feature>`                                                                   |

Third-party actions are pinned to commit SHAs. Releasing is manual so that the published feature only changes on purpose.

The first release creates a private package. Open the package's settings on GitHub and set its visibility to public.

### Layout

```
src/t3-server/
  devcontainer-feature.json   metadata, options, volume, entrypoint
  install.sh                  build-time install (runs as root)
  versions.sh                 pinned archive hashes
  scripts/entrypoint.sh       starts the server when the container starts
  scripts/t3-server           status / start / stop / restart / logs
  scripts/ssh-session         one SSH session over docker exec
  scripts/t3-pair             pairing link helper, for the published-port setup
  README.md                   user documentation
host/t3-dev                   host-side helper (WSL)
test/t3-server/test.sh        checks run by `devcontainer features test`
```
