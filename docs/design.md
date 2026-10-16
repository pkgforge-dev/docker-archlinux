# Design

This document gives the invariants of the images, and the failure that each rule prevents. It also describes the port table, the build and publish topology, the tags, the mirrors, the trust roots and the image. The measurements behind the rules are in [measurements.md](measurements.md). What runs by itself and what needs a person is in [operations.md](operations.md).

## The invariants

⛔ An image is published only when each of these is true:

- It was built from the packages of its distribution, under `SigLevel = Required`.
- Its base image is pinned by digest.
- The image suite passed against the pushed digest.

⛔ A pinned tag is made once and never points at another image. No tag and no image is ever deleted from a registry.

⛔ The image withholds nothing. The package database and the file system agree.

⭐ One port that fails never stops another. A port that does not build keeps its last image in `latest`, and one issue says why.

Each rule below keeps one of these true for one way it could fail.

## Rules, and the failure each one prevents

| rule | failure it prevents | where |
| --- | --- | --- |
| The bootstrap stage starts from the official Arch Linux image, pinned by digest. No `FROM` names an image that this repository publishes. | A build from its own last output keeps each defect of that output, and nobody can rebuild it without trust in this project first. | `Dockerfile`, `tests/static/10-bootstrap-not-circular.sh` |
| The build asks for the digest of the base image and of the buildkit image from `docker.io`, then `mirror.gcr.io`. For the base image, a Docker official image, `public.ecr.aws` is third. The same digest is the same bytes. A registry that answers with `ratelimit-remaining: 0` is passed over: its pull limit is used up. ⚠ The limit can run out between the probe and the pull. | One registry outage or one used-up pull limit stops every build. | `scripts/pick-base-image` |
| Each shipped `pacman.conf` sets `SigLevel = Required DatabaseOptional`. No SigLevel is `Never`. | A forged or unsigned package installs. Most ports do not sign their databases, so `DatabaseOptional` is necessary. | `rootfs/*/etc/pacman.conf`, `tests/static/30-signature-checking-on.sh` |
| A port whose keys are not in `archlinux-keyring` has a keyring pin: the package, its sha256, each trusted fingerprint with its expiry. The package is in the tree. | The port deletes a superseded keyring package from its mirrors, and the build cannot get the trust root. | `bootstrap/keyrings/*.pin`, `bootstrap/any/usr/local/bin/install-port-keyring`, `tests/static/88-keyring-pins-vendored.sh` |
| After populate, each pinned key that is not expired must be fully valid. | A key at marginal validity signs nothing that pacman accepts. The keyring installs, and the transaction commits nothing. | `install-port-keyring` |
| The build follows a newer keyring of the port only when pacman verifies its signature with the pinned keys. | A port that adds a key stops every build until a person moves the pin. | `install-port-keyring` |
| A build is refused when its anchor is below the highest anchor already published for that port. | A mirror serves an older package set. It is validly signed, so signatures do not stop the rollback. Some ARM mirrors are plain http. | `scripts/check-anchor-floor` |
| Below the floor, a build goes on in two cases only. `allow_anchor_downgrade` names the port, or at least 2 reachable https servers all serve the lower version. | An upstream revert stops the publish of that port each day. | `scripts/check-anchor-floor` |
| The build reads a list without its first server in two cases: the server is behind the next one by more than `MIRROR_LAG_MAX` (43200 s), or it serves no database where a later server does. The drop also removes each later path to the same files. | pacman takes the first database that arrives. A mirror that stopped following upstream builds every image from an old package set, and nothing fails. | `scripts/check-mirror-lag`, `drop-server` |
| ⛔ A drop and the oci transport change the build stage only. The image ships every server of each list. | A consumer loses a server that is in step again after its next sync. | `Dockerfile`, `use-transport`, `tests/static/43-use-transport.sh` |
| ⭐ The anchors file is the only reviewed input of a mirror list. Its servers are first, in file order, and are never ranked or dropped. | A generated list loses the servers that a person chose. | `scripts/gen-mirrorlist`, `tests/static/41-mirrorlists-start-with-anchors.sh` |
| The lists of a port change together. A refusal leaves every list of the port as it was. | `[base]` and `[base-any]` read lists of two different runs. | `scripts/gen-mirrorlist` |
| The build generates the lists before the build. The committed lists are the fallback. | A list goes stale while it waits for a pull request. | `build-deploy.yml` step `mirrors` |
| ⛔ The databases that pacstrap used are copied out before the sync directory is emptied. The evidence reads that copy. | A package moves between the build and a second fetch. The evidence has a hole, and the publish stops. | `Dockerfile` stage `dbsnapshot`, `tests/static/68-evidence-snapshot.sh` |
| gen-evidence reads the database stream through a pipe, drops NUL bytes and names a damaged member. | GNU tar writes a sparse member to a regular file with a seek, and the seek writes over every record before it. | `scripts/gen-evidence`, `tests/static/69-evidence-damaged-database.sh` |
| The anchor package in the image must have the version that names its tag (`EXPECT_ANCHOR`). | An anchor tag names an image with another pacman. | `scripts/gen-evidence` exit 6 |
| ⛔ The digest record is the last step of a build leg. The publish tags only a digest that it receives. | An image that failed the image suite gets a tag. | `build-deploy.yml` job `build` |
| Each port publishes on its own. A port with no fresh digest keeps the digest its first alias has, in `latest` too. A run with no fresh port moves no tag, but makes `latest` again when it does not hold the image of each first alias. | One unreachable upstream stops the publish of every port. | `scripts/publish-ghcr` |
| The publish stops before any write when the new `latest` would lose a platform of the present `latest`. | A carried digest that does not read drops a platform from the index. | `scripts/publish-ghcr` |
| Each tag that the publish makes is read back. | A write that the registry did not keep goes unnoticed. | `scripts/publish-ghcr` |
| GHCR is the source. Docker Hub gets a copy by digest, in its own job. A copy that a run misses, the next run makes. | A Docker Hub fault stops the GHCR publish, or a missed copy stays missing. | `scripts/sync-hub` |
| No build leg has a secret. The Docker Hub secrets are only in the job `hub`. | A step that runs upstream code reads a credential. | `tests/static/35-publish-targets.sh` |
| A dry run writes only to the scratch images, `<image>-ci`. | A test run moves a published tag. | `scripts/plan-build`, `tests/static/35-publish-targets.sh` |
| ⛔ No step hides a failure: no `\|\| true`, no `set +e`, no `continue-on-error`, no output sent to `/dev/null` for a command that matters. | A failed step is green with no message. | `tests/static/20-no-swallowed-errors.sh` |
| Each curl call has a connect deadline and a total deadline. Each keyserver call has a timeout. | A server that accepts the connection and sends nothing holds the job until the job timeout. | `tests/static/65-fetch-policy.sh` |
| No pipeline under `pipefail` ends in a reader that stops early. | The producer gets SIGPIPE, and the script ends with status 141 and no message. | `tests/static/25-pipeline-traps.sh` |
| No script, workflow or test writes the list of ports. Each reads `scripts/ports`. | A new port needs an edit in many files, and one is forgotten. | `tests/static/75-architecture-set.sh` |
| The watchers measure the outcome (the newest dated tag), not the runs. | A run that publishes nothing and a run that never starts both stay green. | `scripts/check-publish-recency` |

## The port table

Each port is one file, `ports/<arch>.conf`, with one `key = value` line per key. `scripts/ports` reads the files as data. Nothing sources them.

| key | meaning |
| --- | --- |
| `arch` | the Docker architecture name; the file name and the directory name under `rootfs/` and `bootstrap/` |
| `platform` | the OCI platform, `linux/<arch>` or `linux/<arch>/v<n>` |
| `pacman_arch` | the `Architecture` of `pacman.conf`, and `$arch` in a Server URL |
| `aliases` | the tag names of the port, space separated. The first is the `uname -m` name |
| `distribution` | the name of the upstream distribution |
| `homepage` | the URL of the upstream distribution |
| `repos` | the repositories, in `pacman.conf` order. The first is the primary repository, which holds the anchor package |
| `keyring` | the name of the keyring pin in `bootstrap/keyrings/`, or `none` |
| `binfmt` | the first emulator source: `native`, `tonistiigi` or `multiarch` |
| `qemu` | the emulator name, with no `-static` |
| `zig_triple` | the zig target of the static pacman |
| `host_triplet` | the autotools host triplet of the static pacman |
| `openssl_target` | the OpenSSL `Configure` target |
| `elf_machine` | the ELF machine that `readelf -h` prints for a binary of the port |
| `meson_cpu_family` | the meson `cpu_family` of the cross file |
| `endian` | `little` or `big` |

`scripts/ports check` refuses:

- an unknown key, and a missing or repeated key
- two ports with one `pacman_arch` or one alias
- an alias that is `latest`, or that starts with `v` and a digit
- a port with no `rootfs/<arch>/etc/pacman.conf`, `bootstrap/<arch>/etc/bootstrap-packages.txt` or `mirrors/<arch>.anchors`

The ports:

| arch | platform | pacman_arch | aliases | distribution | repos | keyring | binfmt |
| --- | --- | --- | --- | --- | --- | --- | --- |
| amd64 | linux/amd64 | x86_64 | x86_64 amd64 | Arch Linux | core extra | none | native |
| arm64 | linux/arm64 | aarch64 | aarch64 arm64 | Arch Linux ARM | core extra alarm aur | archlinuxarm | tonistiigi |
| armv7 | linux/arm/v7 | armv7h | armv7l armv7h armv7 | Arch Linux ARM | core extra alarm aur | archlinuxarm | tonistiigi |
| loong64 | linux/loong64 | loong64 | loongarch64 loong64 | Arch Linux for Loong64 (LCPU) | core extra | archlinux-lcpu | tonistiigi |
| ppc | linux/ppc | powerpc | ppc powerpc | ArchPOWER | base base-any | archpower | multiarch |
| ppc64 | linux/ppc64 | powerpc64 | ppc64 powerpc64 | ArchPOWER | base base-any | archpower | multiarch |
| ppc64le | linux/ppc64le | powerpc64le | ppc64le powerpc64le | ArchPOWER | base base-any | archpower | tonistiigi |
| riscv64 | linux/riscv64 | riscv64 | riscv64 | Arch Linux RISC-V | core extra | none | tonistiigi |

⚠ `ppc`, `ppc64` and `ppc64le` are three architectures: 32 bit big endian, 64 bit big endian and 64 bit little endian. A binary of one runs on none of the others. On these three ports `uname -m` is the Docker name, so the second alias is the ArchPOWER name.

⚠ The loong64 image records platform `loong64`, and `uname -m` in it prints `loongarch64`.

The files of one port:

- `ports/<arch>.conf`
- `rootfs/<arch>/etc/pacman.conf`
- `rootfs/<arch>/etc/pacman.d/mirrorlist`, and `mirrorlist-<X>` for each other list that pacman.conf includes
- `bootstrap/<arch>/etc/bootstrap-packages.txt`
- `mirrors/<arch>.anchors`, and `mirrors/<arch>.<X>-anchors` for each other list
- `mirrors/<arch>.pool`, optional
- a keyring pin, when the keys of the port are not in `archlinux-keyring`
- for an emulator that `scripts/binfmt-register` does not have, its line in that script and in `tests/fixtures/64-plan-build/binfmt.tsv`

## Build and publish

`.github/workflows/build-deploy.yml`, name `Build and publish`, runs on the crons `30 5 * * *` and `30 17 * * *` and on dispatch.

| job | needs | permissions | timeout (min) | does |
| --- | --- | --- | --- | --- |
| `plan` | | contents read, packages read | 10 | `scripts/plan-build`: the version, the targets, the ports to build, the matrix |
| `gate` | | contents read | 15 | `tests/run.sh static`, at the same time as the legs |
| `build` | plan | contents read, packages write | 75 | one leg per planned port, named `Build <arch>` |
| `publish` | plan, build, gate | contents read, packages write | 30 | `scripts/publish-ghcr`: tags on GHCR. It runs when the plan and the gate passed, on a run with no planned port too |
| `hub` | plan, publish | contents read, packages read | 45 | `scripts/sync-hub`: copies GHCR tags to Docker Hub, after a publish that passed |
| `report` | plan, gate, build, publish, hub | contents read, actions read, issues write | 10 | `scripts/report-build`: the issues `build-<arch>`, `publish-ghcr`, `publish-hub` and the summary table |
| `status` | report | actions write | 5 | starts `status.yml` on the default branch |
| `watch` | | contents read, actions write, issues write | 10 | `scripts/watch-schedules`, then `dispatch-overdue watchdog.yml 1560` and `dispatch-overdue status.yml 180` |

The plan:

- The version is the UTC date, `YYYY.MM.DD`.
- A port builds unless the target already has `<first alias>-v<version>`. So the second cron builds only the ports that did not publish in the first. `force` builds each port again.
- A tag list that cannot be read builds every port. The publish reads the list again before it tags.
- An empty plan is a green run that builds nothing. The `publish` job still runs, and makes `latest` again when it does not hold the image of each first alias. Then `hub` runs, so Docker Hub catches up.

The steps of a build leg, in order:

1. `scripts/binfmt-register ARCH`: the emulator, with the `F` flag.
2. `scripts/pick-base-image`: the registry for the base image digest.
3. `scripts/pick-base-image --image "$BUILDKIT_IMAGE"`: the registry for the buildkit image of the builder.
4. `scripts/gen-mirrorlist ARCH`: exit 0 writes the lists in the checkout of the runner. Any other exit keeps the committed lists.
5. `scripts/pick-transport ARCH`: `worker` or `oci`.
6. `scripts/check-mirror-lag ARCH`: each `drop LIST SERVER` line becomes a `LIST=SERVER` pair of `SKIP_SERVERS`.
7. `scripts/resolve-anchor ARCH`. ⛔ A port that no server answers for fails here: a red leg, never a green skip.
8. `scripts/check-anchor-floor ARCH ANCHOR`. An anchor that no tag can carry fails here too.
9. `docker buildx build`, pushed by digest to the target, with provenance (`mode=max`) and an SBOM. The cache is `type=gha` with `ignore-error=true`.
10. The `dbsnapshot` target, exported to a directory.
11. `scripts/gen-evidence`, with `DB_SNAPSHOT` and `EXPECT_ANCHOR`.
12. `tests/run.sh image` against the pushed digest.
13. The artifacts `evidence-<arch>` (90 days) and `digest-<arch>` (7 days).

The build args of the Dockerfile: `BASE_IMAGE`, `TRANSPORT` (default `worker`), `SKIP_SERVERS` (default empty), `IMAGE_VERSION`, `SOURCE_COMMIT` and `BUILD_DATE`. Its stages: `bootstrap`, `dbsnapshot` and the final unnamed stage.

`digest-<arch>.json` has the keys `arch`, `platform`, `digest`, `anchor`, `transport`, `skip_servers`, `base_image`, `mirrorlist` (`generated` or `committed`) and `built_at`.

The publish, for each port:

| source | when | the digest |
| --- | --- | --- |
| fresh | the leg passed and uploaded its digest record | from `digest-<arch>.json` |
| carried | no digest record | the digest of `<first alias>` on GHCR. 404 is absent. Another answer is tried 3 times, then Docker Hub is asked. When neither answers, the publish stops |
| absent | no digest record, and GHCR has no `<first alias>` | none; the port is not in the index |

Then:

1. Stop before any write in two cases: a tag of a port is not valid (`scripts/tag-names`), or the new `latest` would lose a platform of the present `latest`.
2. Tag each fresh port with `scripts/tag-names --existing`.
3. Make `latest` from every fresh and carried source.
4. Make `v<version>` when it does not exist and a source was built on that version: a fresh port, or a carried port whose `<first alias>-v<version>` has its carried digest.
5. Read back each tag. Then write the fresh ports to the job output `published`.

With no fresh port, the publish compares `latest` with the image of each first alias. When they agree, it writes nothing. Else it makes `latest` again, and reads it back.

`report-build` clears `build-<arch>` only when the job `publish` passed and its output `published` names the port.

Concurrency: the workflow group `build-deploy-<ref>`, with `-dry` added for a dry run. The publish group is `publish-<target image>`, and the hub group `hub-<hub target>`. ⛔ None cancels a run in progress: a publish stopped half way leaves tags moved and the index not. ⚠ GitHub keeps one pending run in a group, and a newer run replaces it. A dry run has its own group, so it never replaces a pending real run.

## Tags

| tag | names | moves |
| --- | --- | --- |
| `latest` | the index of every published platform | each build |
| `v<YYYY.MM.DD>` | the index, made by the first publish of that day | never |
| `<alias>` | one platform, the newest image | each build |
| `<alias>-v<YYYY.MM.DD>` | one platform, the first image of that day | never |
| `<alias>-<anchor>` | one platform, the first image with that pacman version | never |

The anchor is the version of the `pacman` package of the port, for example `7.1.0.r9.g54d9411-2.2`. No port publishes a `VERSION_ID`. pacman is on each port, and its version holds the upstream tag, the commit count after it and the commit. The ports differ in `pkgrel`, so each port has its own anchor.

⛔ The pinned-tag rule: `scripts/tag-names --existing FILE` leaves out each pinned tag that is a line of FILE, the tag list of the target. A tag that is not given to `imagetools create` cannot move. A tag list that cannot be read stops the publish: read as empty, it would move every pinned tag.

All aliases of a port name one manifest. The image names: `ghcr.io/<owner>/archlinux`, where `<owner>` is `github.repository_owner` (`pkgforge-dev`), and `docker.io/pkgforge/archlinux`, which is set once, as `HUB_IMAGE` in `build-deploy.yml`. ⛔ Never rename or drop an alias or a tag family: `pkgforge-dev/mirror-archlinux` pins `ghcr.io/pkgforge-dev/archlinux:<alias>@sha256` for its keyring images (`tests/fixtures/75-architecture-set/consumer-aliases`).

⚠ A per-platform tag is an index with one platform. A pull of a foreign platform needs `--platform`.

⚠ Git tags are a different namespace: `vX.Y.Z` is a version of the tooling and the release assets of this repository, not an image version.

## The rollback floor and the revert rule

`scripts/check-anchor-floor ARCH ANCHOR` runs in each leg before the build.

- The floor is the highest anchor in the published tags `<alias>-<anchor>` of the port, compared with `scripts/vercmp`. `scripts/vercmp` is an awk port of `alpm_pkg_vercmp`; `tests/fixtures/61-vercmp/vectors.tsv` holds the vectors of pacman's `test/util/vercmptest.sh` and more.
- The tag list comes from GHCR, and from Docker Hub when GHCR gives none. With no tag of that shape there is no floor (`nofloor`). When no registry gives a list, the check fails.
- Below the floor the verdict is `behind`, exit 3, unless `ALLOW_ANCHOR_DOWNGRADE` names the port or is `all` (`allowed`), or the revert rule holds (`revert`).
- The revert rule: `scripts/resolve-anchor --each ARCH` shows at least 2 reachable https servers, and each of them serves the lower version. The GHCR mirror counts as one server.

⚠ Limits. The floor reads one package, so a rollback of another package inside one anchor version passes. The first build of a new port has no floor.

## Evidence and the database snapshot

`scripts/gen-evidence ARCH IMAGE PLATFORM OUTPUT` writes one JSON file per image. The package set comes from the pacman database inside the image. The download size, the sha256 and the build date of each package come from the repository databases: the local database has no `%CSIZE%` and no `%SHA256SUM%`.

The top-level keys that `tests/image/40-evidence.sh` checks: `image`, `platform`, `digest`, `built`, `source_commit`, `anchor` (`name`, `version`) and `packages`. Each package entry has `name`, `version`, `size`, `installed_size`, `sha256` and `released`. ⚠ A value that upstream does not publish is a dash, never a guess.

`source_commit` and `built` are the commit and the time of the build of the image. They are `SOURCE_COMMIT` and `BUILD_DATE` when these are set. Else they are the revision and created labels of the image, or `unknown` when a label is absent or empty.

| exit | means |
| --- | --- |
| 0 | written |
| 1 | an error: an argument, an image or a database cannot be read |
| 3 | `DB_SNAPSHOT` cannot be used: not a directory, or a database is missing |
| 4 | the database entry of an installed package is damaged upstream |
| 5 | installed packages are in no database: the snapshot is not that of the image, or the databases moved |
| 6 | the anchor in the image is not `EXPECT_ANCHOR` |

On each refusal, no file is written.

⛔ The order is the mechanism. The Dockerfile copies `/rootfs/var/lib/pacman/sync/*.db` to `/dbsnapshot` before it empties the sync directory. The stage `dbsnapshot` is `FROM scratch` with that copy. The image stage copies only `/rootfs`, so the image does not change. `tests/static/68-evidence-snapshot.sh` checks the order.

⚠ A cache miss on the export is detected, not prevented: gen-evidence then names the packages it cannot find, and the leg fails.

## Mirrors

The first server of each list of each port, PowerPC `[base]` and `[base-any]` included, is the GHCR mirror:

```text
Server = https://ghcr.mirror.archlinux.pkgforge.dev/$arch/$repo
```

`pkgforge-dev/mirror-archlinux` copies the repositories of each port to GHCR. Its Cloudflare Worker answers a file request with a redirect to GitHub's blob host. It serves upstream's own databases and packages, with upstream's signatures. For `[base-any]`, pacman expands the URL to `/<pacman_arch>/base-any/base-any.db`.

The input files of `scripts/gen-mirrorlist`:

| file | holds |
| --- | --- |
| `mirrors/<arch>.anchors` | the first servers of `mirrorlist`, in order. Reviewed. Never ranked or dropped |
| `mirrors/<arch>.<X>-anchors` | the same for `mirrorlist-<X>` |
| `mirrors/<arch>.pool` | optional: the candidates, ranked after the anchors |

A pool line is one of:

```text
Server = SERVER
source = status-json URL
source = mirrorlist URL
source = mirrorlist-package DB_URL PACKAGE PATH
```

The sources are read in file order, and the first that gives candidates is used. `status-json` takes the https mirrors that are active, complete (`MIN_COMPLETION`), synced within `MAX_SYNC_DELAY` and scored. `mirrorlist-package` reads PATH from the package PACKAGE that the database DB_URL names; it is the fallback through the GHCR mirror. A candidate is written only when it answers 200 for the database of the first repository of the list.

gen-mirrorlist keeps `MIN_SERVERS` (2), writes at most `MAX_SERVERS` (12) ranked candidates, and keeps at least half of the ranked servers a list had. At least one anchor of each list must answer. The header records the generation date. Exit 0 written, 3 unchanged, 1 an input or tool error.

### The lag check

`scripts/check-mirror-lag ARCH` prints, for each list that `pacman.conf` includes, one `keep LIST` line, or one `drop LIST SERVER` line for each server the list loses. A drop removes the first server and each later server that serves the same files: the same value, or another path to the GHCR mirror. With `TRANSPORT=oci`, a list has two paths to the GHCR mirror, the `oci://` path and the Worker. ⚠ A list stays when a drop would leave it with no server.

For each repository of the list it compares the newest database member on the first server with a reference:

1. The next server in the same list that serves a readable database and does not serve the same files as the first server.
2. When no later server answers and the first server is the GHCR mirror: the record of the mirror, `MIRROR_STATUS_URL` (default `https://pkgforge-dev.github.io/mirror-archlinux/status.json`), the target `<pacman_arch>-<repo>`, the field `lag_seconds`.

⚠ A record that cannot be read, of another schema, older than `MIRROR_STATUS_MAX_AGE` (default `MIRROR_LAG_MAX`), with no target or with no number is not used. The server stays, with a warning that gives the reason.

⚠ The measure is an upper bound: it is the time between the newest package of each server. A quiet upstream gives a large number for a mirror that is in step.

The Dockerfile runs `drop-server --pairs /etc/pacman.d "$SKIP_SERVERS"` on the build stage only. drop-server refuses a server that is not a whole Server line, and a malformed pair. It also refuses a path as the list name, and a drop that leaves a list empty.

### The transport fallback

The Worker is one path to GHCR. The registry is a second path that does not use Cloudflare:

- `scripts/pick-transport ARCH` asks for the first database of the port. It prints `worker` when the Worker answers 2xx or 3xx, and `oci` when only the registry gives it through `pacman-oci`. When neither answers, it prints `worker`.
- With `TRANSPORT=oci`, `use-transport` adds `XferCommand = /usr/local/bin/pacman-oci %o %u` to the build stage `pacman.conf` and puts `Server = oci://ghcr.io/pkgforge-dev/mirror-archlinux/$arch/$repo` first in each build stage list. pacman-oci gives every other URL to curl, so the other servers stay the fallback.
- `scripts/resolve-anchor` and `scripts/check-mirror-lag` read an `oci://` server through `pacman-oci OUT URL`.
- `bootstrap/any/usr/local/bin/pacman-oci` is a copy of `client/pacman-oci` of mirror-archlinux, byte for byte. `bootstrap/pacman-oci.pin` records the source commit and the sha256. `tests/static/47-pacman-oci-pin.sh` checks the hash.

⛔ The shipped configuration never has an `XferCommand` or an `oci://` server.

### The PowerPC repositories

ArchPOWER has no `core` and no `extra`. `[base]` holds the packages of the architecture, and `[base-any]` the packages with no architecture, at `base/any` on the origin and the proxy. iana-etc is only in `[base-any]`, and the keyring package is there too. The databases are Zstandard. So each PowerPC `pacman.conf` has two sections with their own lists, `mirrorlist` and `mirrorlist-any`. After the GHCR mirror, each list has the origin `repo.archlinuxpower.org` and the read-through proxy `api.rv.pkgforge.dev`, which serves the same files of the same origin.

## Emulation

Every leg runs on an x86_64 runner. The bootstrap stage runs native. The last stage runs target binaries (`pacman-key`, `locale-gen`), so each port but amd64 needs a user mode emulator with the `F` flag.

`scripts/binfmt-register ARCH` takes the emulator from the key `qemu` and the first source from the key `binfmt`:

| source | does |
| --- | --- |
| `native` | nothing; the runner runs the port |
| `tonistiigi` | `tonistiigi/binfmt --install <name>`, pinned by digest; then multiarch, then ubuntu |
| `multiarch` | `multiarch/qemu-user-static --reset -p yes`, pinned by digest; then ubuntu |
| `ubuntu` | the `qemu-user-static` package of the runner, and a registration line that the script writes, flags `F`. The magic and mask come from the table of the script, which holds each emulator of qemu's `scripts/qemu-binfmt-conf.sh` |

After each source, the script reads `/proc/sys/fs/binfmt_misc/<name>`: it must be enabled with the `F` flag. ⚠ Without `F` the kernel opens the emulator inside the build container, where it does not exist. ⚠ tonistiigi/binfmt has no `qemu-ppc` and no `qemu-ppc64`, so the two big endian PowerPC ports start at multiarch.

## Keyring pins

One pin per trust root, in `bootstrap/keyrings/<name>.pin`, with its package beside it. The fields:

| field | holds |
| --- | --- |
| `keyring` | the keyring name, for `pacman-key --populate` |
| `arch` | the `pacman_arch` of each port that uses the pin |
| `mirror` | URLs of the package, tried in order; the GHCR mirror first |
| `package` | the file name of the pinned package |
| `sha256` | its sha256 |
| `trusted` | one line per trusted fingerprint, with its expiry date |

A comment line `# Adopted YYYY-MM-DD.` records the adoption date. `scripts/check-keyring-pin --apply` writes it.

`install-port-keyring` selects the pin by the `Architecture` of the build stage. It checks the sha256, the whole trusted set and each expiry. After populate, each key that the pin dates in the future must be `f` or `u`, and at least one key must be usable. ⚠ A key past its pinned expiry is named and skipped: it can sign nothing that pacman accepts.

`scripts/check-keyring-pin` finds the newest keyring package in the repository database of the port, GHCR mirror first. The trusted set is `same` when the new package trusts the same fingerprints, else `changed`.

| exit | means |
| --- | --- |
| 0 | the pin is current |
| 3 | a newer package, and the pinned one is still served |
| 4 | a newer package, and the pinned one is gone |
| 5 | the pinned name is served with other bytes |
| 6 | no server answered |
| 7 | a newer package that no pinned key signed |
| 1 | the check could not run |

⛔ The trust criterion of a port:

- A keyring that can be had apart from the packages it signs: a keyring package, a fingerprint on a channel that serves no packages, or a chain to `archlinux-keyring`.
- A real `base` transaction that commits under `SigLevel = Required`.

⚠ docker-archlinux keeps its own pin as the trust root for each port. It never takes a keyring from the GHCR mirror. mirror-archlinux reads its PowerPC keyrings from the images of this repository, pinned by digest.

## The image

| property | how |
| --- | --- |
| ⛔ No `NoExtract` rule in any `pacman.conf` | every file of each package is on disk. Each path that `pacman -Ql` lists is on disk, but `/var/lock`: a link to `../run/lock`, which systemd makes |
| The package cache is empty | `package-cleanup.hook` runs `find /var/cache/pacman/pkg -mindepth 1 -delete`. The directory stays: the `pacman` package owns it |
| The sync databases are empty | the first `pacman -Sy` of a consumer gets new ones |
| `/etc/machine-id` is present and empty | `machine-id(5)` asks an image for an empty file. Each container writes its own ID |
| No local signing key | the build runs `pacman-key --init` and `--populate`, then removes `private-keys-v1.d` and `openpgp-revocs.d`. `pacman-key --lsign-key` needs `pacman-key --init` first |
| `PATH` is the PATH of the official image | nothing that resolved before resolves anywhere new |
| `bindir-links.hook` | after a transaction that changes `/usr/bin`, `/usr/local/lib/docker-archlinux/bindir-links` links each executable of `/usr/bin/vendor_perl`, `/usr/bin/site_perl` and `/usr/bin/core_perl` into `/usr/local/bin`. ⛔ A name that already resolves is never linked. A link goes when its target goes, or when a package takes the name |
| Locale | `en_US.UTF-8` is generated. `LANG`, `LANGUAGE` and `LC_ALL` are set. `LC_ALL` overrides `LANG`, and `LANGUAGE` overrides `LC_ALL` for messages |
| `DownloadUser` is not set | pacman downloads as root. Consumer CI often fails when downloads run as an unprivileged user |
| `#DisableSandboxFilesystem`, `#DisableSandboxSyscalls` | present as comments, for a host with no landlock. pacman 7.1 goes on when it cannot apply the sandbox |
| `/etc/os-release` | `write-os-release` writes it with `VERSION_ID` = `IMAGE_VERSION`. No package owns the file |
| Labels | `org.opencontainers.image.version`, `.revision`, `.created`, `.source`, `.licenses` and `.title` |
| No multilib block, and the first `SigLevel` line is the global one | `pkgforge/devscripts` patches the first SigLevel line and uncomments `#[multilib]`; `tests/image/50-consumer-contract.sh` holds the contract |

## The static pacman

`scripts/build-pacman-static ARCH` links pacman statically against musl, for each port, from the inputs of `bootstrap/pacman-static/sources.pin`. It is a release asset. ⛔ The Dockerfile does not read the pin, and no image build fetches anything named in it.

- One zig download is the compiler, the linker, the archiver and the musl source for every target. zig 0.16.0 is pinned for x86_64 and aarch64 hosts.
- 11 libraries: zlib, xz, bzip2, zstd, openssl (3.5 line), libarchive, curl, libgpg-error, libassuan, gpgme and libseccomp. ⚠ No brotli and no nghttp2: the binary uses HTTP/1.1 and does not take the `br` content encoding.
- ⛔ pacman is pinned at a commit, `54d94116164b0b2202c6061c4a59c6f3e70820d8`, the commit of the pacman that the images ship (`g54d9411` in the anchor). The tag `v7.1.0` is an older commit.
- The signed tag `v7.1.0` is pinned by its object sha. The build checks its signature with the pinned signer keys (`bootstrap/pacman-static/keys/`, then two keyservers) and requires a `VALIDSIG` of a signer line. ⚠ The signature covers the tagged commit. The commit sha covers the commits after it.
- Each download is kept only when its sha256 equals the pin. The build tries the URL of the record, then each `mirror` line of that record.
- `--build` and `--host` both go to configure, so autoconf runs no target binary, also when binfmt can run one.
- libgpg-error has a lock object header for one musl target only. The build measures `sizeof(pthread_mutex_t)` for the target with `readelf` on a compiled object and writes the header: 40 bytes, alignment 8, on the 64 bit targets; 24 bytes, alignment 4, on arm and powerpc.
- The checks: the ELF machine of the port, no `PT_INTERP`, and the binary runs under the emulator of the port and prints its version. With no emulator the result is `NOT MEASURED`. `--check-evidence` refuses `NOT VERIFIED`, `SKIPPED`, `NOT MEASURED` and a binary with an interpreter.

⚠ The binary is not byte reproducible from run to run. The inputs are pinned, and the evidence file records them.

`docs/bootstrap-with-pacman-static.md` tells how to build a root with it.

## Releases

`.github/workflows/release.yml` runs on a pushed `v*` tag and on the cron `15 6 1 * *`, which makes the next patch tag after the newest `vX.Y.Z` tag. A dispatch builds the assets and publishes nothing.

| asset | per | is |
| --- | --- | --- |
| `pacman-static-<arch>` | port | the static pacman |
| `pacman-static-<arch>.json` | port | its evidence |
| `rootfs-<arch>.tar.gz` | port | `docker export` of the published image, by digest, gzip |
| `rootfs-<arch>.json` | port | the evidence of that image |
| `bootstrap-set-<arch>.txt` | port | `name version sha256`, one package per line |
| `oci-<arch>.tar.gz` | port | `docker save` of the same image, gzip, for `podman load` |
| `manifest.json` | release | each published tag with its digest, platforms and anchor; schema `docker-archlinux/manifest/1` |
| `SHA256SUMS` | release | every asset but itself |

- The evidence of a rootfs comes from the branch `status` when its digest is the published digest. Else gen-evidence runs again with no `SOURCE_COMMIT` and no `BUILD_DATE`, so it reads them from the labels of the image. The notes say so.
- A port with no published image is left out and named in the notes. It does not fail the release.
- The publish makes a draft at the commit of the run, and uploads with `--clobber` (3 tries). It removes each asset that the run did not make. The step `verify` checks the names and sizes and refuses an extra asset. Then `undraft` publishes the draft.
- A run at the same commit finishes the draft. A draft at another commit is deleted and made again. ⛔ A published release is never changed: the steps `verify` and `undraft` do not run.
- `scripts/release-notes` makes the body from the files only, and refuses a release with a hole.
- The job `report` runs last on a scheduled run. One failed or cancelled job raises `failing-release`. A scheduled run that succeeds clears it.

## The status site

`.github/workflows/status.yml`, name `Status`, cron `23 * * * *`, dispatch, and a start from `build-deploy.yml` after each build.

| job | permissions | does |
| --- | --- | --- |
| `build` | actions read, contents write | `scripts/status-collect`, then `python3 -I scripts/status-render`. On the default branch it pushes the branch `status` as one orphan commit and uploads the Pages artifact |
| `deploy` | pages write, id-token write | checks that Pages has `build_type == workflow`, then `actions/deploy-pages` |
| `keep` | contents read | after a `build` that passed on the default branch: the branch `status` as the artifact `status-history` (90 days). Nothing needs this job, so a fault of the artifact store stops neither the record nor the deploy |
| `check` | contents read, issues write | runs whatever `build` did: `scripts/check-status-record` |

status-collect reads, per port:

- the rolling tag on GHCR: the digest, the labels and the compressed size
- each alias on Docker Hub, by HEAD only, and the tag families
- the newest `Build <arch>` job of the newest 40 runs of this repository on the default branch (schedule, workflow_dispatch or push). A dry run among them is left out: its run name ends in `(dry run)`, or it skipped the job `Watch the schedules`
- the evidence of the published image, and the mirror-archlinux record of each repository

Once: the platforms of `latest` and the parity of the registries. A value that does not read is `null`, and the page says `unknown`, never 0. A parity counts each tag whose digest did not read in `unknown`, and then has `same` and `ratio` null. The whole collect keeps to `STATUS_BUDGET` (600 s).

The branch `status` and Pages hold `index.html`, `status.json` (schema 1), `history.jsonl` (the last 2000 lines), `history.json`, `evidence/<arch>.json`, `evidence/<arch>.digest`, `badges/*.svg`, `charts/*.svg`, `charts/narrow/*.svg` and `.nojekyll`.

| badge | shows |
| --- | --- |
| `badges/<arch>.svg` | image age and state of one port |
| `badges/all.svg` | ports whose image is current, of all ports |
| `badges/latest.svg` | the platforms in `latest` |
| `badges/registries.svg` | the GHCR tags that Docker Hub carries |
| `badges/build.svg` | the last build of each port: passed, of all |
| `badges/size-<arch>.svg` | compressed size of one port |
| `badges/packages-<arch>.svg` | package count of one port |

| chart | shows |
| --- | --- |
| `charts/freshness.svg` | image age per port, against the build interval |
| `charts/size.svg` | compressed and installed size per port |
| `charts/packages.svg` | package count per port |
| `charts/coverage.svg` | tags per port on GHCR and on Docker Hub |
| `charts/build.svg` | job time of the last build per port, with its result |
| `charts/history-age.svg`, `charts/history-size.svg`, `charts/history-build.svg` | the last 30 days |

Each chart is 760 px wide, and 420 px under `charts/narrow/`. Each has a light and a dark style, a fixed colour-blind-safe slot per port, and a glyph with a word for each state. ⚠ A port name may not be a summary badge name: `all`, `latest`, `registries` or `build`.

## References

Nothing of these projects is copied into this repository. The licence of each decides that.

| project | licence | use |
| --- | --- | --- |
| `archlinux/archlinux-docker` | GPL-3.0 | mechanisms only: the `pacman-key` steps of the image stage |
| `lcpu-club` loongarch Dockerfile | GPL-3.0 | none |
| `kth5/archpower` | none | confirms the PowerPC layout: `base` and `base-any` (`cross-compilers/*/pacman.conf`) |
| `Aseem0xff/pacman-static` | 0BSD | the toolchain method: zig cc and musl |
| `fwcd/docker-archlinux` | MIT, holders Stefan Agner 2020 and fwcd 2023 | the origin of this repository; `LICENSE` names both holders |
| `westandskif/rate-mirrors`, commit `98ac2a2698b1c7aed4c4ad15817b710d62ef3b31` | CC BY-NC-SA 3.0 | mechanisms of gen-mirrorlist, written again: the status JSON pool, `completion_pct == 1`, `delay <= 86400` and score order; the ARM pool with commented entries; ranking by connect time; a temporary file then a move; a non-zero exit that leaves the list unchanged |
| `pkgforge/devscripts` `Github/Runners/bootstrap/archlinux.sh` | | the direct consumer; its patches are the contract of `tests/image/50-consumer-contract.sh` |

`THIRD-PARTY.md` lists each file of the tree that comes from another project, with its licence, and the licences of what the release assets ship. The one copied program is `bootstrap/any/usr/local/bin/pacman-oci`, from `pkgforge-dev/mirror-archlinux`, MIT.

## Ports that are not built

i686 (Arch Linux 32) has a keyring package, and its `base` transaction does not commit under `SigLevel = Required`. Its packager key `80EC18799E8BCD375C6E64ABE4D41569196B1160` has 2 valid master signatures of the 3 that gpg's `marginals-needed` asks, because master key `A0B250C0FC9FC079EC04ADB7A50C0F20AEC3AF00` expired. The key stays marginal, and pacman refuses each package it signed. A newer `archlinux32-keyring` that renews that key or adds a signature changes the result. Check it again with a bootstrap, not with this page.
