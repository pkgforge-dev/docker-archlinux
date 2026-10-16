# Measurements

Measured facts only. Each row gives its date and its source: the command, the run or the document. Times are UTC. A row from documentation says so. A run id names a run of this repository unless the row names another.

⚠ A fact here is true at its date. Measure it again before a decision depends on it.

## Upstream servers and repositories

| fact | date | source |
| --- | --- | --- |
| `repo.archlinuxpower.org` answers HTTP 403 to a GitHub runner, with a Cloudflare "Just a moment..." page (5379 bytes). The user agents: `curl/8.5.0`, `pacman/7.1.0`, `libalpm/16.0.1`, `Mozilla/5.0` and `docker-archlinux-mirrorlist/1`. It answers 200 from a residential network | 2026-08-28 | curl from a runner and from a workstation |
| the ArchPOWER tracker, issue 69 (closed 2023-12-29): the maintainer blocks whole networks by policy; no issue names GitHub's ranges | 2026-08-29 | the ArchPOWER issue tracker |
| `api.rv.pkgforge.dev` served the same databases as the origin: powerpc64le 724493 B, powerpc 741715 B, powerpc64 684273 B, base-any 504891 B | 2026-08-28 | curl through the proxy and from the origin |
| `api.rv.pkgforge.dev` answers 403 to runners; the origin sees it as `2a06:98c0:3600::103`, Cloudflare's address for requests between Workers | from 2026-09-18; seen 2026-10-13 | run 35332125742, curl |
| ArchPOWER has no second publisher: no mirrorlist package in its four databases, and `archpower/`, `archlinuxpower/` and `pub/archpower/` answer nothing on 42 academic and community mirrors; `robots.txt` of the origin is `Disallow: /` | 2026-10-13 | curl |
| ArchPOWER: `core.db`, `extra.db`, `extra-any` and `community` answer 404; the databases are Zstandard; `any` packages are only in `base/any/base-any.db`; iana-etc is only there; `openssl-3.6.3-1` is in the architecture database | 2026-08-28 | curl, `tar --zstd -tf` |
| ArchPOWER packages: `base/ppc` 3552, `base/ppc64` 3533, `base/ppc64le` 3736, `base/any` 2200 | 2026-08-28 | `tar --zstd -tf` |
| the archpower keyring is in `base/any`, so a probe of `base/powerpc64le` finds no keyring | 2026-08-28 | curl, tar |
| ArchPOWER: `base/powerpc64le` has `pacman-7.1.0.r9.g54d9411-2.2` and `base-4-4.2`; packages carry a detached `.sig`, no `%PGPSIG%` | 2026-08-26 | curl, tar |
| `archive.archlinux.org` answers 200; `archive.archlinuxarm.org` and `archive.archriscv.felixc.at` do not resolve | 2026-08-28 | curl |
| `core.db.sig` answers 404 on Arch Linux, Arch Linux ARM, Arch RISC-V and loong64 | 2026-08-27 | curl |
| the ARM anchor `mirror.archlinuxarm.org` has no https; the 3 https servers `fl.us`, `ca.us` and `de3` belong to the same operator | 2026-08-27 | curl |
| shipped lists: 20 of 46 servers were plain http, all on the two ARM ports; amd64 0 of 13, arm64 10 of 13, armv7 10 of 13, riscv64 0 of 7 | 2026-08-27 | awk over `rootfs/*/etc/pacman.d/mirrorlist` |
| loong64: `core` 293 packages, `extra` 14050; `base` resolves to 137 packages; 5 of 5 probed mirrors answered `core.db` over https | 2026-08-28 | curl, tar |
| loong64: all six servers served the same 90776 B `core.db`; the pool came from `pacman-mirrorlist-loong64-20250718-1-any.pkg.tar.zst` | 2026-08-28 | curl, sha256sum |
| loong64: `mirrors.pku.edu.cn` answers a directory with a JavaScript page of 597 B, so a listing scan finds nothing there; a file under it answers 200 | 2026-08-28 | curl |
| loong64: pacman depends on `pacman-mirrorlist-loong64`, which writes `/etc/pacman.d/mirrorlist-loong64`; `base` does not pull `pacman-mirrorlist` | 2026-08-28 | `pacman -Sp --print-format '%n' base` |
| loong64: the lcpu pin named `archlinux-lcpu-keyring-20241126-1`, which the port deleted when it published `20260906-1`; builds failed from 2026-09-06 until the pin moved | 2026-09-06 to 2026-10-13 | run 34024971087 |
| the new lcpu keyring trusts the same 10 fingerprints with the same expiry dates; its signature is a subkey of `8C7F6B7B9B90AE02C2ACB633F0647F18A79089C9`, which the old pin trusts | 2026-10-13 | gpg |
| Arch RISC-V `extra.db` stores `ntk-1.3.1001-4/desc` as a GNU sparse member (`GNU.sparse.major=1`, `minor=0`, `realsize=576`, 576 NUL bytes); the riscv64 evidence lost 3 packages from 2026-10-05 | 2026-10-13 | run 37309541458, tar |
| that `extra.db`: 14716 desc members; GNU tar 1.35 `-O` into a regular file gives 7154 `%FILENAME%` records, into a pipe 14714; bsdtar 3.7.2 exits 1 with `Seek error` | 2026-10-13 | `tar -xOf` |
| GNU tar 1.35 past a sparse desc member of 576 B: 2 of 3 records into a regular file after 2000 B of records, 3 of 3 after 100 B, 3 of 3 through a pipe | 2026-10-16 | a database of 4 desc members made with `tar --sparse --format=posix --sparse-version=1.0 -czf`, then `tar -z -xOf DB --wildcards '*/desc'` into a file and into a pipe, `tr -d '\000'`, and a count of `%NAME%` lines |
| `ca-certificates-mozilla` moved from 3.127-1 to 3.128-1 in a window of at most 63 s, 16:37:48Z to 16:38:51Z, between the build and the evidence | 2026-08-27 | run 33094128354 |
| the Arch status endpoint answered 429 and was unreachable during an Arch infrastructure incident | documented | rate-mirrors issue 85 |

## The GHCR mirror

| fact | date | source |
| --- | --- | --- |
| every database that amd64, arm64, armv7, loong64 and riscv64 read answered 200 through the Worker, after one redirect; x86_64 `core.db.sig` answers 404 | 2026-10-15 | curl |
| lag behind the next server: amd64 core 0 s, extra 4183 s; arm64 core, alarm, aur 0 s, extra 21147 s; armv7 extra 21054 s; loong64 0 s; riscv64 core 0 s, extra 3029 s | 2026-10-15 02:22 | `scripts/check-mirror-lag`, run 38670642456 |
| the mirror read the arm64 `extra.db` at 2026-10-14 23:54 from three Arch Linux ARM mirrors, newest entry 19:57; `mirror.archlinuxarm.org` served packages from 23:31 on at 02:22 | 2026-10-15 | mirror-archlinux run 38656876449 |
| GHCR `powerpc64le/base/base.db`: 724416 B, zstd, 3735 packages, `pacman-7.1.0.r9.g54d9411-2.2`, 3 s; sha256 `80906a82b276158f51d3facb541a512da922bd97002c3b4ba000e0d3854a9342`, the same as the Worker copy | 2026-10-16 | `sh bootstrap/any/usr/local/bin/pacman-oci OUT oci://ghcr.io/pkgforge-dev/mirror-archlinux/powerpc64le/base/base.db` |
| GHCR `powerpc64le/base-any/base-any.db`: 504891 B, 2200 packages, 2 s; sha256 `2df5ce1823a21a694a7140ef3d56fddb0f1157e4b2263d8c8f684662bec6363b` | 2026-10-16 | pacman-oci |
| the newest member is the same on GHCR and the origin: base 2026-08-14 07:58:48, base-any 2026-07-28 12:54:38 | 2026-10-16 | `scripts/check-mirror-lag ppc64le` |
| loong64: the GHCR mirror is behind loongarchlinux.lcpu.dev by 66728 s (core) and 66735 s (extra): `drop` | 2026-10-16 | `scripts/check-mirror-lag loong64` |
| riscv64 `extra`: 21636 s behind riscv.mirror.pkgbuild.com: `keep` | 2026-10-16 | `scripts/check-mirror-lag riscv64` |
| the mirror record, generated 2026-10-16T06:29:50Z: powerpc64le-base and -base-any current, lag_seconds 0, age_seconds 58352; x86_64-extra lag 13424 s, ratio_files 0.99967; riscv64-extra current false, ratio_files 0.99993 | 2026-10-16 | `curl .../mirror-archlinux/status.json \| jq` |
| `resolve-anchor --each ppc64le`: GHCR, the origin and the proxy all gave `7.1.0.r9.g54d9411-2.2` | 2026-10-16 | `scripts/resolve-anchor --each ppc64le` |
| `resolve-anchor --each riscv64`: 8 https servers; mirrors.felixc.at serves `7.1.0.r9.g54d9411-1`, the other 7 serve `-2.1` | 2026-10-16 | `scripts/resolve-anchor --each riscv64` |
| the GHCR mirror line of each keyring pin answered 302 to `pkg-containers.githubusercontent.com`; the file has the sha256 of the pin | 2026-10-16 | curl with and without `-L` |
| `pick-transport` gives `worker` for every port (HTTP 302 from the Worker) | 2026-10-16 | `scripts/pick-transport` |
| `pacman -Sy` through pacman-oci in a ppc64le build stage: 1.66 s for base.db (724416 B), base-any.db (504891 B) and each `.sig` (119 B) | 2026-10-16 | truncated `podman build` with `TRANSPORT=oci` |
| BuildKit v0.25.1 passes the build argument `https://h.invalid/$arch/$repo` unchanged into a `RUN` heredoc | 2026-10-15 | `buildctl-daemonless.sh` |
| libalpm skips a server after 3 errors for the rest of a run (`server_error_limit`) | documented | pacman `lib/libalpm/dload.c` |

## Mirror lists

| fact | date | source |
| --- | --- | --- |
| `gen-mirrorlist all`: 37 s; amd64 40 candidates from status-json, 12 ranked; arm64 and armv7 12 from the ALARM mirrorlist; loong64 5, riscv64 6; PowerPC anchors only | 2026-10-16 | `scripts/gen-mirrorlist all` in the test container |
| with the first pool source closed, the `mirrorlist-package` source through GHCR gave candidates: amd64 39 in 40 s; arm64 and armv7 12 each in 22 s | 2026-10-16 | gen-mirrorlist on a copy |
| `tests/network/40-mirrors-reachable.sh`: 30 of 30 in 70 s; `https://de3.mirror.archlinuxarm.org` (armv7) answered HTTP 000 | 2026-10-16 | `tests/run.sh network 40-mirrors-reachable` |
| with the clock 91 days on, `tests/network/40-mirrors-reachable.sh` passes 19 of 19 and shows each header date. The file with the header age check failed each list | 2026-10-16 | a `date` on PATH that adds 91 days to `date -u +%s`, then this file, and a copy with the header age check |
| the regeneration of 2026-10-01 stopped at the first PowerPC port and refreshed nothing after it | 2026-10-01 | the freshness run of that day |
| the committed PowerPC lists before the GHCR mirror were written by an older generator | 2026-08-28 | the list headers |
| three files under `mirrors/` held eight markers encoded twice | 2026-10-15 | `tests/static/98-text-encoding.sh` |
| the Arch status pool collapsed to 1 of 1166 mirrors under the completion filter | documented | rate-mirrors issue 56 |

## Keyrings

| fact | date | source |
| --- | --- | --- |
| archpower: `archpower-keyring-20260408-1-any.pkg.tar.zst`, 28621 B; 4 primary keys, 3 trusted at level 4, 1 revoked; nearest expiry 2031-02-22 | 2026-08-28 | bsdtar, gpg |
| archpower: current, `archpower-keyring-20260408-1` from GHCR `powerpc/base-any/base-any.db`; `base.db` was read first and has no keyring | 2026-10-16 | `scripts/check-keyring-pin bootstrap/keyrings/archpower.pin` |
| archlinuxarm: current through GHCR `aarch64/core/core.db` | 2026-10-16 | `scripts/check-keyring-pin` |
| archlinux-lcpu: current through GHCR `loong64/core/core.db`; 10 trusted keys; `5CDE9ADCBD04454BAF547A1C40D0304E1192746B` expired 2026-04-24, `60922C5D40F6297BC1616C270A8F993ECADF8CE7` expired 2026-07-14; 8 usable, none expires within a year; `B955F2012D6A161F6D9076AF34BE2B6F4A99C0E9` expires 2027-11-26 | 2026-10-16 | `scripts/check-keyring-pin` |
| loong64 signers of the 293 `core` packages: `A6C02FBE730CD45859B946E15C74AE170BDA1433` 260, `E340D891C0227DFF3D622A74023DA348C36B0A11` 26, `8C7F6B7B9B90AE02C2ACB633F0647F18A79089C9` 6, `65D4986C7904C6DBF2C4DD9A4E4E02B70BA5C468` 1; neither expired key signs one | 2026-08-28 | `gpg --list-packets` |
| loong64: the keyring has 21 keys, 10 trusted; no key in common with the 489 keys of archlinux-keyring; both signing keys are in the keyring they sign | 2026-08-28 | gpg, comm |
| loong64: keys.openpgp.org has the package-signing key with 1 confirmed uid; keyserver.ubuntu.com has both keys; the wiki page that the key's uid names answers 530 | 2026-08-28 | curl |
| loong64: `pacman -r /target -Sy base` under `SigLevel = Required` exits 0, 137 packages, 23405 files, a LoongArch bash | 2026-08-28 | pacman in the published amd64 image |
| with only `archlinux-keyring` populated, `pacman -Sw archlinux-lcpu-keyring` refuses the package as "unknown trust" and exits 1 | 2026-10-13 | pacman |
| the build follows the loong64 keyring forward from a pin renamed to an older version: "followed forward to archlinux-lcpu-keyring-20260906-1-any.pkg.tar.zst, 8 of its trusted keys fully valid" | 2026-10-13 | `install-port-keyring` against the live port |
| i686: `archlinux32-keyring-20251214-1.0`, 5 trusted master keys; master key `A0B250C0FC9FC079EC04ADB7A50C0F20AEC3AF00` expired 2026-01-16; packager key `80EC18799E8BCD375C6E64ABE4D41569196B1160` has 2 of the 3 valid master signatures it needs; `pacman` exits 1 after 365 s with 0 packages; 9 of the 132 `base` packages are refused | 2026-08-26 | pacman, gpg |
| i686: `--marginals-needed 2` moves that packager key from marginal to full validity | 2026-08-26 | gpg |
| archlinuxarm pin: adopted 2026-08-26; its trusted set and expiry measured again | 2026-08-28 | `scripts/check-keyring-pin` |
| the freshness keyring job was red each Monday from 2026-09-07: the check's exit 3 stopped the step under `bash -e` | 2026-09-07 to 2026-10-13 | run 38245829268 |

## Anchors and tags

| fact | date | source |
| --- | --- | --- |
| anchors: amd64 and arm64 `7.1.0.r9.g54d9411-3`; armv7 and loong64 `-2`; the three PowerPC ports `-2.2`; riscv64 `-2.1`; the floor of amd64 and arm64 is `-2` | 2026-10-16 | `scripts/resolve-anchor`, `scripts/check-anchor-floor` |
| GHCR 364 tags, Docker Hub 364 tags; parity 1; 17 of 17 rolling tags with the same digest; 347 of 347 pinned tags present; 149 index tags | 2026-10-16 | `scripts/registry-tags`, `scripts/status-collect` |
| GHCR tags per port (total, rolling, dated, anchor): amd64 30 2 26 2; arm64 30 2 26 2; armv7 45 3 39 3; loong64 28 2 24 2; ppc 22 2 18 2; ppc64 22 2 18 2; ppc64le 22 2 18 2; riscv64 16 1 13 2 | 2026-10-16 | `scripts/status-collect` |
| tag counts before: 161 (2026-08-27), 194 (2026-08-29), 330 (2026-10-13) on each registry | 2026-08-27 to 2026-10-13 | `scripts/registry-tags` |
| `v<date>` was published 5 times on 2026-08-26 and 3 times on 2026-08-28, before `--existing`; `v2026.08.28` went from 5 to 8 platforms | 2026-10-15 | the logs of the `Create tags` jobs |
| the anchor tag moved every day before `--existing`: on GHCR `x86_64`, `x86_64-v2026.10.14` and `x86_64-7.1.0.r9.g54d9411-2` were one digest, `x86_64-v2026.10.13` another | 2026-10-15 | registry reads |
| consumers pin the dated index: 11 code hits for `"pkgforge-dev/archlinux:v2026"`, 9 outside this repository; 0 for a per-port dated tag or an anchor tag | 2026-10-15 | `gh api search/code` |
| dry run 38675434990, a second build of one day: the rolling tags moved, the pinned tags did not; 21 pinned tags kept | 2026-10-15 | run 38675434990 |
| `plan-build --dry-plan`: no `<alias>-v2026.10.16` exists at 09:19, so all 8 ports would build; a dry run targets `-ci` with `publish_hub` false | 2026-10-16 | `scripts/plan-build --dry-plan` |
| `sync-hub --dry-plan`: `summary tags=364 in_step=364 copy=0 move=0 failed=0`, 40 s | 2026-10-16 | `scripts/sync-hub --dry-plan` |
| `gen-manifest ghcr.io/pkgforge-dev/archlinux`: 364 of 364 tags resolved in 68 s with 8 readers | 2026-10-16 | `scripts/gen-manifest` |
| every one of 161 tags on each registry resolves to a manifest (HTTP 200); 7 sampled tags have 0 of 104 blobs missing | 2026-08-27 | curl against both registries |
| `check-anchor-floor`: `ok` for all 8 ports; riscv64 with a lower anchor gives `behind`, exit 3 | 2026-10-16 | `scripts/check-anchor-floor` |
| the floor discriminates per port: arm64 one pkgrel back gives `BEHIND arm64`, exit 3, while amd64 is `ok` | 2026-08-27 | `scripts/check-anchor-floor` |

## The published images

| fact | date | source |
| --- | --- | --- |
| compressed size (sum of 4 layers): amd64 195676464 B, arm64 202075943, armv7 189690691, loong64 207051122, ppc 194351612, ppc64 197398884, ppc64le 203187150, riscv64 221622505 | 2026-10-16 | `scripts/status-collect` |
| the created label: 2026-10-15T10:08:46Z for amd64, arm64, armv7, loong64 and riscv64; 2026-09-05T09:11:41Z for the three PowerPC ports, so 5 of 8 images are current | 2026-10-16 | `scripts/status-collect` |
| `latest` has 8 platforms; the Docker Hub `latest` has the same digest | 2026-10-16 | `scripts/status-collect` |
| the newest tag of the three PowerPC ports is `<alias>-v2026.09.05` (41 days) on GHCR and Docker Hub; every other port and the index `v2026.10.15` | 2026-10-16 | `scripts/check-publish-recency` |
| later the same day: every port but the three PowerPC ports, and the index, at `v2026.10.16` (0 days) on GHCR and Docker Hub; the three PowerPC ports still at `v2026.09.05` (41 days); exit 3 | 2026-10-16 | `scripts/check-publish-recency /tmp/rec`, with the image names read from the env of `build-deploy.yml` |
| no tag moved on either registry from 2026-09-06 to 2026-10-13 (37 days); the newest dated index was `v2026.09.05` | 2026-10-13 | `scripts/registry-tags` |
| scheduled runs of the build workflow: daily to 2026-07-13 (run 29235804728), then none for 45 days to 2026-08-27 (run 33094128354), with every workflow state `active` | 2026-08-29 | `gh api .../runs?event=schedule` |
| the runs API with `event=schedule` named 2026-09-05 as the newest scheduled run, from inside a scheduled run of 2026-10-06 | 2026-10-06 | `gh api` |
| scheduled runs start hours late: two runs of the cron `30 05` started at 17:32Z and 16:36Z | 2026-08-29 | `gh api` |
| the 3 newest scheduled build runs succeeded: 2026-10-15T20:28:17Z, 2026-10-15T10:08:41Z, 2026-10-14T20:52:51Z | 2026-10-16 | `scripts/check-schedules-fired` |
| `freshness.yml`, `status.yml` and `watchdog.yml` have no GitHub record yet: the run list answers 404 | 2026-10-16 | `scripts/check-schedules-fired` |
| a workflow that never ran and is not on the default branch answers 404 on its run list | 2026-10-13 | `gh api` against mirror-archlinux |
| the published image went 59 days stale behind green runs: `continue-on-error` on the build step, `2>/dev/null` on the bootstrap and `\|\| true` | before 2026-08-26 | the history before the rewrite |
| a riscv64 image was published with a CA bundle link that had no target; the build started from its own last image, so it could not repair itself | before 2026-08-26 | the history before the rewrite |
| `{{ json .SBOM }}` of `docker buildx imagetools inspect` is a map keyed by platform for an index of more than one platform, and the SBOM itself for one platform | documented | docker/buildx `util/imagetools/printers.go` |
| the digest of `ghcr.io/pkgforge-dev/archlinux:latest`: `sha256:0a4774dad9b1be24854f2103c1e4621658feb790b37e5a6c788641bab412ef31` | 2026-10-16 14:52 | `PROG=m; . scripts/lib.sh; reg_head ghcr.io pkgforge-dev/archlinux latest` |
| the freshness pacman-static job stopped each Tuesday from 2026-09-22 on a PowerPC 403, so it compared no port | 2026-09-22 to 2026-10-13 | run 38395328839 |
| the newest build run before this record: run 38884226329, a scheduled run, success; amd64 digest `sha256:b04e8ed828fca4e67f893a0df667a3352e5671ffed32d8a5cf8fdcb85bfab4a0`, anchor `7.1.0.r9.g54d9411-3`, 137 packages | 2026-10-16 09:59 | `gh run list`, the artifacts `evidence-amd64` and `digest-amd64` |

## Image contents

| fact | date | source |
| --- | --- | --- |
| with `NoExtract` rules, `base` plus `qt6-base` listed 49035 paths and 25513 were missing (52 %): usr/share/man 18944, locale 4539, doc 1022, i18n 563, X11 236, info 135, gtk-doc 68 | 2026-08-27 | `pacman -Qlq` against the filesystem |
| with no rule: 49035 listed, 1 missing, `/var/lock` (a link to `../run/lock`); the official image has the same link | 2026-08-27 | the same command |
| image size: 521 MiB (`v2026.05.15`), 395 MiB (every rule), 543 MiB (no rule) | 2026-08-27 | `podman image inspect --format '{{.Size}}'` |
| `newuidmap` and `newgidmap` keep `security.capability` (CAP_SETUID, CAP_SETGID); the official image has none | 2026-08-27 | `getfattr -d -m -` |
| 14 files keep a setuid or setgid bit; `/usr/bin/passwd` is `-rwsr-xr-x` | 2026-08-27 | `find / -xdev -perm -4000 -o -perm -2000` |
| `/usr/share/i18n/charmaps` 233 entries (official image 2); `/usr/share/i18n/locales` 371 on amd64 and riscv64, 370 on arm64 and armv7 | 2026-08-27 | ls |
| `locale-gen` prints `done` and an error, and exits 0, for a locale with no definition | documented | archlinux-docker issue 59 |
| `pacman -S filesystem` under podman keeps the runtime's `/etc/hosts` and `/etc/resolv.conf`; the `filesystem` package lists 17 `%BACKUP%` files, both included | 2026-08-27 | podman |
| `/var/lib/pacman/local` has 138 entries on amd64, arm64 and armv7, 136 on riscv64; `pacman -Qq` lists 137 on amd64 | 2026-08-27 | ls, pacman |
| pacman 7.1.0, libalpm 16.0.1: a seccomp profile that answers `ENOSYS` or `EPERM` for the landlock calls still lets `pacman -Sy` and `-S` exit 0 | 2026-08-27 | podman `--security-opt seccomp=` |
| the default PATH is `/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`, the same string as the official image; exiftool lands in `/usr/bin/vendor_perl` | 2026-08-27 | podman |
| `bindir-links`: 30 links for `perl-image-exiftool`, 0 shadow a `/usr/bin` entry; 39106 paths listed, 1 missing | 2026-08-27 | a local build |
| `/etc/pacman.d/gnupg/pubring.gpg` 1371167 B; no `private-keys-v1.d` | 2026-08-27 | ls |
| `/etc/passwd` 18 entries, `/etc/group` 50 | 2026-08-27 | wc |
| systemd 261.2-1 writes `/etc/machine-id` in its `post_install`; a published image held a 33 B ID that every container of the tag shared | 2026-08-27 | podman cp |
| the image stage and the image are the same with and without the `dbsnapshot` stage: 33086 paths and 137 packages | 2026-08-28 | `find / -xdev` and `pacman -Q` in two builds |
| `core.db` exported 130051 B, `extra.db` 8894888 B; the evidence from the snapshot equals the evidence from a fetch | 2026-08-28 | `podman build --target dbsnapshot`, diff |
| the export step takes 1 to 2 s, every layer cached | 2026-08-28 | run 33162764880 |
| `pacman -Q` in a local amd64 build gives the same 137 name and version pairs as `%NAME%` and `%VERSION%` of each `/var/lib/pacman/local/*/desc` | 2026-10-16 | `podman run --rm IMAGE pacman -Q`, and awk over each desc file in the image, then diff |

## Builds and runners

| fact | date | source |
| --- | --- | --- |
| tonistiigi/binfmt has 9 emulators: qemu-aarch64, -arm, -i386, -loongarch64, -mips64, -mips64el, -ppc64le, -riscv64, -s390x; no qemu-ppc and no qemu-ppc64 | 2026-08-28 | `podman export` of the image |
| Ubuntu `qemu-user-static` ships no binfmt descriptions; `update-binfmts --import qemu-ppc` exits 2; the same in Debian trixie | 2026-08-28 | runner, container |
| qemu master `scripts/qemu-binfmt-conf.sh` has 34 emulators, sha256 `5e12ef484b8364e1ba7bae4acda837d2e6320ffbeb7fab341034124553cdb137`; gitlab.com/qemu-project and raw.githubusercontent.com/qemu/qemu give the same file; the table of `scripts/binfmt-register` has the same 34 names, magics and masks | 2026-10-16 | curl, sha256sum, `scripts/binfmt-register --table`, diff |
| `docker/setup-qemu-action` registers `loongarch64` on a GitHub runner | 2026-08-28 | run 33165970427 |
| rootless podman build steps have no `CAP_MKNOD`: `mknod` gives "Operation not permitted"; docker build steps on runners have it | 2026-10-15 | podman run, run 38718147891 |
| build step and job times, before and after the GHCR mirror (s): amd64 136/120 and 201/179; arm64 277/245 and 357/316; armv7 265/231 and 331/303; loong64 257/206 and 324/270; riscv64 300/202 and 383/271; the run 544 and 441 | 2026-10-15 | runs 38549236313 and 38670811239 |
| local builds through the GHCR mirror: amd64 95 s, arm64 170 s, armv7 181 s, loong64 193 s, riscv64 217 s; 137 packages (riscv64 135); 66 of 66 image assertions | 2026-10-15 | podman on a workstation |
| truncated builds through `install-port-keyring`: amd64 46.5 s; ppc64le with `TRANSPORT=oci` 59.7 s | 2026-10-16 | `podman build` of a copy of the Dockerfile that ends after the `install-port-keyring` step |
| a dry run of 8 ports took 456 s end to end, 5 ports 416 s | 2026-08-28 | runs 33195922986, 33165970427 |
| the image digests of the pins: tonistiigi/binfmt:latest `sha256:400a4873b838d1b89194d982c45e5fb3cda4593fbfd7e08a02e76b03b21166f0`; moby/buildkit:buildx-stable-1 `sha256:cec9f139f45e93c5c69c60f8b07cfad9f43f4ef6b6a6cd917527fea5ff2e3dea`; library/archlinux:latest `sha256:3c64b538588416593f69a1aebd2f2ec0f2541b29159f32556fa7def2167147a0` | 2026-10-16 | `reg_head docker.io` |
| image pins: 5, all current; tag push ages `archlinux:latest` 4 days, `registry:3` 17 days, `busybox:latest` 23 days | 2026-10-16 | `scripts/check-image-pins --max-age 14` |
| `pick-base-image`: docker.io serves the digest of the base image, and of the buildkit image | 2026-10-16 | `scripts/pick-base-image`, and `scripts/pick-base-image --image` with the buildkit pin of `build-deploy.yml` |
| `moby/buildkit:buildx-stable-1` at `sha256:cec9f139f45e93c5c69c60f8b07cfad9f43f4ef6b6a6cd917527fea5ff2e3dea`: docker.io and mirror.gcr.io answer 200 with that digest; public.ecr.aws (`docker/moby/buildkit`) and ghcr.io answer 404 | 2026-10-16 | `PROG=m; . scripts/lib.sh; reg_head REGISTRY REPO DIGEST` |
| pacman 7.1.0, a database that no server gives, through curl: `failed retrieving file` lines, then `failed to synchronize all databases (download library error)` | 2026-10-16 | `pacman -Sy` in the test container with `--network none`, against `file://` and `http://127.0.0.1:9` servers |
| the same through an XferCommand: only `failed to synchronize all databases (error invoking external downloader)` | 2026-10-16 | the same, with an `XferCommand` |
| a package that no server gives: through curl `warning: failed to retrieve some files`, then `failed to commit transaction (download library error)`; through an XferCommand `failed to commit transaction (error invoking external downloader)` | 2026-10-16 | `pacman -S`, the same way |
| a package that the first server fails and the second gives: `error: failed retrieving file ...`, and pacman exits 0 | 2026-10-16 | `pacman -S`, the same way |
| a database with a bad signature: `failed to synchronize all databases (invalid or corrupted database (PGP signature))` | 2026-10-16 | `pacman -Sy`, the same way |

## The static pacman

| fact | date | source |
| --- | --- | --- |
| the `v7.1.0` tag object `208ff2b57e49f2851ce7bca5ac9090c6cb8aa746` points at commit `5683f8477a0afcc6b331766175a83445b2dcfe89`, 9 commits behind `54d94116`; it is signed by Allan McRae, signature time 1761996827 (2025-11-01) | 2026-10-16 | `git verify-tag --raw v7.1.0` |
| a depth 1 fetch of the tag: 3 s, `.git` 1.7 MB (1.6 MB and 2.4 s on 2026-08-29) | 2026-10-16 | git fetch |
| keys.openpgp.org gives the Allan McRae key with no user ID, so gpg skips it, and has no Andrew Gregory key; pgpkeys.eu gives both keys with user IDs; keys.mailvelope.com has none | 2026-10-16 | `gpg --keyserver K --recv-keys FPR` |
| `B8151B117037781095514CA7BBDFFC92306B1121` (Andrew Gregory) expired at 1659417244 (2022-08-02); `6645B0A8C7005E78DB1D7864F99FFE0FEAE999BD` (Allan McRae) has no expiry | 2026-10-16 | gpg |
| the archlinux.org WKD serves allan@archlinux.org, not andrew@archlinux.org | 2026-10-16 | `gpg --auto-key-locate clear,wkd --locate-external-keys` |
| every `mirror` line of `sources.pin` serves the pinned sha256 | 2026-10-16 | `curl -sSL --connect-timeout 20 --max-time 300 -o f URL && sha256sum f` |
| not usable as a mirror: tukaani.org/xz and www.openssl.org/source redirect to GitHub; openssl-library.org 404; ftp.heanet.ie gnupg 404; sourceware.mirrors.tds.net does not resolve; zigmirror.hryx.net 0 B in 300 s; pkg.earth HTTP/2 stream reset; Alpine edge has no zstd-1.5.7; Gentoo has no zlib-1.3.2, libarchive-3.8.9, curl-8.21.0 or libassuan-3.0.2 | 2026-10-16 | curl |
| the hashes of `sources.pin` were measured by fetching each URL | 2026-08-28 | curl, sha256sum |
| the two signer names of the pin were swapped until 2026-08-29; the first check that read them found it | 2026-08-29 | `scripts/build-pacman-static` |
| the vendored pacman-oci sha256 `80e7a87d...` equals the copy on the default branch of mirror-archlinux; the newest commit that changed `client/pacman-oci` is `5963104a...`, and the pin names `89d9e705...` | 2026-10-16 | the freshness `pacman-oci` step |
| amd64 build: 505 s, meson 1.12.1; 15912120 B, sha256 `2da05f6d09d0bb58ee78e27e44ebd7292bbfe739c58e736c71057b4cf68830c4`; `Pacman v7.1.0 - libalpm v16.0.1`; no `PT_INTERP` | 2026-10-16 | `WORK=/tmp/ps OUT=/out/dist scripts/build-pacman-static amd64` |
| binary sizes (B): amd64 15910176, arm64 15897928, armv7 14048036, loong64 15223104, riscv64 24082528, ppc 14827576, ppc64 16520608, ppc64le 16538280; each printed `Pacman v7.1.0 - libalpm v16.0.1` under its emulator | 2026-08-28 | `scripts/build-pacman-static` |
| two amd64 builds from one pin gave two sha256 values, both 15910176 B | 2026-08-28 | sha256sum |
| `sizeof(pthread_mutex_t)`: 40, alignment 8, on x86_64, aarch64, riscv64, loongarch64, powerpc64, powerpc64le; 24, alignment 4, on arm and powerpc | 2026-08-28 | `readelf` on a compiled object |
| the runner's apt meson 1.3.2 stops with "Unable to detect linker" after 168 objects compiled | 2026-08-29 | run 33208408451 |
| `step` wrote to stdout, and all 8 ports failed at zlib configure | 2026-08-29 | run 33206329907 |
| curl's getifaddrs configure test ran more than 26 minutes under qemu-ppc when `--build` was not given | 2026-08-28 | a local build |
| the 8-port run of `pacman-static.yml` took 6 min 16 s | 2026-08-28 | run 33210060549 |
| meson 1.10.1 pinned, 1.12.1 newest; shellcheck 0.11.0, actionlint 1.7.12, jq 1.8.2 and yq 4.54.1 current | 2026-10-16 | `scripts/install-tools --pins` against the latest releases |
| sources behind upstream: xz 5.8.3 to 5.8.4, openssl 3.5.8 to 3.5.9, libarchive 3.8.9 to 3.8.10, curl 8.21.0 to 8.23.0, gpgme 2.1.2 to 2.2.0, zig 0.16.0 to 0.17.0; zlib, bzip2, zstd, libgpg-error, libassuan and libseccomp current | 2026-10-16 | the freshness `sources` step |
| the licence fields of the Arch Linux packages of the sources | 2026-10-16 | `%LICENSE%` of x86_64 `core.db` and `extra.db` through the GHCR mirror; `THIRD-PARTY.md` |
| pacman 7.1.0 with `-r /tmp/r`: Conf File `/etc/pacman.conf`, Cache Dirs `/var/cache/pacman/pkg/`, Hook Dirs `/tmp/r/usr/share/libalpm/hooks/` and `/etc/pacman.d/hooks/`, GPG Dir `/etc/pacman.d/gnupg/`; DB Path, Lock File and Log File are under `/tmp/r` | 2026-10-16 | `pacman -r /tmp/r -v -Q` in the test container |
| with no `/etc/pacman.conf`, `pacman -r /tmp/r` stops: "config file /etc/pacman.conf could not be read"; an `Include` of a missing file stops the same way; a `--hookdir` that does not exist stops: "failed to resolve path ... passed to '--hookdir'" | 2026-10-16 | `pacman -r /tmp/r -Q`, `pacman --config FILE -r /tmp/r -Q`, `pacman -r /tmp/r --hookdir /tmp/r/nohooks -Q` |
| the GnuPG directory and the hook directory are not relative to the root, even with `--root`; only the database and the log are put under it | documented | pacman `src/pacman/conf.c` at commit `54d94116` |

## Releases

| fact | date | source |
| --- | --- | --- |
| `v0.1.0`: 50 assets, 3284077162 B (3132 MiB); `manifest.json` 194 tags, 194 resolved | 2026-08-29 | `gh api .../releases/tags/v0.1.0`, run 33213236059 |
| amd64: `rootfs-amd64.tar.gz` 188542400 B, `oci-amd64.tar.gz` 189231028 B, `bootstrap-set-amd64.txt` 19304 B (137 packages), `manifest.json` 56936 B (176 tags), gzip level 9 | 2026-08-29 | stat |
| gen-evidence chose podman on a runner that has podman and docker, and all 8 rootfs jobs failed | 2026-08-29 | run 33211181473 |
| a local image that was never pushed has no `RepoDigests` | 2026-08-29 | run 33212195947 |
| the only release is `v0.1.0` | 2026-10-16 | `gh release list` |

## The status site

| fact | date | source |
| --- | --- | --- |
| a live collect of 8 ports: exit 0, parity 1, 40 runs read, 272 s (282 s at 05:45:26Z) | 2026-10-16 09:13:35 | `GITHUB_REPOSITORY=pkgforge-dev/docker-archlinux STATUS_ARTIFACTS=0 STATUS_BUDGET=1500 scripts/status-collect OUT` |
| the newest `Build <arch>` jobs took 3 to 10 s, all success | 2026-10-16 | run 38802203230 |
| one history line for 8 ports is about 860 B, so 2000 lines are about 1.7 MB; the site is 424 KiB with 44 SVG files | 2026-10-16 | `scripts/status-render` |
| headless Edge has a narrowest window of 496 px; at 375 px in an iframe the page has no horizontal scroll | 2026-10-16 | `--window-size=390,800` |

## Tests and tools

| fact | date | source |
| --- | --- | --- |
| the static suite: 49 files; `-j 4` 82 s, `-j 1` 205 s, with two other test containers running; a later `-j 4` run 58 s | 2026-10-16 | `TESTS_REQUIRE_TOOLS=1 tests/run.sh -j N static` in the test container (`tests/Containerfile`) |
| the longest static file is `76-status-collect`: 54 s at `-j 1`, 67 s at `-j 4` | 2026-10-16 | the same |
| `scripts/install-tools` for five tools, first run: 17.8 s | 2026-10-16 | `time scripts/install-tools /tmp/tools shellcheck actionlint jq yq meson` |
| meson 1.10.1 from `scripts/install-tools` (the source tarball, sha256 checked): `meson setup`, `ninja` and the regeneration after a `meson.build` change pass for a one-file C project. The run was in the published amd64 image, with `ninja` and `gcc` from pacman | 2026-10-16 | `scripts/install-tools /tmp/tools meson`, then `meson setup b && ninja -C b` |
| the static suite: 49 files, 1041 assertions, 0 failed, 0 skipped, 64 s at `-j 4`; on the read-only working tree, 113 s | 2026-10-16 | `TESTS_REQUIRE_TOOLS=1 tests/run.sh -j 4 static` in the test container |
| the network suite: 1 file, 30 of 30, 78 s | 2026-10-16 | `TESTS_REQUIRE_TOOLS=1 tests/run.sh -j 4 network` in the test container |
| the test container from `tests/Containerfile`: built in 46 s, 961 MB; the static suite in it, 49 files, 0 failed, 32 s at `-j 6` | 2026-10-16 | `podman build -f tests/Containerfile -t localhost/dal-test tests`, then `TESTS_REQUIRE_TOOLS=1 tests/run.sh -j 6 static` |
| actionlint 1.7.12 refuses a `queue` key in a `concurrency` block: `unexpected key "queue" for "concurrency" section` | 2026-10-16 | `actionlint` |
| `seq 1 2000000 \| head -n 40 \| tail -1` under pipefail gives 141; `grep -c '^x' /dev/null` gives 1 | documented in `tests/static/25-pipeline-traps.sh` | bash |
| renovate 44.126.0 `renovate-config-validator --strict`: "Config validated successfully" | 2026-10-16 | `npx --yes --package renovate@44.126.0 -- renovate-config-validator --strict` in `docker.io/library/node` |
| a process start in Git Bash on Windows costs about 165 ms, so do not take timings there | documented | mirror-archlinux `docs/conventions.md` |
| the image suite against the published amd64 image `sha256:b04e8ed8...` and its evidence: 6 files, 66 of 66 assertions | 2026-10-16 | `IMAGE=... PLATFORM=linux/amd64 EVIDENCE=... CONTAINER_RUNTIME=podman tests/run.sh image`, Git Bash and podman 5.8.6 |
| `pacman -Q` in the image writes "warning: database file for 'extra' does not exist" to stderr, because the image has no sync databases; the count on stdout is right | 2026-10-16 | `podman run --rm IMAGE sh -c 'pacman -Q \| wc -l'` |
| actionlint writes its findings to stdout and its `-verbose` lines to stderr; a guard that read only stdout failed each run, so the required check could not pass | before 2026-10-16 | the old `ci.yml` |
| a curl that followed a 301 to a host that did not answer waited 29 s | 2026-08-29 | `tests/static/65-fetch-policy.sh` |
| `gpg --recv-keys` came into the tree, and a scan of curl calls only did not see it | 2026-08-29 | `tests/static/65-fetch-policy.sh` |
| `gen-manifest` read 176 tags | 2026-08-28 | `scripts/gen-manifest` |
