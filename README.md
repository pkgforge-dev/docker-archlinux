- #### [Docker images of Arch Linux](https://hub.docker.com/r/pkgforge/archlinux/tags) [![Build and Deploy](https://github.com/pkgforge-dev/docker-archlinux/actions/workflows/build-deploy.yml/badge.svg)](https://github.com/pkgforge-dev/docker-archlinux/actions/workflows/build-deploy.yml)

Unofficial, automated Docker multi-platform images of Arch Linux for the following architectures:

| Architecture | Docker Platform | Distribution |
| ------------ | --------------- | ------------ |
| x86_64 | `linux/amd64` | [Arch Linux](https://archlinux.org) |
| aarch64 | `linux/arm64` | [Arch Linux ARM](https://archlinuxarm.org) |
| armv7h | `linux/arm/v7` | [Arch Linux ARM](https://archlinuxarm.org) |
| riscv64 | `linux/riscv64` | [Arch Linux RISC-V](https://archriscv.felixc.at) |

- #### Registries

The same images are published to two registries under two organisation names.
Both are live and both stay working.

```bash
ghcr.io/pkgforge-dev/archlinux
docker.io/pkgforge/archlinux
```

- #### Usage

```bash
# --rm deletes the container on exit
# --net=host and --privileged are not required, but --privileged often works
#   around host DNS and networking problems
# --platform runs another architecture under QEMU, for example
#   --platform=linux/arm64 runs the aarch64 image on an x86_64 host

# drops you in a bash shell
docker run --rm -it docker.io/pkgforge/archlinux:latest

# the same image from GHCR
docker run --rm -it ghcr.io/pkgforge-dev/archlinux:latest

# a specific architecture, under emulation
docker run --rm -it --platform=linux/arm64 docker.io/pkgforge/archlinux:aarch64
```

More in [`examples/`](examples/).

- #### Tags

Five families. `latest` and `v<date>` are multi-architecture indexes. The other
three name one architecture each.

| tag | resolves to | moves |
| --- | --- | --- |
| `latest` | an index over all four platforms | every build |
| `v2026.08.26` | an index over all four platforms, that day's build | never |
| `x86_64` | one platform, newest | every build |
| `x86_64-v2026.08.26` | one platform, that day's build | never |
| `x86_64-7.1.0.r9.g54d9411-2` | one platform, that `pacman` version | never |

Each architecture answers to more than one spelling. The names share one
manifest, so `x86_64` and `amd64` are two names for one digest.

| Docker platform | tag names |
| --- | --- |
| `linux/amd64` | `x86_64`, `amd64` |
| `linux/arm64` | `aarch64`, `arm64` |
| `linux/arm/v7` | `armv7l`, `armv7h`, `armv7` |
| `linux/riscv64` | `riscv64` |

The `uname -m` spellings follow the sibling images in the organisation. ⚠ The
Docker platform spellings (`amd64`, `arm64`, `armv7`) are this repository's
extension and are not an organisation convention.

⚠ A single-architecture tag still records its platform, so pulling one for a
foreign architecture needs `--platform`. Without it the runtime looks for the
host architecture and finds nothing:

```bash
docker pull ghcr.io/pkgforge-dev/archlinux:aarch64
# no image found in image index for architecture "amd64", variant "", OS "linux"

docker pull --platform=linux/arm64 ghcr.io/pkgforge-dev/archlinux:aarch64
```

- #### What the pinned tag is pinned to

`x86_64-7.1.0.r9.g54d9411-2` names the version of `pacman` that image contains.

Arch is rolling. No port publishes a `VERSION_ID`, so there is no distribution
version to name a tag after. `pacman` is used because it exists on every port
and its version already carries the upstream tag, the commits since it, and the
commit hash it was built from.

⚠ The ports are not in lockstep and `pacman` has differed by `pkgrel` between
them, so the anchor is resolved per architecture. Two architectures can carry
different anchor versions in the same build, and the index tags cover both.

```bash
# what an image is anchored on
docker run --rm docker.io/pkgforge/archlinux:x86_64 pacman -Q pacman
```

- #### What is not in the image, and how to get it back

Man pages, info pages, documentation and non-English locales are not extracted.
The packages are installed as normal and pacman still records every file, so
nothing is missing from the package database and every path is restorable.

The rules are the `NoExtract` lines in `/etc/pacman.conf`, and they are the set
official Arch uses.

| path | removed |
| --- | --- |
| `usr/share/man`, `usr/share/info` | yes |
| `usr/share/doc`, `usr/share/gtk-doc/html`, `usr/share/help` | yes, except English |
| `usr/share/locale`, `usr/share/i18n`, `usr/share/X11/locale` | yes, except English, the base charmaps and `C` |

Two commands restore any of it: comment out the rule, then reinstall.

```bash
# man and info pages
sed -i 's|^NoExtract  = usr/share/man|#&|' /etc/pacman.conf
pacman -Syu --noconfirm $(pacman -Qq)
```

```bash
# documentation
sed -i 's|^NoExtract  = usr/share/gtk-doc|#&|' /etc/pacman.conf
pacman -Syu --noconfirm $(pacman -Qq)
```

⚠ Adding a non-English locale needs the same step first. `locale-gen` reads its
source data from `/usr/share/i18n/locales`, which is not extracted, and it
reports `Generation complete` even when it generated nothing.

```bash
sed -i 's|^NoExtract  = usr/share/locale|#&|' /etc/pacman.conf
pacman -Sy --noconfirm glibc
echo "de_DE.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
```

⚠ The image sets `LANG`, `LC_ALL` and `LANGUAGE`, and they do not have equal
weight. `LC_ALL` beats `LANG`, and `LANGUAGE` beats `LC_ALL` for translated
messages. Setting `LANG` alone changes nothing here. Override all three.

```bash
docker run --rm -it -e LANG=de_DE.UTF-8 -e LC_ALL=de_DE.UTF-8 -e LANGUAGE=de ghcr.io/pkgforge-dev/archlinux:latest
```

[`examples/04-add-a-locale.sh`](examples/04-add-a-locale.sh) shows both.

- #### Provenance

Every image carries a build provenance attestation and an SBOM. Each build also
publishes an evidence file per platform recording every package, its version,
its download size, its sha256 and its build date.

```bash
docker buildx imagetools inspect docker.io/pkgforge/archlinux:latest --format '{{ json .Provenance }}'
```

See [`examples/`](examples/) for consuming the evidence file.

- #### Building and testing

```bash
docker build --platform linux/amd64 --build-arg IMAGE_VERSION="$(date -u +%Y.%m.%d)" -t archlinux:amd64 .
tests/run.sh static
IMAGE=archlinux:amd64 PLATFORM=linux/amd64 tests/run.sh image
```

`IMAGE_VERSION` is required. An image that does not record its version cannot be
tagged by it. [`tests/README.md`](tests/README.md) lists what every test asserts.
