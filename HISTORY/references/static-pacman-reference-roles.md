# Which static pacman reference answers which question

Set by the maintainer 2026-08-28, asked as whether the canonical AUR package
replaces the Manjaro fork as the studied reference for TODO 2. The answer was
that all three are required and serve different purposes.

⛔ This page is the record. It does not belong in `README.md` or in `docs/`,
which are manuals. A reader building the binary needs
`docs/bootstrap-with-pacman-static.md`; a session about to change the recipe
needs this.

⛔ Decision 7 is unchanged by any of it. Nothing is vendored. This repository
builds its own recipe from pacman's own sources, and all three are read.

## The three, and what each is for

| reference | role | read it for |
| --- | --- | --- |
| `aur/pacman-static` | the recipe reference | how the canonical package builds pacman against musl, and what it links |
| `manjaro-contrib/packages-core-pacman-static` | the ports reference | the only one of the three that declares `riscv64`, and the one patch it carries that the canonical package does not |
| `Aseem0xff/pacman-static` | the toolchain reference | one `zig cc` install instead of per architecture toolchains, and the only one with a `loongarch64` case at all |

## Why not one of them

⭐ **None of the three covers the eight architectures this repository builds.**

| architecture | AUR | Manjaro fork | Aseem |
| --- | --- | --- | --- |
| `amd64` | yes | yes | yes |
| `arm64` | yes | yes | yes |
| `armv7` | yes | yes | no |
| `loong64` | no | no | yes |
| `riscv64` | no | declared, cannot build | yes |
| `ppc64le` | no | no | yes |
| `ppc`, `ppc64` | no | no | no |

⛔ Two of this repository's eight are covered by none of them, and one more,
`armv7`, is covered by neither of the two that could build it for the others.
That is why the recipe here is its own rather than an adaptation of any one.

⚠ The Manjaro fork's `riscv64` is declared in `arch()` and cannot build:
`openssltarget='linux64-$CARCH'` is single quoted, so `$CARCH` never expands and
OpenSSL's `Configure` receives a literal. ⭐ Declared is not built, and nothing
in that fork's CI catches it because it has one runner tag.

## The ordering between them

- `aur/pacman-static` is ahead on `pkgrel`, 16 against the fork's 15, and does
  not declare the broken `riscv64` branch. It is the better reference on every
  axis except the one patch the fork carries.
- The fork is kept because that patch and the `arch()` line are evidence of
  intent about the ports, which the canonical package does not carry.
- Aseem is the newest and the only one that answers the two questions this
  repository actually had: how to reach `loongarch64` at all, and how to avoid
  building a toolchain per architecture.

## What was taken, and what was not

⛔ No line of any of them is in this repository. What transferred is knowledge,
and every piece of it was re-measured here before it was relied on:

| taken | re-measured as |
| --- | --- |
| `zig cc` as the whole toolchain | `bootstrap/pacman-static/sources.pin`, pinned by sha256 at 0.16.0 |
| the eleven library dependency order | `scripts/build-pacman-static`, with brotli and nghttp2 dropped and the reason written down |
| the five repository layouts | `rootfs/*/etc/pacman.conf`, eight of them, three of which no reference has |
| the two pass bootstrap shape | `docs/bootstrap-with-pacman-static.md` |

⚠ **Two claims did not reproduce**, and both are in `Aseem0xff/pacman-static`
`docs/GOTCHAS.md`:

1. G-11 says `iana-etc` and `openssl` are only in ArchPOWER's `any` database.
   `iana-etc` is. `openssl-3.6.3-1` is in the architecture specific database.
   Measured 2026-08-28. `HISTORY/powerpc.md`.
2. G-09's emulator table is correct and incomplete for this repository's needs:
   it lists five triples and this repository has eight, and the two it does not
   cover, `powerpc` and `powerpc64`, are the two `docker/setup-qemu-action` does
   not register either.

⭐ Its package counts reproduce exactly: 3736 in `base/powerpc64le` and 2200 in
`base/any`, both re-measured 2026-08-28.

⚠ Its own `RESEARCH.md` §0 lists nine claims it corrected about itself in one
session and says to assume more remain. That warning held: the two above were
found by measuring rather than by reading.

## Verdicts, under policy 11

| reference | verdict |
| --- | --- |
| `aur/pacman-static` | **confirms**. The canonical recipe, read and not copied |
| `manjaro-contrib/packages-core-pacman-static` | **anti-pattern exhibit** for the single quoted `openssltarget`, **confirms** for the rest |
| `Aseem0xff/pacman-static` | **adopt**, for the toolchain approach only |

⚠ `aur/pacman-static` has no tracker of its own: the AUR comment stream is what
exists, and it was not read. Policy 11 asks for the tracker, and for this one
there is not one in the shape the rule assumes. Recorded rather than glossed.

## Re-mine when

- the pinned pacman commit moves, which `freshness-pacman-static.yml` reports;
- any of the three gains an architecture this repository builds and they do not;
- `Aseem0xff/pacman-static` closes its intermittent `SIGSEGV`, which its own
  repository calls a blocker and which nothing here has reproduced or ruled out.
