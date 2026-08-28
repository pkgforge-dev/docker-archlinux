# Aseem0xff/pacman-static

The second reference for TODO 2, reported by the maintainer on 2026-08-28 as a
0-BSD proof of concept for this repository. Read under policy 11 before any
line of it is copied. It claims a statically linked `pacman` built from source
for five architectures, four of which are this repository's own.

## Provenance

| item | value |
| --- | --- |
| repository | `https://github.com/Aseem0xff/pacman-static` |
| commit read | `38f7e3e45730f9a6dd4d62675dc1e9594b90f4e4` |
| commit date | 2026-08-28T14:03:34Z |
| commit subject | `Static multi-arch pacman: research, instruments, corpus and working build` |
| commits in the repository | 1 |
| commit author | `Claude <noreply@anthropic.com>` |
| repository created | 2026-08-28T10:40:45Z |
| last push | 2026-08-28T14:07:40Z |
| default branch | `main`, the only branch |
| licence | **0BSD**, `LICENSE`, 12 lines, the full permissive text. The API reports `spdx_id: 0BSD` |
| tracker read | **0 items**: no issues, no pull requests, no releases, no tags |
| stars, forks, archived | 0, 0, not archived |
| tracked files | 1301, of which 1249 are the vendored corpus under `references/` |
| clone | `--depth 1` |
| studied on | 2026-08-28 |

```bash
gh api repos/Aseem0xff/pacman-static --jq '{created_at,pushed_at,license:.license.spdx_id,default_branch}'
gh api repos/Aseem0xff/pacman-static/commits --paginate --jq '.[] | "\(.sha) \(.commit.committer.date)"'
gh api 'repos/Aseem0xff/pacman-static/issues?state=all&per_page=100' --paginate --jq 'length'
gh api 'repos/Aseem0xff/pacman-static/pulls?state=all&per_page=100' --paginate --jq 'length'
git clone --depth 1 https://github.com/Aseem0xff/pacman-static
```

⚠ **The repository was created and pushed on the day it was read**, and it was
pushed again four minutes before the commit above was captured. The commit was
captured first, which is what policy 11 requires, and every claim below names
that commit.

⚠ **The tracker is empty, so there are no decisions recorded in it.** Closed
issues are where reasoning usually lives. There are none. Everything below is
read from the tree.

## Verdict: adopt

⭐ **Adopt as the recipe TODO 2 builds from**, subject to every number being
re-measured here. The licence permits it outright, it covers four of this
repository's five architectures plus a fifth this repository has on file as
blocked, and its central technical claims hold when checked against live
upstream rather than against its own corpus.

⛔ **Adoption is not trust.** Nothing in it has been built or run on this
machine or in this repository's CI. Its own `RESEARCH.md` §0 lists nine claims
it corrected about itself mid-flight and says to assume more remain. What is
adopted is the method and the file-level detail, each to be re-measured.

⛔ **And adopt does not mean vendor.** Policy 11's vocabulary uses one word for
both, and the two are different here. Nothing of this tree is copied into this
repository by this verdict. What is adopted is the method and the file level
detail, to be rebuilt from pacman's own sources as decision 7 requires.

⛔ **The verdict is bounded by one gap, and it is the size of the task.**
`armv7` is one of this repository's five architectures and **this reference does
not cover it.** Neither does either `PKGBUILD` reference in a form known to
build: the canonical package declares `armv7h` in `arch()` and nothing builds
it. The fork's `.gitlab-ci.yml` is 211 bytes, one job, one runner tag,
`aarch64`, and the AUR has no CI at all.

```bash
curl -sS -L "https://raw.githubusercontent.com/manjaro-contrib/packages-core-pacman-static/aad8fa5b24a94aa36f01b42eeae5a426b314a2c9/.gitlab-ci.yml"
```

⭐ **A static `pacman` for four of five architectures does not remove the trust
root. It removes it for four fifths of the matrix.** The image still cannot be
bootstrapped without a container for the fifth, so whoever takes TODO 2 should
size it against five, not four.

## The licence, which is the question decision 7 turned on

⛔ **Read because decision 7 turned on exactly this.**
`manjaro-contrib/packages-core-pacman-static` carries **no** LICENSE while its
`PKGBUILD` declares `GPL-2.0-or-later`, and a repository claiming 0-BSD in
prose while shipping something else is the same trap.

**It does not repeat here.** `LICENSE` is the full 0BSD text, 12 lines,
`Copyright (C) 2026 Aseem`, with the permission grant and the warranty
disclaimer intact. GitHub's own licence detection agrees.

```bash
gh api repos/Aseem0xff/pacman-static --jq '.license.spdx_id'   # 0BSD
wc -l LICENSE && head -4 LICENSE
```

`LICENSING.md`, 68 lines, states the scope in the repository's own words: the
prose, scripts, patches, fixtures and experiment output are 0BSD, with no
attribution and no permission required. It carries two scope notes of its own,
and both are correct:

1. The vendored trees under `references/` keep their upstream licences. It
   lists them: `archlinux__pacman` GPL-2.0-or-later, `aur__pacman-static`
   GPL-2.0-or-later, `manjaro-contrib__packages-core-pacman-static`
   GPL-2.0-or-later, `firasuke__mussel` ISC, `seccomp__libseccomp` LGPL-2.1.
2. The patch **diff text** is 0BSD; applying one produces a derivative of the
   upstream file under that file's licence.

⛔ **0BSD on the recipe does not settle the pacman question, and this document
does not claim it does.** The binary is `pacman`, so it is `GPL-2.0-or-later`
however it was built. The source offer obligation on a release asset is
unchanged. TODO 2 already records that as unsettled.

⚠ `patches/pacman/0001-libalpm-invalidate-curl-data-in-child.patch` is authored
by Christian Hesse and carries his `From:` header. It is a GPL-2.0-or-later
change to pacman regardless of the 0BSD grant over the diff text, and
`LICENSING.md` says so itself.

## What was verified here, against live upstream

⚠ **The corpus was not used as the oracle for any of these.** Each was fetched
from the upstream it describes, so a wrong corpus could not produce a right
answer.

### 1. The `riscv64` OpenSSL target cannot expand, in both PKGBUILDs

```bash
curl -sS -o manjaro-PKGBUILD -L "https://raw.githubusercontent.com/manjaro-contrib/packages-core-pacman-static/aad8fa5b24a94aa36f01b42eeae5a426b314a2c9/PKGBUILD"
curl -sS -o aur-PKGBUILD -L "https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=pacman-static"
grep -n 'openssltarget' manjaro-PKGBUILD aur-PKGBUILD
grep -n '^arch=' manjaro-PKGBUILD aur-PKGBUILD
```

| what | value |
| --- | --- |
| the line, both files | `openssltarget='linux64-$CARCH'`, single quoted |
| in the `riscv64)` branch | yes, `manjaro-PKGBUILD:251`, `aur-PKGBUILD:256` |
| `arch=()` names `riscv64` | manjaro **yes**, line 27. aur **no**, line 25 |

⭐ **Declared is not built.** In the canonical package the branch is
unreachable, because `riscv64` is not in its `arch()`. In the fork it is the
one architecture the fork exists to add, and `$CARCH` in single quotes never
expands, so OpenSSL's `Configure` receives a literal.

⛔ **This corrects a fact in this repository's own TODO 2 table**, which lists
the fork's architectures as `i486 i686 pentium4 x86_64 arm armv6h armv7h
aarch64 riscv64` without qualification. `riscv64` is declared there and cannot
build. riscv64 is one of this repository's five.

### 2. The Manjaro reference has moved since it was mined

| item | recorded in TODO 2 | measured 2026-08-28 |
| --- | --- | --- |
| HEAD | `8c7a7c2262d5d51ee4d7301d403133a9c932c2f6` | `aad8fa5b24a94aa36f01b42eeae5a426b314a2c9` |
| commit date | 2026-07-31 | 2026-08-27T13:39:20Z |
| `pkgrel` | 14 | **15** |

```bash
gh api repos/manjaro-contrib/packages-core-pacman-static/commits --jq '.[0] | "\(.sha) \(.commit.committer.date) \(.commit.message | split("\n")[0])"'
gh api repos/manjaro-contrib/packages-core-pacman-static/commits/8c7a7c2262d5d51ee4d7301d403133a9c932c2f6 --jq '.commit.committer.date'
```

The recorded commit still resolves, dated 2026-07-31T14:05:09Z, so the entry
was right when it was written. Its subject today is
`[pkg-upd] 7.1.0.r9.g54d9411-15`. ⚠ Policy 11 says re-mine on every bump, and
this is the bump.

### 3. There is a canonical package upstream of the one on file

⛔ **The reference this repository has on file is a fork of one it does not
name.** `aur/pacman-static` is maintained in the AUR, and the fork's whole
diff against it is small: `pkgrel` 15 against **16**, so the canonical package
is ahead.

| | manjaro | aur |
| --- | --- | --- |
| `pkgver` | `7.1.0.r9.g54d9411` | `7.1.0.r9.g54d9411` |
| `pkgrel` | 15 | 16 |
| `arch()` names `riscv64` | yes | no |

⚠ **Decision 7 was set against the fork alone.** It refuses vendoring
`packages-core-pacman-static` and requires this project's own recipe built from
pacman's sources. Nothing measured here overturns it: the canonical package is
also `GPL-2.0-or-later` and also has no `loongarch64` case. ⛔ Whether the
canonical package replaces the fork as the studied reference is the
maintainer's call, not this session's.

### 4. The corpus is smaller than its own README says

`references/README.md` describes the corpus as "the right one at 59 MB".
Measured on the clone at `38f7e3e4`:

```bash
python -c "
import os
tot=n=0
for root,dirs,files in os.walk('references'):
    if '.git' in dirs: dirs.remove('.git')
    for f in files:
        tot+=os.path.getsize(os.path.join(root,f)); n+=1
print(n, tot)
"
```

**1249 files, 10 935 533 bytes, 10.4 MB.** ⚠ The likeliest reading is that 59
MB predates the removal of the nested `.git` directories that the same README
documents, and was not re-measured after. Nothing depends on the number.

### 5. A retracted diagnosis survives in a code comment

`RESEARCH.md` §0 claim 1 retracts the finding that the segfault was a pacman
bug fixed by the Manjaro patch: "The patch changed nothing." §4.3 repeats it:
"⛔ **It does not fix the crash in §9**, applied, built, crash unchanged."

`experiments/80-build-pacman.sh:91` still states the retracted cause as fact:

```
# phase, on stock v7.1.0+54d94116. The crash is in _alpm_run_chroot's forked
# child touching libcurl state the parent owns. Upstream curl issue 21466.
```

⚠ The patch is still worth applying, and both documents say so for a different
reason: it is a real fix for a real child-process bug. Only the causal claim in
the comment is stale. ⭐ Worth carrying forward as a pattern, not a complaint:
a retraction that reaches the write-up and not the code leaves the wrong answer
where the next reader works.

## What it claims, and what the claim rests on

⛔ **None of this was re-run here.** It is recorded so a later session knows
what to re-measure rather than re-derive.

| claim | where it is measured | what it rests on |
| --- | --- | --- |
| static `pacman` 7.1.0 for `x86_64`, `aarch64`, `riscv64`, `loongarch64`, `powerpc64le` | `experiments/out/85-feature-matrix.txt` | `readelf -l` finds no `PT_INTERP`; each binary prints `libalpm v16.0.1` under its own emulator |
| all five install `base` from their own distribution | `experiments/out/95-cross-arch-bootstrap.txt` | 136, 135, 137, 140 and 137 packages; `file(1)` on the installed `/usr/bin/bash` read back |
| a full x86_64 root, `chroot`ed, with signatures on | `experiments/out/90-bootstrap-arch.x86_64.txt` | 137 packages, 704 MB, then `pacman-key --init && --populate` and a verified re-sync, reported separately from the unverified pass |
| no feature dropped to link statically | `docs/FEATURES.md` | libarchive 3.8.9, libcurl 8.21.0, gpgme 2.1.2, libcrypto 3.6.4, libseccomp 2.6.0, landlock header, identical on all five |
| one `zig cc` install replaces five GCC cross toolchains | `experiments/out/50-zig-cross-targets.txt` | zig 0.16.0, one 55 MB tarball, pinned by sha256 |

⚠ **Every non-`x86_64` claim is a `qemu-user` claim**, which the repository
states at each point. No real hardware, no target page size, and no `chroot`
into a foreign root: post-transaction hooks fail there with `Exec format
error`. That is the same gap TODO 9 records for `loong64` here.

⛔ **One fault is open and it blocks shipping.** A low rate intermittent
`SIGSEGV` at the end of `pacman -S base`, **after** the install completes:
roughly 3 in 50, all under load, moving between architectures across runs. The
package count and the ELF check pass and only the exit status is wrong.
`RESEARCH.md` §9 lists six hypotheses killed by measurement and says the next
statement about the cause should come from a stack.

## What is worth taking, ranked

1. ⭐ **`zig cc` instead of a musl cross toolchain.** One pinned tarball, no
   toolchain build, and it reaches `loongarch64`, which `mussel` has no case
   for at all. This is the finding that changes TODO 2's shape.
2. ⭐ **The per architecture OpenSSL target table**, `TASKS.md` T-04. Three of
   the five carry a `64` in the middle and two do not, and it is not derivable
   from the triple.
3. ⭐ **Extract every source tree per architecture, never configure two targets
   in one tree.** OpenSSL bakes the prefix into `configdata.pm` and the
   generated `.pc` files, the failure is silent until the final link, and
   copying a configured tree carries the poison with it.
4. ⭐ **`-static` belongs in the meson cross file**, not in `LDFLAGS`, which
   reaches the build machine compiler instead.
5. ⭐ **`LIBS=-lbrotlienc` when configuring curl**, which avoids the reference
   PKGBUILD's `configure.ac` patch and the `autoreconf` and autotools it drags
   onto the build host.
6. **The brotli loongarch patch**, `patches/brotli-1.2.0/`. clang accepts
   `__has_attribute(model)` on every target and rejects the value where the
   target has no code models.
7. **The two pass keyring bootstrap**, `docs/GOTCHAS.md` G-08. `pacman-key` is
   a shell script driving `gpg`, so a static binary cannot run it into an empty
   root. ⚠ Its pass 1 uses `SigLevel = Never`, which policy 5 refuses for this
   repository's own build. The shape transfers, the trade does not.

## What it does not settle

- ⛔ **Source provenance.** `experiments/60-fetch-sources.sh` records the
  sha256 of what arrived on one host on one day. Its own `TASKS.md` T-07 says
  that is a change detector and not provenance, and marks it a blocker.
- ⛔ **Reproducibility.** Built once, never diffed against a second build.
  Every binary measured is unstripped with `debug_info`.
- ⚠ **Release shape.** T-15 is unstarted. This repository's TODO 7 has the
  mechanics mined from `pkgforge-dev/cross-libc-dlopen` already.
- ⚠ **`i686`, `arm`, `armv7h`.** Supported by the PKGBUILD references,
  untouched here. ⛔ `armv7` is one of this repository's five architectures and
  this reference does not cover it.

## ⛔ What the fetches did not get

- **GitHub discussions on this repository.** Not checked. The REST route this
  session used does not reach them.
- **Any tracker.** There is none: 0 issues and 0 pull requests, measured above.
  A one day old repository has no closed decisions to read, so policy 11's
  most productive step yields nothing here and that is a real gap, not a clean
  result.
- **The AUR comment thread for `pacman-static`.** Not served by any API route
  this session had. For a package whose maintainer is a pacman developer that
  is a real gap, and the reference records the same gap.
- **The Manjaro fork's GitLab tracker.** Its GitHub mirror carries 0 issues and
  0 pull requests, and its own `.gitlab-ci.yml` points at GitLab. Not fetched,
  here or there.
- **pacman's own GitLab issues.** Not fetched.

## What was opened, and what was not

⛔ **Read in full**, at `38f7e3e4`: `LICENSE` (12), `LICENSING.md` (68),
`README.md` (202), `RESEARCH.md` (567), `TASKS.md` (580), `docs/FEATURES.md`
(87), `docs/GOTCHAS.md` (477), `references/README.md` (91),
`experiments/README.md` (94), `experiments/70-build-static-stack.sh` (395),
`experiments/80-build-pacman.sh` (237), `experiments/90-bootstrap-arch.sh`
(237), both files under `patches/`, and the outputs
`experiments/out/95-cross-arch-bootstrap.txt` and
`experiments/out/85-feature-matrix.txt`.

⚠ **Not opened:** `scripts/mine-repo.sh` (424),
`docs/patches/mine-repo-page-join.md` (63), the four files under `examples/`
(873 lines together), the remaining eleven scripts under `experiments/`, the
remaining fifteen files under `experiments/out/`, and the 1249 file corpus
under `references/` beyond the four `PKGBUILD` lines cited above. ⭐ The
examples matter most of those: TODO 2 asks this repository for a bootstrapping
guide, and `examples/02-bootstrap-arch-rootfs.md` is the reference's version of
one.

## Found while reading this, and filed elsewhere

⭐ **ArchPOWER now publishes a keyring package.** `docs/GOTCHAS.md` G-11 names
`archpower-keyring` and contradicts this repository's own
`HISTORY/removed-architectures.md`, which recorded no keyring package in `base`
or `testing`. Re-measured live, the reference is right and the reason the
earlier probe missed it is a real trap. The measurement is in
`HISTORY/removed-architectures.md`, at the ArchPOWER section, because that is
the page a session taking TODO 3 opens.
