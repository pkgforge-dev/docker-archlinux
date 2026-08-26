# Outstanding work

The working brief, trimmed. ⭐ **Finished work is summarised. Unfinished work
keeps its full detail**, because that is what the next session has to act on.

Standalone by design: a reader needs nothing but this file and the repository.

---

## The repository

Automated multi-platform Arch Linux images, published to
`ghcr.io/pkgforge-dev/archlinux` and `docker.io/pkgforge/archlinux`.

⛔ **The two registries use different organisation names and it is not a typo.**
GHCR is `pkgforge-dev`, derived at run time from `github.repository_owner`.
Docker Hub is the hardcoded `pkgforge/archlinux`. Any tag work must emit both.

⛔ **No image or tag is ever removed from either registry.** Both hold 161 tags.
`:latest` and `:v<YYYY.MM.DD>` resolve to a multi-arch index and must keep doing
so.

Architectures: `amd64`, `arm64`, `armv7`, `riscv64`. ⚠ Those are the Docker
platform names. Tags also use the `uname -m` spelling, and the two differ for
every architecture except riscv64.

87 tracked files, 6 scripts, 5 workflows, 19 test files, 7 examples.

### The image stays vanilla

Minimal, sane defaults, unopinionated. Downstream decides everything else.

⭐ **The test for a change is not "is it smaller". It is "could a consumer undo
it."** Dropping the pacman package cache is a sane default: it comes back on
demand. A hook that re-deletes files on the consumer's next transaction is not.

⚠ That test proved insufficient once, and the correction is load-bearing:
`NoExtract` was undoable in principle and still broke a consumer, because the
package database kept listing paths that were not on disk. See
[`../noextract-reverted.md`](../noextract-reverted.md). **The image now withholds
nothing.**

### Downstream exists in numbers

```bash
gh api "search/code?q=pkgforge-dev%2Farchlinux+in:file&per_page=20" --jq '.total_count'
```

187 code hits on 2026-08-26. Named consumers include `ivan-hc/ArchImage`,
`pkgforge-dev/Anylinux-AppImages`, `Samueru-sama/Anylinux-AppImages`,
`kem-a/wps-office-appimage`, `citron-neo/emulator`,
`linux-surface/aarch64-arch-mkimg`, `iRASPA/RASPA3`. `pkgforge/archlinux-base`,
built by `pkgforge/devscripts` `Github/Runners/bootstrap/archlinux.sh`, is the
most direct: it runs this image and patches it with `sed`. Its requirements are
asserted by `tests/image/50-consumer-contract.sh`.

---

## ⛔ Standing policy

Set by the maintainer. Requirements, not preferences.

1. **Upstream is not a party to this work.** ⛔ Never file an issue or a pull
   request upstream, never comment on any upstream tracker, and ⛔ never suggest
   it in a document. Reading upstream is required; writing to it is forbidden.
   ⛔ Never write anything that reads as blame. State the defect, the version,
   the measurement and the patch. The rule is **vendor, then patch, then
   document** against a named upstream commit. ⚠ A licence can forbid vendoring;
   read it first and record it.
2. **Unmaintained upstreams are the normal case.** State the date and the status
   code. ⛔ Do not write that a project is dead or abandoned. Bootstrap from
   source as far as it can be taken rather than consuming an unverifiable
   prebuilt artefact.
3. **The quality bar is a distribution, not a side project.** No dead code, no
   commented-out experiments, no `|| true` hiding a failure, no step whose
   success means nothing, no file whose purpose nobody can state, no
   documentation claim that is not checked by a test.
4. **Documentation is a manual. History lives somewhere else.** `README.md` and
   `docs/` are concise and technical. No lore, no narrative, no dated banners.
   Amend rules in place. History goes in `HISTORY/`.
5. **Security: reduce the surface.** Signature checking stays on; ⛔
   `SigLevel = Never` is never the answer. Pin actions to commit SHAs. No opaque
   binary fetched at build time. Least privilege on every `permissions:` block.
6. **Maintainability: immune to upstream having a mood.** A breaking change, a
   mirror going away or a schema change must produce a **loud, specific CI
   failure**, never a silently wrong image and never a green run that published
   nothing.
7. **Compatibility: nothing changes for downstream, except that more is
   possible.** ⛔ An existing consumer must notice no difference at all.
8. **Reproducible and bootstrappable, as requirements.** A build reproducible
   only by trusting an image this project published is not bootstrappable.
   Evidence records which package, which version, which size, which checksum and
   when. "Built successfully" is not evidence.
9. **Nothing pinned is allowed to go stale.** Every pinned thing gets a job that
   **detects**, **applies on a branch**, **tests**, and **opens a pull request
   carrying the measurement** and ⚠ what it did **not** verify.
10. **Pin by commit hash, never by tag or release.** A tag moves. ⭐ A stale tag
    is never evidence a project is unmaintained; check the commits. The
    equivalent for a non-git artefact is a content hash.
11. **Mine the tracker before vendoring anything.** Order: clone shallow, ⛔
    **capture the commit first**, read the code, read the tracker, write it up.
    ⛔ The issues endpoint returns pull requests too. ⭐ Closed is where the
    decisions are. ⚠ Read the comments, not only the body. ⛔ If you could not
    fetch something, say so. Each reference gets one verdict: **adopt**,
    **confirms**, **anti-pattern exhibit**, **filed elsewhere**, or **refused**.

---

## ⛔ Decisions already made. Do not reopen.

1. **Adoption is `.gitattributes` and nothing else.** No check scripts, no
   `.editorconfig`, no doctor probe, no agent-facing files. What those would test
   belongs in CI, where it runs without anybody remembering to.
2. **The repository maintains itself.** Very low maintenance: the maintainer
   occasionally merges a Dependabot pull request and otherwise does not touch it.
   Secret scanning is GitGuardian, needing a repository secret. ⛔ Creating that
   secret is the maintainer's action. Ask, do not create.
3. **Effort goes into tests and scripts**, not documentation scaffolding.
4. **Publish both tag families.** `:x86_64` and `:amd64` are two names for one
   manifest, likewise `:aarch64`/`:arm64` and `:armv7l`/`:armv7h`/`:armv7`.
   `riscv64` is one tag. ⚠ The org precedent (`pkgforge/alpine`) supports only
   the `uname -m` family; the docker-arch names are an extension. ⚠ `alpine`
   publishes no `latest` and no bare `v<date>`; this repository has both and
   downstream pulls them, so ⛔ keep them.
5. ⛔ **Superseded. Nothing is withheld from the image.** Decisions 5, 6 and 7 of
   the original brief stripped man pages, documentation, info pages and locales
   through `NoExtract`. A consumer broke, the maintainer ruled that the package
   database and the filesystem must agree, and every rule was removed. Full
   measurement in [`../noextract-reverted.md`](../noextract-reverted.md).
   ⛔ Do not reintroduce `NoExtract`. `tests/static/80-docs-claims.sh` fails on
   any rule in any shipped `pacman.conf`.

---

## What is done

Summaries. Each line points at the artefact that proves it.

| area | state |
| --- | --- |
| bootstrap | builds from the official Arch image pinned by digest, not from its own output. `tests/static/10-bootstrap-not-circular.sh` |
| signatures | `SigLevel = Required` everywhere, no `pacman-key` patch. The ARM keyring is pinned by sha256 and master fingerprint in `bootstrap/keyrings/archlinuxarm.pin`. `tests/static/30-signature-checking-on.sh` |
| publish topology | one job per architecture pushing by digest, a merge job needing the whole matrix creating every tag. A run that loses one architecture publishes nothing |
| cross-registry copy | exercised against scratch repositories on **both** registries via `dry_run` plus `dry_run_hub`, and both registries are verified after publishing. Run `33001089986` |
| evidence | `scripts/gen-evidence` writes a per-platform file: every package, version, size, sha256, release date. `tests/image/40-evidence.sh` |
| freshness | three workflows, keyring weekly, image pins weekly, mirrors monthly. All three fired once: runs `33001871256`, `33001881101`, `33001891317` |
| tests | 14 static files, 5 image files. Every assertion has a recorded fault in [`../tests-seen-to-fail.md`](../tests-seen-to-fail.md) |
| failure messages | every `fail` in `tests/` carries a `reproduce:` line, 103 of 103, enforced by `tests/static/15-actionable-failures.sh`. `die` gained action lines |
| pipeline traps | 17 sites removed across six files. `tests/static/25-pipeline-traps.sh` fails on either shape |
| harness | `tests/lib/harness.sh` has a test that does not report through it. `tests/static/05-harness.sh` |
| references | five studied with verdicts, in [`../references/`](../references/): the methodology template, `pkgforge/devscripts`, `archlinux/archlinux-docker`, `fwcd/docker-archlinux`, `westandskif/rate-mirrors` |
| consumer contract | `tests/image/50-consumer-contract.sh` asserts the eight things `pkgforge/devscripts` patches |
| architectures | ppc64le and i686 excluded, each with the measurement, in [`../removed-architectures.md`](../removed-architectures.md) |
| branch protection | applied. One review, `Static suite and linters` required, no force pushes, no deletions, `enforce_admins: false` |
| history | `main` is one root commit, `Rewrite Project v.0.0.1`. Everything before it is on `history-archive`, tip `9d1e142`. See [`../rewrite.md`](../rewrite.md) |
| reviews | eight, each with its lens, its findings and what it did not look at, in [`../reviews/`](../reviews/) |
| upstream defect parity | issue 55's class is fixed here and guarded. 1 path missing of 49035, against 25508 of 49027 in the official Arch image |

### Two defects found late, both fixed

- ⛔ **CI had never passed.** The actionlint step piped only stdout into `tee`,
  and `-verbose` writes to stderr, so the guard's `grep` failed on every run.
  That job is the required status check, so branch protection could not be
  satisfied by anything. Measured: stdout 0 bytes, stderr 1402 bytes.
- ⛔ **A downstream consumer broke** on `NoExtract`. See decision 5 above.

---

## What is left

⛔ **The order below is the order to take them in.**

### 1. Defect parity: check ours against every known upstream defect

⛔ **This is not about upstream and owes them nothing.** Their tracker is a list
of failure modes somebody already found and paid for. Each one is a question
about **this** image, and each answer belongs in a test.

⭐ **One is already fixed here and must stay fixed.**

`archlinux/archlinux-docker` issue 55,
`https://gitlab.archlinux.org/archlinux/archlinux-docker/-/issues/55`, open since
2020-12-06: the image withholds files the package database still lists. Measured
on 2026-08-26, same command, same packages:

```bash
podman run --rm --platform linux/amd64 <image> bash -c '
  pacman -Sy --noconfirm --needed qt6-base >/dev/null 2>&1
  echo "listed : $(pacman -Qlq | wc -l)"
  echo "missing: $(pacman -Qlq | while read -r p; do [ -e "$p" ] || printf x; done | wc -c)"'
```

| image | listed | missing |
| --- | --- | --- |
| `docker.io/pkgforge/archlinux:latest` | 49035 | **1** |
| `docker.io/library/archlinux:latest` | 49027 | 25508 |

The one is `/var/lock`, a symlink to `../run/lock` that only systemd creates.
`tests/static/80-docs-claims.sh` fails on any `NoExtract` line in any shipped
config, so it cannot come back by accident.

⭐ **Also already checked here.** Issue 106, xattrs and acls not preserved:
`/usr/bin/newgidmap` and `/usr/bin/newuidmap` carry `security.capability` in this
image. Verified with `getfattr -d -m -`. ⚠ Not guarded by a test yet, so it can
regress. Add one.

⛔ **Not yet checked against this image.** Each needs a measurement and, where it
applies, a test:

| issue | what to check here |
| --- | --- |
| 72, a locale that cannot be generated | `locale-gen` for a non-Latin locale, for example `ja_JP.UTF-8`. Should now work with no preparation; confirm and add it to `tests/image/` |
| 60, `/etc/hosts` and `/etc/resolv.conf` | whether the container runtime's versions survive, and whether anything here would clobber them |
| 67 and 56, `failed to initialize alpm library` | pacman on an older host kernel, or one without the syscalls it expects. Relevant to consumers on old runners |
| 66, tags outliving the artefact they name | whether any published tag can point at a manifest whose blobs are gone |
| 80, a package binary not on `PATH` | whether `/usr/sbin` being a symlink to `/usr/bin` holds in this image |
| 110, systemd in rootless containers | out of scope unless a consumer asks; record the decision |

⚠ Read them with the GitLab API; `gh` does not reach GitLab:

```bash
B="https://gitlab.archlinux.org/api/v4/projects/archlinux%2Farchlinux-docker"
curl -sS "$B/issues?state=all&per_page=100" | jq -r '.[] | "\(.iid)\t[\(.state)]\t\(.title)"'
```

⛔ **Comments need authentication and this account has none.** `$B/issues/55/notes`
returns `{"message":"401 Unauthorized"}`, so every issue is readable by title and
description only. Say so in anything written from them.

⛔ **Reads only.** Policy 1: nothing is filed, commented or proposed upstream.

### 2. Static pacman, everywhere, and in the releases

⛔ **Promoted from "consider" to a requirement.** The trust root today is one
container image plus working mirrors. A statically linked `pacman` removes the
first, and it has to work in CI, in local development and in a consumer's hands.

What this owes, all of it:

- **A `pacman-static` built from source for all four architectures**, `x86_64`,
  `aarch64`, `armv7h`, `riscv64`. ⛔ Built here, never downloaded. Policy 5
  forbids an opaque binary fetched at build time, and a static bootstrap binary
  is the last thing that should arrive unverified.
- **It works everywhere.** CI, a Linux workstation, and inside this image. A
  binary that only builds on the runner is not a bootstrap tool.
- **A release asset per architecture**, alongside the rootfs tarball and the
  evidence file. Named, checksummed, and listed in the release body.
- ⭐ **A complete guide to bootstrapping from scratch with it**, written so a
  reader with the binary and nothing else can build a working root: fetch the
  keyring, verify it against the pin, populate, install `base`, and end with an
  image that passes this repository's own image suite. It goes under `docs/` or
  `examples/`, and every command in it is checked by
  `tests/static/80-docs-claims.sh`.

#### The reference, mined 2026-08-26

`https://github.com/manjaro-contrib/packages-core-pacman-static`, HEAD
`8c7a7c2262d5d51ee4d7301d403133a9c932c2f6`, 2026-07-31.

| item | value |
| --- | --- |
| what it is | a `PKGBUILD` that links pacman against musl with its own dependency tree |
| pacman version | `7.1.0.r9.g54d9411-14` |
| architectures | `i486 i686 pentium4 x86_64 arm armv6h armv7h aarch64 riscv64` |
| statically links | nghttp2 1.70.0, curl 8.21.0, openssl 3.6.3, brotli 1.2.0, zlib 1.3.2, xz 5.8.3, bzip2 1.0.8, zstd 1.5.7, libarchive 3.8.9, libgpg-error 1.61, libassuan 3.0.0, gpgme 2.1.2, libseccomp 2.6.0 |
| makedepends | `meson cmake musl kernel-headers-musl git gperf` |
| patches carried | 4, one local and three fetched from pacman's own GitLab by commit |
| their CI | GitLab, one `aarch64` tag, `sudo chrootbuild -cp` |

⭐ **Its pacman version is the anchor this repository already publishes.**
`7.1.0.r9.g54d9411` is exactly the value in the `<arch>-<anchor>` tag family, so
the static binary and the image can be shown to agree.

⭐ **How it pins, which is worth adopting.** The pacman source is a **signed** git
tag verified against `validpgpkeys`, the two pacman maintainers' fingerprints
`6645B0A8C7005E78DB1D7864F99FFE0FEAE999BD` and
`B8151B117037781095514CA7BBDFFC92306B1121`. Dependency tarballs come with `.asc`
signatures. ⚠ Policy 10 prefers a commit hash to a tag; a signed tag plus a
pinned key is a defensible alternative, but write down which was chosen and why.

⚠ **Three cautions, all measured or read:**

- ⛔ **Licence.** The repository carries **no LICENSE file**; the `PKGBUILD`
  declares `GPL-2.0-or-later` for what it builds, which is pacman's own licence.
  Policy 1's vendor-then-patch does not apply cleanly: copying that `PKGBUILD`
  into this MIT repository needs a decision, and **distributing a GPL binary
  from a release carries a source offer**. Settle both before building.
- ⚠ **Their CI does not transfer.** It builds one architecture on a Manjaro
  runner with `chrootbuild`. This project has four architectures and GitHub
  runners, so the build recipe transfers and the pipeline does not.
- ⚠ **`.nvchecker.toml` watches the AUR**, not upstream pacman. Policy 9 needs a
  watcher of this project's own.

⭐ **What this unlocks, and why it is worth the cost.** With a static pacman the
`FROM scratch` bootstrap becomes possible: one static binary plus a pinned
keyring is a far smaller trust root than a whole distribution image, and it is
the only shape that lets a third party rebuild the root without this repository's
tooling or any base image at all.

⚠ **The alternative that was tried and failed.** `fwcd/docker-archlinux` ran an
Alpine bootstrap for six and a half months, 2023-08-30 to 2024-03-18. Its price
was `SigLevel = Never` in the bootstrap stage, because Alpine's `pacman` package
carries no Arch keyring. Policy 5 forbids that trade. ⭐ **The static route
differs in exactly that place: it can keep `SigLevel = Required`**, because the
keyring is pinned and verified rather than absent. Full write-up in
[`../references/fwcd-docker-archlinux.md`](../references/fwcd-docker-archlinux.md).

⚠ **A cheaper half-measure exists and is not the same thing.**
`archlinux/archlinux-docker` pins an entire package set with **one date** against
`archive.archlinux.org`, at `scripts/make-rootfs.sh:46`, rather than hundreds of
hashes. That solves reproducibility, not the trust root, and it is Arch only: the
ARM and RISC-V ports publish no equivalent archive. See
[`../references/archlinux-docker.md`](../references/archlinux-docker.md).

### 3. The ARM rollback decision

Measured and **not decided**. This is the smallest outstanding item and the one
with a recorded obligation: ⭐ **a recorded decision is an acceptable outcome,
silence is not.**

The exposure, re-measured 2026-08-26:

```bash
for a in amd64 arm64 armv7 riscv64; do
  printf '%-9s http=%s https=%s\n' "$a" \
    "$(awk '/^Server[[:space:]]*=[[:space:]]*http:\/\//' rootfs/$a/etc/pacman.d/mirrorlist | wc -l)" \
    "$(awk '/^Server[[:space:]]*=[[:space:]]*https:\/\//' rootfs/$a/etc/pacman.d/mirrorlist | wc -l)"
done
```

```
amd64     http=0   https=13
arm64     http=10  https=3
armv7     http=10  https=3
riscv64   http=0   https=7
```

20 of 46 entries are plain http, all on the two ARM ports. An on-path attacker
there can serve a **stale but validly signed** package set, which is a rollback.
Packages are signed and `SigLevel = Required` catches forgery, so injection is
not the risk; freezing is.

⭐ **Two corrections to the original framing, both measured.**

- The unsigned repository database is **not** ARM-specific. `core.db.sig` is 404
  on Arch proper and Arch RISC-V too, which is what `DatabaseOptional` exists
  for. The differentiator is transport, not signing.
- Dropping plain http is more costly than it looks. The ARM **anchor** is
  `http://mirror.archlinuxarm.org`, which offers no https at all (`https://`
  returns a connection failure), and it is the endpoint Arch Linux ARM
  recommends and the only active entry in the mirror list they ship. The three
  https servers are `fl.us`, `ca.us` and `de3`, all nodes of that same operator.
  So dropping http means dropping the recommended anchor and depending on one
  operator's three nodes.

The options:

- **Drop the plain-http mirrors.** Costs the anchor and geographic spread, as
  above.
- **Add a version floor on the anchor**, so a build refuses to go backwards.
  Groundwork done: the published tag family already carries the anchor version
  (`aarch64-7.1.0.r9.g54d9411-2`), which can be read anonymously from the
  registry, so no state file is needed. `vercmp` is in the Arch image and returns
  1 when the first argument is newer. ⚠ Open questions: the resolve job runs on
  `ubuntu-latest` which has no `vercmp`, so it must come from a container using
  the digest already pinned in the `Dockerfile`; and a legitimate upstream
  downgrade would block the daily publish, which argues for an explicit
  `workflow_dispatch` override rather than a silent pass.
- **Record it and move on.**

### 4. Outage, slow mirror and CVE resilience

- **Every mirror for one architecture down.** Today the build fails, which is
  correct but total. Consider a pinned last-known-good package set as a fallback
  producing an image with a loud annotation saying it is not current.
- **Slow mirrors.** Decide the transfer policy deliberately: connect timeout,
  total timeout, retries, and how many servers pacman may fall through.
- **Emergency CVE patch.** There is no path to publish faster than the daily
  cron, and no way to rebuild one architecture without rebuilding all four.
  Consider a `workflow_dispatch` input naming a single architecture and a reason,
  publishing only that architecture's tags and leaving the index alone until all
  four agree.
- **Mangled and blocked responses.** Seen in this project: a 301 that `-L`
  followed to a 29 second dead end; a `.sig` that was 404 and became a zero byte
  file; a `base.db` that was Zstandard where every sibling is gzip; a mirror
  answering 403 for one path; and a mirror answering 200 from one network and
  403 from another. ⛔ **Every fetch should assume the response is wrong, not
  just absent.** Add tests that feed each shape to the scripts.

### 5. Redundancy for the things with one of something

| single point | today |
| --- | --- |
| the `FROM` digest | one image, one registry |
| the Arch Linux ARM keyring | one mirror path, one package name |
| the anchor package | `pacman` only |
| the riscv64 pool | six hand maintained servers in `mirrors/riscv64.pool` |
| GHCR as the digest staging area | the whole publish depends on it |
| `archlinux.org/mirrors/status/json/` | `scripts/gen-mirrorlist:22`, the only amd64 pool source |
| `raw.githubusercontent.com` ARM mirrorlist | `scripts/gen-mirrorlist:23`, the only ARM pool source |

For each: is a second source possible, and is the failure loud?

⚠ The last two are known to fail. `rate-mirrors` issue 85 records the Arch status
endpoint returning 429 and being unreachable during an infrastructure incident.
The exposure here is bounded because the generator is not part of any image
build, and `mirrors/<arch>.anchors` is written whatever the pool source does.

### 6. More container formats and non-container consumers

⭐ **The framing was "so other tools can import, extract and reuse without
container tooling".** None attempted.

⚠ **Ships together with task 2.** The static `pacman` per architecture and the
bootstrap guide are release assets too, so build the release once and put all of
it in the same place rather than adding a second mechanism later.

- A release asset per architecture carrying the **rootfs tarball**, with a sha256
  and the evidence file beside it. That is the artefact ArchPOWER, Arch Linux ARM
  and Arch RISC-V all publish and this project does not.
- The **bootstrap set** as a release asset: the resolved package list with
  versions and hashes, so a third party can rebuild the same root without this
  repository's tooling. ⭐ `scripts/gen-evidence` already produces most of it.
- An **OCI layout directory** or `docker save` archive for air-gapped consumers.
- A **manifest of manifests**: one small JSON at a stable URL listing every tag,
  its digest, its platform and its anchor version.
- ⚠ Check what `pkgforge/alpine` and the sibling images publish before inventing
  a shape. Matching the org is worth more than being clever.

⭐ **The release mechanics are mined.** `pkgforge-dev/cross-libc-dlopen`
`.github/workflows/release.yml`, 250 lines, is the pattern to follow:

- triggers on `tags: ['v*']`; a `workflow_dispatch` run builds and uploads for
  inspection and **stops**, so a manual run cannot create a release;
- ⛔ **the body is generated**, by `scripts/release-notes.sh` reading
  `build-manifest.json`, so the release and the manifest cannot disagree. Nothing
  in the body is typed at release time;
- it refuses a tag whose commit never reached the default branch;
- `fetch-depth: 0`, because the changelog is `git log` between this tag and the
  one before it;
- `permissions: contents: write` only on the publishing job.

⚠ **This repository has no releases yet**, so there is nothing to fix, only to
build. ⚠ With a single-commit history a `git log` changelog is degenerate until
there is a second tag; generate the body from the manifest, as the reference
does.

### 7. Faster CI

Baseline: **245 seconds** wall clock on run `32992678276`, four builds in
parallel, no disk pressure. Optimise against that number, not a guess.

- **Native arm64 runners.** `vars.ARM64_RUNNER` is unset and the matrix already
  reads it. ⚠ An unavailable label queues forever, so verify access first.
- **Skip publishing when nothing changed.** The cron runs daily and tags by date,
  so an unchanged package set still mints a new tag for a byte-identical image.
  ⭐ The largest cheap saving available. Compare the resolved package set against
  the last published build and skip when it matches. ⚠ Cache the inputs, never
  the verdict. A cached "this passed" is not a pass.
- **A shared package cache across the matrix.** Four jobs download overlapping
  sets. ⛔ But every job in one run must build against the same pinned set, or the
  four architectures are no longer one coherent release.

### 8. The items only the maintainer can apply

[`../maintainer-actions.md`](../maintainer-actions.md) is the list. ⛔ **Do not
apply these without being asked.**

- ⛔ **The GitGuardian secret.** Ask, do not create. Once `GITGUARDIAN_API_KEY`
  exists, add the scanning workflow. ⛔ Do not add the workflow first: one that
  fails every run for a missing secret trains people to ignore a red mark.
- ⛔ **A freshness pull request carries no status check.** Its run is created and
  held at `action_required` because the pull request is opened with the built-in
  `GITHUB_TOKEN`. The required check never reports, so merging takes two
  deliberate actions. Fixing it needs a personal access token or a GitHub App
  installation token, which is a credential and so the maintainer's. Measured in
  `maintainer-actions.md` section 4.
- `default_workflow_permissions` is `write`. Every workflow declares its own, so
  narrowing the default to `read` is safe in principle and untested in practice.
- The `debug` branch holds nothing unique. Proposed for deletion, not deleted.
- ⚠ **Forks.** The maintainer is contacting fork owners so the repository can be
  detached. ⛔ Nothing in the repository changes for it.

### 9. Reviews

⛔ **Three is the floor, five is better**, once the work is done and CI is green.
Each review states its lens, what it looked at, what it found, and what it did
**not** look at. ⭐ **A review that finds nothing must say what it ruled out**, or
it is not a review. ⭐ Each also carries a change summary: files touched, lines
added and removed.

Eight lenses are used, in [`../reviews/`](../reviews/). ⛔ **Do not repeat them:**

1. a consumer who upgrades blind
2. an attacker at build time
3. the day upstream breaks
4. a maintainer six months from now
5. the tests themselves
6. somebody auditing a repository with one commit
7. a consumer who reads the package database
8. the next session, starting cold

⭐ **Lenses that fit the work still outstanding**, none of them used: a consumer
who never touches a registry, once releases exist; whoever holds the static
`pacman` and no base image, once task 2 lands; and an operator during a mirror
outage, once task 4 is decided.

---

## Working notes

### This machine

| item | state |
| --- | --- |
| host | Windows 11, Git Bash and PowerShell |
| podman | machine `podman-machine-default`, WSL2. ⚠ `podman machine start` first |
| cross-arch | amd64, arm64, arm/v7, riscv64, 386, ppc64le, s390x all run under emulation |
| `gh` | authenticated, admin on the repository |
| absent | `pip`, `pyyaml`, `zstd`, `bsdtar`, `shellcheck`, `actionlint`. The last two run in containers |

⚠ **Prefix every container and `gh` command in Git Bash** with
`MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'`, or MSYS rewrites paths inside
arguments.

⛔ **The `gh` token has no `packages` scope.** Read public tags anonymously:

```bash
TOKEN=$(curl -s "https://ghcr.io/token?scope=repository:pkgforge-dev/archlinux:pull&service=ghcr.io" | jq -r .token)
curl -s -H "Authorization: Bearer $TOKEN" "https://ghcr.io/v2/pkgforge-dev/archlinux/tags/list?n=1000" | jq -r '.tags | length'
```

⚠ Docker Hub's `.count` on page one is not the tag count. It read 0 against a
real figure of 26. Follow `.next` to the end.

### The two linters

```bash
podman run --rm -v "$PWD:/repo:ro" -w /repo docker.io/rhysd/actionlint:latest -verbose
podman run --rm -v "$PWD:/mnt:ro" -w /mnt docker.io/koalaman/shellcheck:stable \
  --shell=bash --external-sources tests/run.sh tests/lib/harness.sh tests/static/*.sh \
  tests/image/*.sh scripts/* bootstrap/any/usr/local/bin/* examples/*.sh
```

⚠ **actionlint writes findings to stdout and `-verbose` to stderr.** Capture both
or a clean run looks like it read nothing.

### Running the tests

```bash
bash tests/run.sh static
```

```bash
SOURCE_COMMIT="$(git rev-parse HEAD)" BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  bash scripts/gen-evidence amd64 localhost/archlinux:amd64 linux/amd64 .tmp/ev.json
IMAGE=localhost/archlinux:amd64 PLATFORM=linux/amd64 EVIDENCE=.tmp/ev.json bash tests/run.sh image
```

⛔ **The image suite needs `EVIDENCE`.** ⚠ `40-mirrors-reachable.sh` needs network
and takes about 45 seconds.

⭐ **Run the static suite on Linux before pushing**, not only on Windows. One
assertion passed on Windows and failed in CI because only the Windows branch was
ever exercised:

```bash
podman run --rm --platform linux/amd64 -v "$PWD:/repo:ro" -w /repo \
  docker.io/pkgforge/archlinux:latest \
  bash -c 'pacman -Sy --noconfirm --needed git curl jq; REPO_ROOT=/repo bash tests/run.sh static'
```

Build one architecture:

```bash
podman build --platform linux/amd64 --build-arg "IMAGE_VERSION=$(date -u +%Y.%m.%d)" \
  --build-arg "SOURCE_COMMIT=$(git rev-parse HEAD)" \
  --build-arg "BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)" -t localhost/archlinux:amd64 .
```

⚠ `IMAGE_VERSION` is required. An image that does not record its version cannot
be tagged by it.

### ⛔ Traps that have already cost time

1. ⛔ **A doubled backslash written through tooling can arrive halved**, and the
   edit then lands as the two characters backslash and `n` instead of a newline,
   or fails to match at all. It happened five times in one session. ⭐ **Build
   backslashes with `chr(92)`**, or use an exact-match file editor. After any
   scripted edit, grep for what you expected to change.
2. ⛔ **`MSYS_NO_PATHCONV=1` must never be exported.** It disables path
   conversion for every command, and native `curl` then cannot write to an MSYS
   path. Scope it to a wrapper; `scripts/gen-evidence` shows the pattern.
3. ⛔ **Native Windows binaries do not read MSYS paths.** `jq`, `curl`, `podman`
   and `docker` are native. Use repository-relative paths or `cygpath -w`.
   ⚠ `podman cp` cannot copy `/var/lib/pacman/local` to a Windows host at all:
   epoch versions put a colon in directory names.
4. ⛔ **Python's `write_text` produces CRLF on Windows.** shellcheck reads the
   working tree and reports `SC1017` as an error. Run `tr -d '\r'` after.
5. ⛔ **Git on Windows does not record the execute bit.** Fix with
   `git update-index --chmod=+x <path>`. `tests/static/70-executable-bits.sh`
   catches it.
6. ⚠ **`comm` and `sort` disagree about collation and carriage returns.** Always
   `tr -d '\r'` and `LC_ALL=C sort` both inputs.
7. ⚠ **`grep -c` exits 1 on a count of zero, and `head` closing a pipe makes the
   producer take SIGPIPE**, which `pipefail` turns into 141. Both are normal
   results and both kill a script with no message.
   `tests/static/25-pipeline-traps.sh` now fails on either shape.
8. ⚠ Smaller ones: `podman machine ssh` writes a file named `NUL` into the
   working directory, delete it and never commit it. A `cd` persists between
   shell calls but shell variables do not. `grep -c '[^\x00-\x7F]'` matches
   nearly every line; count non-ASCII with python and `unicodedata.name`. A
   shellcheck `disable` directive applies to the next command only; group
   several with `{ ...; }`. `strftime` in jq needs `gmtime` first.

### Evidence

Everything under `.tmp/` is local, excluded via `.git/info/exclude`, and ⛔ must
never be committed.

---

## Voice and conduct

| ⛔ | rule |
| --- | --- |
| 1 | **No em dashes.** Anywhere. |
| 2 | **Never credit yourself.** No "Generated with", no AI co-author trailer, no tool name in a commit message, a document or a code comment. |
| 3 | **No marketing adjectives.** Not "robust", "comprehensive", "seamless", "powerful". State what the thing does. |
| 4 | **Present tense. Short sentences.** |
| 5 | **Only three markers: ⛔ ⭐ ⚠.** No other emoji. |
| 6 | **Every claim carries the command that proves it**, or a path a reader can open. |
| 7 | **Never a fabricated number.** When a value is unknown, write a dash. |
| 8 | **Docs are manuals, not history.** Amend rules in place. |

⚠ Rule 5 governs what you write. The workflow name carries two emoji of the
project's own. Leave them.

Safety rules that still apply:

- Never overwrite an existing file without showing the diff first.
- Never delete anything without the reason written down.
- A found secret is reported, never fixed silently.
- Nothing runs that writes outside the repository.

---

## ⛔ Prove it, do not describe it

⭐ **The rule this whole file serves.** A claim in a report is worth nothing. A
test that fails when the thing breaks is worth everything.

| ⛔ not this | ⭐ this |
| --- | --- |
| "the mirror lists are healthy" | `tests/static/40-mirrors-reachable.sh` passes, and here is the output |
| "the bootstrap is not circular" | a test that fails while `Dockerfile` names a `pkgforge` image |
| "signature checking is on" | a test that fails when `SigLevel = Never` is injected |
| "the tags are correct" | 24 assertions over `scripts/tag-names`, and a run that created them |
| "CI cannot publish a broken image" | a dry run where one architecture was made to fail and no tag moved |

⛔ **A test you have not seen fail is not known to work.** For every test you add
or touch, break the thing it guards and record the failure in
[`../tests-seen-to-fail.md`](../tests-seen-to-fail.md).

⛔ **A number you cannot reproduce does not go in a document.**
