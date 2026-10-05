# devcontainer-t3code

English | [繁體中文](README.zh-TW.md)

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

2. Once, in WSL, download the helper from the latest release and let it install itself:

   ```bash
   curl -fsSLO https://github.com/laijunbin/devcontainer-t3code/releases/latest/download/t3-dev
   bash t3-dev setup && rm t3-dev
   ```

   To check the file before running it, see [Verifying a download](#verifying-a-download). From a checkout of this repository, `host/t3-dev setup` does the same. Later, `t3-dev update` fetches a newer release.

3. Start the dev container.

4. In T3 Code: **Settings → Connections → Add environment → SSH**, and pick `t3-<folder name>`.

To skip step 1 for every project, see [For every dev container](src/t3-server/README.md#for-every-dev-container).

Options, compatibility, other setups, troubleshooting and security notes are in the [feature README](src/t3-server/README.md).

## `t3-dev`

| Command         | Does                                                                                                   |
| --------------- | ------------------------------------------------------------------------------------------------------ |
| `t3-dev setup`  | Copies itself to `~/.local/bin`, adds one `Include` line to the Windows user's `.ssh/config` (a copy of the file as it was is kept once, as `config.before-t3`), and installs a user-level systemd service that runs `t3-dev watch`. |
| `t3-dev sync`   | Writes one SSH host per dev container that has the feature, into a file it owns next to that config. A stopped container keeps its host; a removed one loses it. Also names an environment whose feature found no name (see below). |
| `t3-dev watch`  | Runs `sync` whenever a container starts, stops or is removed. This is what the service runs.            |
| `t3-dev list`   | Shows the hosts of running containers: the host, the name T3 Code shows for it once added, and the container ID. `-a` adds stopped containers. The two names are the same unless `T3_SERVER_LABEL` is set or two projects share a folder name. |
| `t3-dev version` | Prints the tool's version. It is numbered separately from the feature; see [Versions](#versions).   |
| `t3-dev update` | Downloads `t3-dev` from the latest release, checks it (see below), shows the old and new version, and replaces itself after you confirm; `--yes` skips the question. Then reruns `setup`. |
| `t3-dev remove` | Stops the service and takes the `Include` line and its own files out again.                            |

It changes nothing else on Windows. `remove` edits the SSH config as it is at that moment and deletes only the line `setup` added, so whatever you or other tools wrote to the file in between is kept; the backup is never copied back.

Without user-level systemd in the WSL distro, `setup` says so and you run `t3-dev sync` yourself after starting a new project's container.

Containers are matched by workspace folder, in either the form VS Code records for WSL folders or the plain Linux form.

Each SSH host is named `t3-<project folder>`, lowercased, with anything outside `a-z`, `0-9` and `-` turned into `-`. That is also what the feature calls the environment by default, so the host you pick in **Add environment** is the name T3 Code then shows. Setting `T3_SERVER_LABEL` changes the name in T3 Code only; the host stays, and with it the environment T3 Code has saved.

A folder keeps the host it was given. Two projects with the same folder name get `t3-<folder>` and `t3-<folder>-2` in the order they were first seen, and neither changes when the other stops or starts. Removing a container, as a rebuild does, takes its host off the list but not away from the folder: the name stays reserved while the folder exists, and the next container of that folder gets it back. Both projects are still called `t3-<folder>` in T3 Code, because each server names itself without knowing about the other; `t3-dev list` points this out, and a `T3_SERVER_LABEL` in one of them tells them apart there.

The feature can only work out the folder's name for a project mounted at `/workspaces/<folder>`. For any other, a Docker Compose project for example, T3 Code would show the container ID. `sync` gives such an environment its host's name, by writing it to `/etc/machine-info` in the container, the file T3 Code reads the name from. The server reads that file when it starts, so `sync` restarts the server if the container started within the last two minutes, when no work can be running yet. A container that has been up longer keeps its server; `t3-dev list` then says so, and the name applies the next time the container starts, or after `t3-server restart` in it. A `/etc/machine-info` the image brought along is left as it is, and so is any environment the feature did name, including one with `T3_SERVER_LABEL`.

### Verifying a download

`t3-dev` never contacts the network on its own; only `update` does, and only when you run it.

Each `t3-dev` release carries `t3-dev`, its SHA-256 in `t3-dev.sha256`, and a GitHub [artifact attestation](https://docs.github.com/en/actions/security-for-github-actions/using-artifact-attestations) for `t3-dev`. They protect against different things:

| Check       | Tells you                                                                                                       | Does not tell you                          |
| ----------- | --------------------------------------------------------------------------------------------------------------- | ------------------------------------------ |
| SHA-256     | The download arrived intact.                                                                                    | Who published it: the hash sits next to the file. |
| Attestation | This exact file was produced by this repository's `release.yaml` workflow, signed through Sigstore and recorded in a public transparency log. A file swapped on the release page afterwards fails it. | That the source it was built from is harmless. Read it; it is one shell script. |

`update` always checks the SHA-256. It checks the attestation too when the [GitHub CLI](https://cli.github.com/) is installed and signed in, and refuses the file if that fails; without the CLI it says that the check was skipped. To check by hand, before the first `setup` for instance:

```bash
gh attestation verify t3-dev --repo laijunbin/devcontainer-t3code \
  --signer-workflow laijunbin/devcontainer-t3code/.github/workflows/release.yaml
```

## Versions

The feature and `t3-dev` are versioned and released separately, because updating them costs very different amounts:

| Part      | Version is in                             | Released as                                                                  | You get it by                                              |
| --------- | ----------------------------------------- | ---------------------------------------------------------------------------- | ---------------------------------------------------------- |
| Feature   | `src/t3-server/devcontainer-feature.json` | `ghcr.io/laijunbin/devcontainer-t3code/t3-server:<version>`, git tag `feature_t3-server_<version>` | rebuilding the dev container, which downloads the server (about 70 MB) again |
| `t3-dev`  | `T3_DEV_VERSION` in `host/t3-dev`         | GitHub release and git tag `t3-dev-v<version>`                               | `t3-dev update`, a few seconds                             |

Any `t3-dev` works with any feature version; neither has to be updated because the other was. One thing depends on the feature's version: from feature 0.3.1 on, the environment is called `t3-<folder>` in T3 Code, like its host. With an older feature in a container, T3 Code shows the container ID, and so does `t3-dev list`.

## Support

Maintained on a best-effort basis. What is known to work is what the **Test** workflow builds and tests, on x64 and arm64: the images in its matrix and the variants in `test/t3-server/scenarios.json`. `t3-dev` is exercised by hand on Windows 11 with Docker in WSL 2. Reports for other setups are welcome, with the image name and the output; fixes may or may not follow.

## Maintaining

### Supporting a new T3 Code version

1. Download `t3-<version>-linux-x64.tar.gz` and `t3-<version>-linux-arm64.tar.gz` from the official release page.
2. Run `sha256sum` on both and add the two lines to `src/t3-server/versions.sh`. Compute the hashes yourself; do not copy them from the release's `SHA256SUMS`, which is what the pin is meant to be independent of.
3. Update the default and `proposals` of the `version` option, the version in `test/t3-server/test.sh`, and bump the feature's own `version` in `devcontainer-feature.json`. `t3-dev` does not change.
4. Push, wait for the **Test** workflow to pass, then run the **Release** workflow.

### Workflows

| Workflow    | Trigger                     | Does                                                                                                                      |
| ----------- | --------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| **Test**    | every push and pull request, except ones that only change documentation | `shellcheck`, then builds a container with the feature per image and architecture and runs `test/t3-server/test.sh` in it |
| **Release** | manual, from `main` only    | for whichever of the two has a version without a tag yet: publishes the feature to `ghcr.io/<owner>/<repo>/<feature>` and tags it, and creates the GitHub release `t3-dev-v<version>` with `t3-dev`, its checksum and its attestation |

Third-party actions are pinned to commit SHAs. Releasing is manual so that what is published only changes on purpose. Only the release's second job can write to the repository.

To release, bump the version of the part that changed and run **Release**. A part whose version is already tagged is skipped, so releasing `t3-dev` alone does not make projects download the server again. If a part's files changed but its version did not, the workflow stops and says which one to bump, instead of skipping it or publishing new content under a used number. A change to only the documentation in the feature's folder does not count.

Turn on **Settings → General → Releases → Enable release immutability** in the repository. GitHub then locks each release's tag and files once it is published, so not even the owner's account can swap them later.

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
  README.md                   user documentation (README.zh-TW.md: Traditional Chinese)
host/t3-dev                   host-side helper (WSL)
test/t3-server/test.sh        checks run by `devcontainer features test`
test/t3-server/scenarios.json other images and option sets to run them on
```
