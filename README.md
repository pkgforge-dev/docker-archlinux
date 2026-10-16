# docker-archlinux

Multi-platform container images of Arch Linux and its ports, built each day from the signed packages of each distribution.

[![all](https://pkgforge-dev.github.io/docker-archlinux/badges/all.svg)](https://pkgforge-dev.github.io/docker-archlinux/)
[![latest](https://pkgforge-dev.github.io/docker-archlinux/badges/latest.svg)](https://pkgforge-dev.github.io/docker-archlinux/)
[![registries](https://pkgforge-dev.github.io/docker-archlinux/badges/registries.svg)](https://pkgforge-dev.github.io/docker-archlinux/)
[![build](https://pkgforge-dev.github.io/docker-archlinux/badges/build.svg)](https://pkgforge-dev.github.io/docker-archlinux/)
[![amd64](https://pkgforge-dev.github.io/docker-archlinux/badges/amd64.svg)](https://pkgforge-dev.github.io/docker-archlinux/)
[![arm64](https://pkgforge-dev.github.io/docker-archlinux/badges/arm64.svg)](https://pkgforge-dev.github.io/docker-archlinux/)
[![armv7](https://pkgforge-dev.github.io/docker-archlinux/badges/armv7.svg)](https://pkgforge-dev.github.io/docker-archlinux/)
[![loong64](https://pkgforge-dev.github.io/docker-archlinux/badges/loong64.svg)](https://pkgforge-dev.github.io/docker-archlinux/)
[![ppc](https://pkgforge-dev.github.io/docker-archlinux/badges/ppc.svg)](https://pkgforge-dev.github.io/docker-archlinux/)
[![ppc64](https://pkgforge-dev.github.io/docker-archlinux/badges/ppc64.svg)](https://pkgforge-dev.github.io/docker-archlinux/)
[![ppc64le](https://pkgforge-dev.github.io/docker-archlinux/badges/ppc64le.svg)](https://pkgforge-dev.github.io/docker-archlinux/)
[![riscv64](https://pkgforge-dev.github.io/docker-archlinux/badges/riscv64.svg)](https://pkgforge-dev.github.io/docker-archlinux/)

![Image age per port, against the build interval](https://pkgforge-dev.github.io/docker-archlinux/charts/freshness.svg)

![Compressed and installed size per port](https://pkgforge-dev.github.io/docker-archlinux/charts/size.svg)

![Tags per port on GHCR and on Docker Hub](https://pkgforge-dev.github.io/docker-archlinux/charts/coverage.svg)

The status site is at <https://pkgforge-dev.github.io/docker-archlinux/>. It shows each port, the registries, the last builds and the history of the last 30 days. A badge shows the state at the last status run, which runs each hour.

## Architectures

The table comes from `ports/*.conf` (`scripts/ports json`).

| port | platform | tags | distribution |
| --- | --- | --- | --- |
| `amd64` | `linux/amd64` | `x86_64`, `amd64` | [Arch Linux](https://archlinux.org) |
| `arm64` | `linux/arm64` | `aarch64`, `arm64` | [Arch Linux ARM](https://archlinuxarm.org) |
| `armv7` | `linux/arm/v7` | `armv7l`, `armv7h`, `armv7` | [Arch Linux ARM](https://archlinuxarm.org) |
| `loong64` | `linux/loong64` | `loongarch64`, `loong64` | [Arch Linux for Loong64 (LCPU)](https://loongarchlinux.lcpu.dev) |
| `ppc` | `linux/ppc` | `ppc`, `powerpc` | [ArchPOWER](https://archlinuxpower.org) |
| `ppc64` | `linux/ppc64` | `ppc64`, `powerpc64` | [ArchPOWER](https://archlinuxpower.org) |
| `ppc64le` | `linux/ppc64le` | `ppc64le`, `powerpc64le` | [ArchPOWER](https://archlinuxpower.org) |
| `riscv64` | `linux/riscv64` | `riscv64` | [Arch Linux RISC-V](https://archriscv.felixc.at) |

The first tag of a port is its `uname -m` name. All tags of a port name one manifest.

## Registries

The same images are on two registries, under two organisation names:

```text
ghcr.io/pkgforge-dev/archlinux
docker.io/pkgforge/archlinux
```

GHCR is the source. Docker Hub gets a copy of each GHCR tag, by digest.

## Usage

```bash
# A shell in the image of the host platform.
docker run --rm -it ghcr.io/pkgforge-dev/archlinux:latest

# The same image from Docker Hub.
docker run --rm -it docker.io/pkgforge/archlinux:latest

# Another platform, under emulation. The host needs a user mode emulator in binfmt_misc.
docker run --rm -it --platform=linux/arm64 ghcr.io/pkgforge-dev/archlinux:aarch64
```

⚠ A tag of one port is an index with one platform. A pull of a foreign platform needs `--platform`. With no `--platform`, the runtime looks for the host platform and finds nothing.

[examples/](examples/) has more.

## Tags

| tag | names | moves |
| --- | --- | --- |
| `latest` | an index over every published platform | each build |
| `v<YYYY.MM.DD>` | an index, made by the first publish of that UTC day that built a port | never |
| `<tag>` | one platform, the newest image | each build |
| `<tag>-v<YYYY.MM.DD>` | one platform, the first image of that day | never |
| `<tag>-<anchor>` | one platform, the first image with that pacman version | never |

`<tag>` is a name from the column `tags` above. `<anchor>` is the version of the `pacman` package in the image. No port publishes a release version, so pacman names the package set. Each port has its own anchor, because the ports differ in `pkgrel`.

⛔ A tag that never moves is made once, by the first build that names it. A second build on the same day, or with the same pacman version, moves `latest` and `<tag>` only.

⚠ A port that does not build on a day keeps its last image in `latest` and in that day's `v<YYYY.MM.DD>`. Its own `<tag>-v<YYYY.MM.DD>` for that day does not exist. An issue with the label `automation` names the port while it does not publish.

```bash
# When this image was built. This reads the registry, so no pull is necessary.
docker buildx imagetools inspect ghcr.io/pkgforge-dev/archlinux:riscv64 \
  --format '{{ index .Image.Config.Labels "org.opencontainers.image.created" }}'

# The anchor of an image.
docker run --rm ghcr.io/pkgforge-dev/archlinux:x86_64 pacman -Q pacman

# Pin by digest.
docker buildx imagetools inspect ghcr.io/pkgforge-dev/archlinux:latest --format '{{ .Manifest.Digest }}'
```

⚠ A git tag of this repository (`vX.Y.Z`) is a version of the tooling and of the release assets. It is not an image version.

## Mirrors

The first server of each mirror list of each port is the [GHCR mirror](https://github.com/pkgforge-dev/mirror-archlinux). That includes both lists of the PowerPC ports, `mirrorlist` for `[base]` and `mirrorlist-any` for `[base-any]`. The mirror serves upstream's own databases and packages, with upstream's signatures, from GitHub's package storage. The upstream servers follow it in the same list.

```ini
Server = https://ghcr.mirror.archlinux.pkgforge.dev/$arch/$repo
```

| case | result |
| --- | --- |
| a transfer from the mirror fails | pacman tries the next `Server` |
| the mirror is behind upstream by more than 12 hours | the build reads the list without each path to the mirror, for that build. The image still ships the mirror |
| the Worker of the mirror does not answer | the build stage reads the same mirror from the registry, through `pacman-oci`. ⛔ The image never ships that path |
| signatures | `SigLevel = Required`. Each package has upstream's own signature |

To use only the upstream servers, delete the mirror from each list:

```bash
sed -i '/ghcr\.mirror\.archlinux\.pkgforge\.dev/d' /etc/pacman.d/mirrorlist*
```

The build generates each list from the reviewed anchors in `mirrors/` and a ranked pool. [docs/design.md](docs/design.md#mirrors) gives the rules.

## What the image contains

- **Every file of each package.** There is no `NoExtract` rule. Man pages, documentation, info pages and every locale are on disk. Each path that `pacman -Ql` lists is on disk, but one. ⚠ `/var/lock` is a link to `../run/lock`, which systemd makes. In a container the link has no target.
- **Signature checks.** `SigLevel = Required DatabaseOptional`. The keyring is populated. The image has no local signing key, so run `pacman-key --init` before `pacman-key --lsign-key`.
- **No package cache and no sync databases.** Install with `pacman -Syu --noconfirm --needed PACKAGE`. ⚠ `pacman -Sy PACKAGE` is a partial upgrade: the new package can need a newer library than the image has.
- **An empty `/etc/machine-id`.** Each container writes its own ID.
- **The PATH of the official image.** A pacman hook links each executable of the perl directories (`/usr/bin/vendor_perl`, `/usr/bin/site_perl`, `/usr/bin/core_perl`) into `/usr/local/bin`. ⛔ It never links a name that already resolves.
- **The locale `en_US.UTF-8`.** `LANG`, `LC_ALL` and `LANGUAGE` are set. `LC_ALL` overrides `LANG`, and `LANGUAGE` overrides `LC_ALL` for messages, so set all three.

```bash
# Add a locale.
echo "de_DE.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen

# Use it for one container.
docker run --rm -it -e LANG=de_DE.UTF-8 -e LC_ALL=de_DE.UTF-8 -e LANGUAGE=de ghcr.io/pkgforge-dev/archlinux:latest

# Remove the linker hook and its links.
rm /etc/pacman.d/hooks/bindir-links.hook
find /usr/local/bin -lname '/usr/bin/*_perl/*' -delete
```

## Provenance and evidence

Each image has a build provenance attestation and an SBOM. The labels `org.opencontainers.image.version`, `.revision` and `.created` record the version, the source commit and the build time of the image. `/etc/os-release` records the version only, as `VERSION_ID` and `IMAGE_VERSION`.

Each build writes an evidence file for each platform: each package, its version, its download and installed size, its sha256 and its build date. The build uploads it as the artifact `evidence-<arch>`, and the status site keeps the newest one at `https://pkgforge-dev.github.io/docker-archlinux/evidence/<arch>.json`.

```bash
docker buildx imagetools inspect ghcr.io/pkgforge-dev/archlinux:latest --format '{{ json .Provenance }}'
curl -sSfL --connect-timeout 15 --max-time 120 https://pkgforge-dev.github.io/docker-archlinux/evidence/amd64.json | jq '.packages | length'
```

## Release assets

A release is made on the first day of each month, and for each pushed `vX.Y.Z` tag. It carries the images as plain files, for a consumer with no container runtime.

| asset | is |
| --- | --- |
| `rootfs-<arch>.tar.gz` | the file system of the published image, `docker export`, gzip. Untar it and use `chroot`, or `podman import` it |
| `oci-<arch>.tar.gz` | the same image with its metadata, for `podman load` with no network |
| `rootfs-<arch>.json` | the evidence file of that image |
| `bootstrap-set-<arch>.txt` | the package set as `name version sha256` |
| `pacman-static-<arch>` | a static pacman, and its evidence file `pacman-static-<arch>.json` |
| `manifest.json` | each published tag, with its digest, platforms and anchor |
| `SHA256SUMS` | each asset but itself |

⚠ A port with no published image is left out of the release, and the release notes name it.

⚠ Only `releases/latest/download/<asset>` has a URL that does not change. A rootfs tarball dates itself in `/etc/os-release`. Its source commit and build time are `source_commit` and `built` in `rootfs-<arch>.json`: the revision and created labels of the image.

```bash
curl -sSfL --connect-timeout 15 --max-time 120 \
  https://github.com/pkgforge-dev/docker-archlinux/releases/latest/download/manifest.json \
  | jq -r '.tags[] | select(.anchor) | "\(.tag) \(.digest)"'
```

## Static pacman

`pacman-static-<arch>` is pacman linked statically against musl. It needs no libc, no libalpm and no Arch keyring on the host, so it can build an Arch root on any Linux host. Each input is pinned by sha256 or by commit in `bootstrap/pacman-static/sources.pin`. pacman is pinned at the commit of the pacman in the images.

Get it from a release, and check it:

```bash
base=https://github.com/pkgforge-dev/docker-archlinux/releases/latest/download
for f in pacman-static-amd64 pacman-static-amd64.json SHA256SUMS; do
  curl -sSfL --connect-timeout 15 --max-time 300 -o "$f" "$base/$f"
done
sha256sum -c --ignore-missing SHA256SUMS
scripts/build-pacman-static --check-evidence pacman-static-amd64.json
```

Or build it from the pin:

```bash
WORK=/tmp/pacman-static scripts/build-pacman-static --fetch
WORK=/tmp/pacman-static OUT=/tmp/dist scripts/build-pacman-static amd64
```

[docs/bootstrap-with-pacman-static.md](docs/bootstrap-with-pacman-static.md) tells how to build a root with it.

## Build and test

```bash
# Build one port.
docker build --platform linux/amd64 --build-arg IMAGE_VERSION="$(date -u +%Y.%m.%d)" -t archlinux:amd64 .

# The static suite, with the pinned tools.
scripts/install-tools /tmp/tools
PATH="/tmp/tools:$PATH" TESTS_REQUIRE_TOOLS=1 tests/run.sh -j 4 static

# The image suite, against a published image. The evidence takes the commit
# and the build time from the labels of the image.
scripts/gen-evidence amd64 ghcr.io/pkgforge-dev/archlinux:x86_64 linux/amd64 /tmp/evidence-amd64.json
IMAGE=ghcr.io/pkgforge-dev/archlinux:x86_64 PLATFORM=linux/amd64 EVIDENCE=/tmp/evidence-amd64.json tests/run.sh image
```

`IMAGE_VERSION` is required: an image that does not record its version cannot be tagged by it. [docs/tests.md](docs/tests.md) tells what each test checks, and how to test a local build.

## Documents

| document | contents |
| --- | --- |
| [docs/design.md](docs/design.md) | the invariants, the rules, the port table, the build and publish topology, the tags, the mirrors, the trust roots, the image |
| [docs/operations.md](docs/operations.md) | the workflows, the schedules, the issues, what needs a person, settings, secrets, recovery |
| [docs/measurements.md](docs/measurements.md) | measured facts, each with its date and source |
| [docs/tests.md](docs/tests.md) | the suites, each test file, how to run them, the tests seen to fail |
| [docs/conventions.md](docs/conventions.md) | the code, workflow, test and text conventions |
| [docs/bootstrap-with-pacman-static.md](docs/bootstrap-with-pacman-static.md) | a root built with the static pacman |
| [examples/](examples/README.md) | commands for consumers |
| [THIRD-PARTY.md](THIRD-PARTY.md) | the licences of what the release assets and the tree carry from other projects |

The history before the rewrite is on the branch [history-archive](https://github.com/pkgforge-dev/docker-archlinux/tree/history-archive).

## Licence

MIT, [LICENSE](LICENSE).
