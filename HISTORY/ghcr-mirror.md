# The GHCR mirror as the first server

⭐ **Decided 2026-10-15 by the maintainer.** The five ports that the GHCR
mirror carries read it first, at build time and in the shipped list. The
upstream mirrors stay in the same list, after it. A build compares the mirror
with the next server first and builds without it when it is behind.

## What the mirror is

`pkgforge-dev/mirror-archlinux` copies each port's repositories into GHCR, one
OCI artifact per package file and one per database, and moves a database to
`latest` only after every file it names is on the registry. A Cloudflare Worker at
`ghcr.mirror.archlinux.pkgforge.dev` answers `/$arch/$repo/<file>` with a
redirect to the blob in GitHub's package storage. It serves upstream's own
bytes: a database is upstream's database file, and a package is upstream's
package with upstream's signature.

| port | `$arch` | repositories this image reads | on the mirror |
| --- | --- | --- | --- |
| amd64 | `x86_64` | core, extra | core, extra, multilib |
| arm64 | `aarch64` | core, extra, alarm, aur | the same four |
| armv7 | `armv7h` | core, extra, alarm, aur | the same four |
| loong64 | `loong64` | core, extra | core, extra |
| riscv64 | `riscv64` | core, extra | core, extra |
| ppc, ppc64, ppc64le | | base, base-any | ⛔ none. No runner reaches ArchPOWER, `HISTORY/outage-2026-09.md` |

Every database the five ports read answered 200 through the Worker, after one
redirect, measured 2026-10-15 from a workstation:

```bash
for p in x86_64/core/core.db aarch64/alarm/alarm.db armv7h/aur/aur.db loong64/extra/extra.db riscv64/extra/extra.db; do
  curl -sS -o /dev/null -L --connect-timeout 10 --max-time 60 \
    -w "$p %{http_code} %{num_redirects}\n" "https://ghcr.mirror.archlinux.pkgforge.dev/$p"
done
```

⚠ `core.db.sig` answers 404 for x86_64, as `geo.mirror.pkgbuild.com` does: Arch
does not sign its databases, and the shipped `SigLevel` is
`Required DatabaseOptional`.

## Where it goes in the list

`mirrors/<arch>.anchors` names it first, so `scripts/gen-mirrorlist` writes it
first and never ranks it away. The lists were regenerated on 2026-10-15 with
the generator, so the ranked part below the anchors changed too.

| case | what happens |
| --- | --- |
| the Worker or GHCR does not answer | pacman tries the next `Server` for that file. It is the fall through every mirror list relies on |
| a package is not on the mirror, because pacman read the database from a later server | the Worker answers 404 and pacman tries the next `Server` |
| the mirror stopped following upstream | the build reads the list without it: below |
| a consumer's network blocks it | pacman tries the next `Server`. ⚠ That costs one timeout per file, and after three errors libalpm skips the server for the rest of the run (`server_error_limit` in `lib/libalpm/dload.c`) |

⭐ On arm64 and armv7 the first path is now https. The upstream anchor there,
`mirror.archlinuxarm.org`, serves plain http only, which is what
`HISTORY/arm-rollback.md` is about. `scripts/check-anchor-floor` still guards
the http path.

## A mirror that is behind

pacman takes the first database that arrives, so a mirror that stopped
following upstream would build every image from an old package set, and
nothing would fail. `scripts/check-mirror-lag` runs in the resolve job for
every port, before `scripts/resolve-anchor`:

1. For each section that includes `/etc/pacman.d/mirrorlist`, it reads the
   database from the first server and from the next server that serves a
   readable one.
2. It compares the newest member of each. A member keeps the time its package
   went into the repository, and both servers carry upstream's file byte for
   byte, so the times compare directly.
3. When the first server is more than `MIRROR_LAG_MAX` seconds behind on any
   section, 43200 by default, or serves no database where a later server does,
   it prints `drop <server>`.

The resolve job then passes that server to `scripts/resolve-anchor` as
`SKIP_SERVER`, and to both build steps as a build argument. The `Dockerfile`
runs `drop-server` on the build stage's own list before `pacstrap`. ⛔ The list
the image ships is the copy under `/rootfs`, and it keeps the server.

⚠ **The measure is an upper bound.** It is the time between the newest package
the mirror has and the newest package upstream has. When upstream was quiet for
a while before its newest package, the number is large even when the mirror
synced after the quiet stretch. Measured 2026-10-15 at 02:22Z from a
workstation, and the resolve job of run `38670642456` printed the same values:

| port | section | behind by |
| --- | --- | --- |
| amd64 | core | 0 s |
| amd64 | extra | 4183 s |
| arm64 | core, alarm, aur | 0 s |
| arm64 | extra | 21147 s |
| armv7 | core, alarm, aur | 0 s |
| armv7 | extra | 21054 s |
| loong64 | core, extra | 0 s |
| riscv64 | core | 0 s |
| riscv64 | extra | 3029 s |

```bash
for a in amd64 arm64 armv7 loong64 riscv64; do scripts/check-mirror-lag "$a"; done
```

The mirror syncs every three hours, and it reads upstream through mirrors that
lag the anchor themselves. Its sync at 2026-10-14 23:54Z, run `38656876449` in
`pkgforge-dev/mirror-archlinux`, read the arm64 `extra.db` from three Arch Linux
ARM mirrors and found it equal to the one it had promoted, newest entry 19:57Z.
At 02:22Z `mirror.archlinuxarm.org` served packages added from 23:31Z on. So
the arm64 and armv7 values are real lag, about one sync and the lag of those
mirrors. 43200 is about twice the largest value measured.

```bash
gh run view 38656876449 --repo pkgforge-dev/mirror-archlinux --log | grep 'plan: aarch64-extra: current'
```

⚠ A drop costs nothing but speed: the build reads the upstream mirrors, which
is what every build did before.

## Measured

Local, podman on the maintainer's workstation, 2026-10-15:

| port | build | evidence | image suite | `pacman -Sw nano` in the image, `--debug` |
| --- | --- | --- | --- | --- |
| amd64 | 95 s | 137 packages | 66 of 66 | `core.db` and the package from the Worker, response code 200 |
| arm64 | 170 s | 137 packages | 66 of 66 | the package and its `.sig` from the Worker, 200 each |
| armv7 | 181 s | 137 packages | 66 of 66 | the package and its `.sig` from the Worker, 200 each |
| loong64 | 193 s | 137 packages | 66 of 66 | the package and its `.sig` from the Worker, 200 each |
| riscv64 | 217 s | 135 packages | 66 of 66 | the package and its `.sig` from the Worker, 200 each |

⚠ riscv64 records 135 packages: `gen-evidence` passes over the damaged member
of Arch RISC-V's `extra.db` and names it, as before this change.
`tests/static/69-evidence-damaged-database.sh`.

```bash
podman run --rm --platform linux/riscv64 IMAGE bash -c 'pacman -Sy --noconfirm >/dev/null && pacman -Sw --noconfirm --debug nano 2>&1 | grep -E "url is|response code"'
```

GitHub, the last scheduled publish before this change, run `38549236313`,
against the dry run of this change, run `38670811239`. One sample of each. The
build step downloads and installs the packages, then runs the last stage under
QEMU on every port but amd64, which is most of the rest:

| port | build step before | build step after | job before | job after |
| --- | --- | --- | --- | --- |
| amd64 | 136 s | 120 s | 201 s | 179 s |
| arm64 | 277 s | 245 s | 357 s | 316 s |
| armv7 | 265 s | 231 s | 331 s | 303 s |
| loong64 | 257 s | 206 s | 324 s | 270 s |
| riscv64 | 300 s | 202 s | 383 s | 271 s |
| the whole run | | | 544 s | 441 s |

```bash
for r in 38549236313 38670811239; do
  gh run view "$r" --json jobs --jq '.jobs[] | select(.name|startswith("Build")) | . as $j | .steps[] | select(.name=="Build and push by digest") | "\($j.name) \(((.completedAt|fromdate)-(.startedAt|fromdate)))s"'
done
```

The dry run built, tested and tagged the five ports in the scratch repository,
and carried the three PowerPC ports, as a scheduled run does. In its resolve
job every port measured `keep`, and every anchor came from the mirror.

## What this does not verify

- ⚠ A consumer outside GitHub's and Cloudflare's reach. Every measurement here
  is from a workstation or a GitHub runner.
- ⚠ The mirror's own health over time. It has its own watchdog in
  `pkgforge-dev/mirror-archlinux`, which opens an issue there for a target that
  stops following upstream. This repository only refuses to build from it.
- ⚠ A `drop` on a real runner. Every port measured `keep`. The drop path is
  proved on fixtures in `tests/static/66-mirror-lag.sh`, and in two local
  amd64 builds: with `SKIP_SERVER` naming the mirror, the build log printed
  `drop-server: the build reads /etc/pacman.d/mirrorlist without` it, the build
  passed, and the image still lists it first. With `SKIP_SERVER` naming a
  prefix of it, the build stopped at that step, as `drop-server` refuses a
  value that is no whole `Server` line.
  ⭐ The CI builder is BuildKit, not buildah. `$arch` and `$repo` reach
  `drop-server` literally there too: BuildKit v0.25.1, run through
  `buildctl-daemonless.sh` on a small Dockerfile, printed the build argument
  `https://h.invalid/$arch/$repo` unchanged from a `RUN` heredoc, with the
  delimiter quoted and unquoted.
- ⚠ A real publish. The dry run tagged the scratch repository only. The first
  scheduled run after this change is the first real publish from the mirror.
