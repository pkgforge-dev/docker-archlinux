# A static pacman, built here, for every architecture

Added 2026-08-28. `scripts/build-pacman-static` links `pacman` against musl for
all eight architectures, from source, with every input pinned.

## Why

The trust root of an image build is one container image plus working mirrors.
This removes the first. With this binary and a keyring pin, a root can be built
on a host that has no `pacman`, no `libalpm` and no Arch keyring, which is what
policy 8 means by bootstrappable.

⛔ Built here, never downloaded. Policy 5 forbids an opaque binary fetched at
build time, and a static bootstrap binary is the last thing that should arrive
unverified. `tests/static/85-pacman-static-pin.sh` fails if the `Dockerfile` or
anything under `bootstrap/any` ever names it.

## What is pinned, and how

`bootstrap/pacman-static/sources.pin`. Every hash was measured by fetching the
URL beside it on 2026-08-28, not copied from an upstream checksum file.

| kind | pinned by | count |
| --- | --- | --- |
| the toolchain | sha256, one tarball per host architecture | 2 |
| the dependency stack | sha256 per release tarball | 11 |
| pacman | a 40 character commit | 1 |

⭐ The commit is `54d94116164b0b2202c6061c4a59c6f3e70820d8`, which is the one
every image this repository publishes is built from. The anchor tag family is
`<alias>-7.1.0.r9.g54d9411-<pkgrel>` and `g54d9411` is that commit abbreviated,
so the binary and the image's own `pacman` come from one source.
`tests/static/85-pacman-static-pin.sh` asserts the two strings agree without
touching the network, and `freshness-pacman-static.yml` measures the pin against
the live anchor on all eight ports weekly.

⛔ A commit, not the `v7.1.0` tag, and the difference is not cosmetic. `v7.1.0`
is an annotated tag object `208ff2b57e49f2851ce7bca5ac9090c6cb8aa746` pointing
at commit `5683f8477a0afcc6b331766175a83445b2dcfe89`, nine commits behind what
Arch ships. Pinning the tag would build a `pacman` that is in no published image.

```bash
curl -s --connect-timeout 15 --max-time 60 \
  "https://gitlab.archlinux.org/api/v4/projects/pacman%2Fpacman/repository/tags?per_page=5" \
  | jq -r '.[] | "\(.name) target=\(.target) commit=\(.commit.id)"'
```

## The toolchain choice

One `zig cc` install, not eight cross toolchains. zig is the compiler, the
linker, the archiver and the musl source in one 55 MB download, and the same
tree serves all eight targets.

⚠ The alternative was measured by the reference corpus rather than here. A
mussel or crosstool-NG toolchain bakes `--prefix` and `--with-sysroot` in at
configure time and cannot be relocated, so a cached toolchain artefact only
works if every runner unpacks it at the identical absolute path.

## Eleven libraries, not thirteen

Both reference recipes also link brotli and nghttp2. Neither is needed to fetch
a package from an Arch mirror and both cost:

- brotli selects a code model attribute on a compiler version test rather than a
  target test, and does not compile for `loongarch64` under clang;
- an OpenSSL built with brotli puts an object needing the brotli encoder inside
  `libcrypto`, and curl's probe then reports that OpenSSL is missing, naming the
  option that failed rather than the cause.

⚠ What that costs is recorded rather than hidden. The binary negotiates HTTP/1.1
and does not accept a `br` content encoding. The evidence file carries the whole
source set, so the difference is a measurement.

## What the build had to solve, each found by a failing build

| symptom | cause | fix |
| --- | --- | --- |
| `--with-openssl was given but OpenSSL could not be detected` | zig cc prefers a dynamic library and the prefix holds only archives | `-static` in `LDFLAGS` for every configure probe |
| the same message again, with `-static` set | OpenSSL installed into `lib64` on `x86_64` and `lib` elsewhere, so the prefix had two library directories | `--libdir=lib` on `Configure` |
| `unknown type name 'ino64_t'` in gpgme | gpgme declares `struct linux_dirent64` itself and spells the fields `ino64_t` and `off64_t`, which musl defines only under `_LARGEFILE64_SOURCE` | that define, for gpgme only |
| libgpg-error cannot cross compile | it ships a lock object header per host triplet and has exactly one for musl, `x86_64` | measure `sizeof(pthread_mutex_t)` for the target and generate the header |
| `meson built no binary` | `meson setup` had failed and its output went to `/dev/null` | keep both meson steps' output and print the tail in the diagnostic |
| `git describe` cannot describe anything | `use-git-version` needs the `v7.1.0` tag and the nine commits after it, and the fetch is one commit deep | `use-git-version=false`; the commit is checked against the pin instead |
| `using shared libraries requires dynamic linking`, after all 168 objects compiled | `buildstatic` resolves dependencies statically; `libalpm` is declared with `library()` and follows `default_library` | `-Ddefault_library=static` as well |
| `'pthread.h' file not found` for 32 bit PowerPC | `powerpc-linux-musl` is not a zig target | `powerpc-linux-musleabi` |
| curl's getifaddrs run test never returned for `ppc` | with QEMU in `binfmt_misc` autoconf answers "whether we are cross compiling: no" and every run test executes a target binary | pass `--build` as well as `--host` |
| `gcc: No such file or directory` building libgpg-error's `mkheader` | with `--build` and `--host` differing, autotools asks for `CC_FOR_BUILD` and its default is gcc | a native zig cc wrapper, so the no gcc claim stays true |

### The lock object, which is the one worth reading twice

libgpg-error cross compiles only to a host it ships `src/syscfg/lock-obj-pub.<triplet>.h`
for. It ships 42 of them and exactly one is musl: `x86_64-unknown-linux-musl`.
`mkheader.c` canonicalises the vendor field and stops there. It does not map musl
onto gnu, so seven of this repository's eight architectures fail on a missing
include.

⛔ Copying the gnu file is wrong. It carries `sizeof(pthread_mutex_t)`, and glibc
and musl do not agree on it.

⭐ So the size is measured rather than assumed. A translation unit declaring an
array of that length is compiled for the target, and the symbol's size is read
back out of the object with `readelf`. Nothing is executed, so no emulator is
needed, and the value is the target ABI's own.

| target | `sizeof(pthread_mutex_t)` | alignment |
| --- | --- | --- |
| `x86_64`, `aarch64`, `riscv64`, `loongarch64`, `powerpc64`, `powerpc64le` | 40 | 8 |
| `arm`, `powerpc` | 24 | 4 |

## What was built

Built on this workstation, 2026-08-28, inside `docker.io/pkgforge/archlinux:latest`
on `linux/amd64`. Every binary was run under its own architecture's emulator and
printed its version.

| architecture | ELF machine | bytes | reported |
| --- | --- | --- | --- |
| `amd64` | Advanced Micro Devices X86-64 | 15910176 | Pacman v7.1.0 - libalpm v16.0.1 |
| `arm64` | AArch64 | 15897928 | Pacman v7.1.0 - libalpm v16.0.1 |
| `armv7` | ARM | 14048036 | Pacman v7.1.0 - libalpm v16.0.1 |
| `loong64` | LoongArch | 15223104 | Pacman v7.1.0 - libalpm v16.0.1 |
| `riscv64` | RISC-V | 24082528 | Pacman v7.1.0 - libalpm v16.0.1 |
| `ppc` | PowerPC | 14827576 | Pacman v7.1.0 - libalpm v16.0.1 |
| `ppc64` | PowerPC64 | 16520608 | Pacman v7.1.0 - libalpm v16.0.1 |
| `ppc64le` | PowerPC64 | 16538280 | Pacman v7.1.0 - libalpm v16.0.1 |

⭐ Eight of eight. Every one was executed under its own architecture's emulator
and printed that string, which is the only one of the three checks that means
the binary works.

⛔ **The build is not byte reproducible run to run, and that is measured rather
than assumed.** Two `amd64` builds from the same script and the same pin, minutes
apart on one host, produced `b3d0db4050b4f371` and `e4ac15383d64a8a9`, both
15910176 bytes. The cause is not established. ⚠ Nothing here claims a
reproducible build: policy 8 asks for reproducible **inputs**, which the pin
gives, and the evidence file records which inputs produced which binary.

```bash
WORK=/tmp/pacman-static OUT=/tmp/dist scripts/build-pacman-static amd64
readelf -lW /tmp/dist/pacman-static-amd64 | awk '/INTERP/ { n++ } END { print n + 0 }'
```

⭐ Three checks and only the third means anything: meson compiled it, the ELF
names the right machine and carries no `PT_INTERP`, and the binary ran under its
architecture's emulator and printed its version. ⛔ With no emulator the third
reads `NOT MEASURED`, in the output and in the evidence file. It is never a dash
and never a pass.

## Where it runs

| place | state |
| --- | --- |
| inside this repository's own image | built, all architectures |
| a Linux workstation | Debian trixie container prepared with the documented apt line. ⚠ Its network was too slow to finish an install, so the recipe was exercised on the Arch image instead |
| CI | `.github/workflows/pacman-static.yml`, ⚠ not yet run on a GitHub runner |

## Releases

`pacman-static.yml`. A `workflow_dispatch` run builds every architecture, uploads
the binaries and their evidence files, and stops. Only a `v*` tag whose commit is
an ancestor of the default branch reaches the release job, so a manual run cannot
publish by accident.

⛔ The body is generated by `scripts/release-notes` from the evidence files, so
the release notes and the assets cannot disagree. It refuses a binary with no
evidence file, an evidence file with no binary, and a set built from more than
one pacman commit.

⚠ The source offer is the pin. The binary is `pacman`, which is
`GPL-2.0-or-later` however it was built, and
`bootstrap/pacman-static/sources.pin` names every input by URL and `sha256`, so
the exact sources are recoverable from the pin alone.

## The guide

`docs/bootstrap-with-pacman-static.md`. Build the binary, build a root with it
in two passes, and end with an image that passes this repository's image suite.
Every fenced block in it is parsed by `tests/static/80-docs-claims.sh`, which now
discovers `docs/` rather than being handed a list of three files.

⛔ The two passes are not interchangeable. There is no `gpg` inside a static
pacman, because `pacman-key` is a shell script that drives `gpg`, so the first
pass cannot verify anything. The second runs inside the new root, where `gpg`
now exists. A bootstrap that stops after the first has proved the download
worked and nothing about trust.

## What is not proven

- ⚠ **CI.** `pacman-static.yml` has never run on a GitHub runner. It installs
  `qemu-user-static` and refuses to build an architecture whose emulator is
  absent, so the failure would be loud, but that is a design and not a
  measurement.
- ⚠ **A non Arch workstation.** The apt line in the guide is written and was not
  run to completion: the Debian container's network could not finish the
  install. The build itself needs no Arch specific tool, and that is reasoning
  rather than a measurement.
- ⚠ **Real hardware.** Every non `x86_64` binary was run under `qemu-user`, which
  emulates the instruction set and passes syscalls to the host kernel. No target
  kernel, no target page size.
- ⚠ **A bootstrap end to end with it.** The guide's commands are parsed, not
  executed. Building a root from nothing with the static binary and running the
  image suite against the result has not been done here.
- ⚠ **Upstream's own signature.** The pin names the two pacman release manager
  fingerprints and the build does not yet verify the signed tag: the shallow
  fetch that keeps the checkout cheap does not carry it. The commit is checked
  against the pin, which is the stronger half, and the signature is the half
  still missing.
