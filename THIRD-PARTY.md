# Third-party software

The code of this repository is MIT ([LICENSE](LICENSE)). The release assets and some files of the tree carry software of other projects, under their own licences. This file names them.

## The static pacman (`pacman-static-<arch>`)

Each `pacman-static-<arch>` release asset is one binary that links the projects below statically. `bootstrap/pacman-static/sources.pin` pins the exact source of each, by URL and sha256, or by commit. `pacman-static-<arch>.json` beside the binary records the same sources.

| project | version | licence of the Arch Linux package |
| --- | --- | --- |
| pacman (libalpm) | commit `54d94116164b0b2202c6061c4a59c6f3e70820d8` | GPL-2.0-or-later |
| zlib | 1.3.2 | Zlib |
| xz (liblzma) | 5.8.3 | GPL-2.0-or-later AND 0BSD AND LicenseRef-Public-Domain AND LGPL-2.1-or-later |
| bzip2 (libbz2) | 1.0.8 | BSD |
| zstd (libzstd) | 1.5.7 | BSD-3-Clause, GPL-2.0-only |
| OpenSSL | 3.5.8 | Apache-2.0 |
| libarchive | 3.8.9 | BSD-2-Clause, BSD-4-Clause-UC, Apache-2.0 OR CC0-1.0 OR OpenSSL |
| curl (libcurl) | 8.21.0 | curl |
| libgpg-error | 1.61 | LGPL-2.1-or-later, BSD-3-Clause OR LGPL-2.1-or-later, FSFULLR, GPL-2.0-or-later |
| libassuan | 3.0.2 | FSFULLR, GPL-2.0-or-later, LGPL-2.1-or-later |
| gpgme | 2.1.2 | GPL-2.0-or-later, LGPL-2.0-or-later, LGPL-2.1-or-later, MIT |
| libseccomp | 2.6.1 | LGPL-2.1-only |
| musl libc, from zig | zig 0.16.0 | MIT |

⚠ The licence column is the `%LICENSE%` field of the Arch Linux package of each project ([measurements.md](docs/measurements.md#the-static-pacman)). That field covers the whole package, tools included. The licence files in each pinned source tarball are the authority.

The binary as a whole is distributed under GPL-3.0-or-later. pacman is GPL-2.0-or-later. OpenSSL 3 is Apache-2.0, which is compatible with GPLv3 and not with GPLv2. The "or later" grant of pacman allows GPLv3.

### The source offer

The complete source of each binary is the set of inputs that `bootstrap/pacman-static/sources.pin` names:

- each tarball, at its URL, with its sha256
- pacman, at its commit, from `https://gitlab.archlinux.org/pacman/pacman.git`
- the build script `scripts/build-pacman-static`, of the same commit of this repository

The release does not carry the source tarballs. This command downloads every pinned source and checks each sha256:

```bash
WORK=/tmp/pacman-static scripts/build-pacman-static --fetch
```

## The images and the rootfs assets

The images, `rootfs-<arch>.tar.gz` and `oci-<arch>.tar.gz` hold the packages of the upstream distribution of each port, unchanged. Each package has its own licence, in `/usr/share/licenses/<package>/` and in the `%LICENSE%` field that `pacman -Qi` shows. The source of each package is with its distribution:

| distribution | sources |
| --- | --- |
| Arch Linux | <https://gitlab.archlinux.org/archlinux/packaging/packages> |
| Arch Linux ARM | <https://github.com/archlinuxarm/PKGBUILDs> |
| Arch Linux for Loong64 (LCPU) | <https://github.com/lcpu-club/loongarch-packages> |
| Arch Linux RISC-V | <https://github.com/felixonmars/archriscv-packages> |
| ArchPOWER | <https://github.com/kth5/archpower> |

## Files of the tree

| file | from | licence |
| --- | --- | --- |
| `bootstrap/any/usr/local/bin/pacman-oci` | `pkgforge-dev/mirror-archlinux`, `client/pacman-oci`, at the commit in `bootstrap/pacman-oci.pin` | MIT |
| `bootstrap/keyrings/archlinuxarm-keyring-*.pkg.tar.*` | Arch Linux ARM, unchanged | GPL (the `license` field of the package) |
| `bootstrap/keyrings/archlinux-lcpu-keyring-*.pkg.tar.*` | Arch Linux for Loong64 (LCPU), unchanged | GPL-3.0-or-later (the `license` field of the package) |
| `bootstrap/keyrings/archpower-keyring-*.pkg.tar.*` | ArchPOWER, unchanged | GPL (the `license` field of the package) |
| `bootstrap/pacman-static/keys/*.asc` | the public keys of the pacman release signers, exported from a keyserver | public key data |
| `tests/fixtures/61-vercmp/vectors.tsv`, the first block | pacman, `test/util/vercmptest.sh`: the version pairs and their results, as test data | GPL-2.0-or-later |
