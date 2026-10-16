# Tests

## The suites

| suite | files | needs |
| --- | --- | --- |
| `static` | `tests/static/*.sh`: the tree, the scripts on fixtures, the workflows read as data | bash, awk, git, jq, yq, shellcheck, actionlint, GNU tar, zstd, gpg, bsdtar, python3. No network and no container runtime |
| `network` | `tests/network/*.sh`: live reads of the mirrors | curl and network |
| `image` | `tests/image/*.sh`: one built image | docker or podman, `IMAGE`, `PLATFORM`; `EVIDENCE` and jq for `40-evidence.sh`; a user mode emulator for a foreign platform |

Output is TAP. Each file is one plan. A failed assertion prints what was measured and a `reproduce:` line. A file with no assertion fails.

### Static

| file | checks |
| --- | --- |
| `tests/static/00-workflow-branch-buildable.sh` | each workflow builds and tests the commit that started it: no `git clone` in a `run:` block; a checkout with a fixed ref has a path; a job checks the tree out before it runs a file of `scripts/` or `tests/`; each image build reads the checked-out tree |
| `tests/static/05-harness.sh` | `tests/lib/harness.sh` and `tests/run.sh`, with counters of its own: TAP counts, `summary`, `need_tool`, `check_eq`, `yaml_json`, `fixture_dir`, `grep_matches`; the runner's FILE argument, `-j`, `--list`, plan check, summary and exit codes; the deadline of a file (`TESTS_FILE_TIMEOUT`), and the output of each file after an early stop |
| `tests/static/10-bootstrap-not-circular.sh` | no `FROM` names an image that this repository publishes. Each `FROM` that is not scratch or a stage is pinned by digest, with the ARG defaults resolved |
| `tests/static/15-actionable-failures.sh` | each `fail` call in `tests/` has a `reproduce:` argument |
| `tests/static/20-no-swallowed-errors.sh` | no `continue-on-error`, `\|\| true`, `set +e` or output sent to `/dev/null` in the workflows, the Dockerfile, `scripts/`, `bootstrap/any/usr/local/bin`, `rootfs/any/usr/local/lib/docker-archlinux` and `tests/`, except the lines of `tests/policy/swallowed-errors.allow`; a dead exception fails |
| `tests/static/25-pipeline-traps.sh` | no pipefail script and no workflow `run:` block pipes into `head`, `grep -q`, `grep -m` or an `awk` that exits, or counts with `grep -c` |
| `tests/static/30-signature-checking-on.sh` | each shipped `pacman.conf` has `SigLevel = Required ...`, and no SigLevel is `Never` |
| `tests/static/35-publish-targets.sh` | `build-deploy.yml` read with yq: job ids, needs, permissions, concurrency, the leg name `Build <arch>`, no secret in a leg; the buildkit pin and its fallback to `mirror.gcr.io`; a publish on a stand-down, the hub gate, and the output `published` that the report reads; the watch step on each exit status of `watch-schedules`; a dry run end to end with fixtures writes only to the scratch images |
| `tests/static/41-mirrorlists-start-with-anchors.sh` | each mirror list starts with its anchors file in order. It has at least 2 servers and one over https, no `oci://` server, and a header date that parses. Each `mirrorlist*` file is included by a `pacman.conf`. Each pool line is valid |
| `tests/static/42-pick-transport.sh` | `scripts/pick-transport` gives `worker` when the Worker answers, `oci` when only the registry answers, `worker` when neither does |
| `tests/static/43-use-transport.sh` | `use-transport` changes the build stage only: `worker` changes nothing, `oci` adds one XferCommand and puts the `oci://` server first in each list, a second run changes nothing; no shipped file has an XferCommand or an `oci://` server |
| `tests/static/44-drop-server.sh` | `drop-server` removes exactly the servers it is given, from the lists it is given, and refuses all else |
| `tests/static/45-pacman-conf-shape.sh` | the shipped `pacman.conf` files: both `DisableSandbox` directives as comments; no `DownloadUser`; `Architecture` is the `pacman_arch` of the port; the same `[options]` apart from `Architecture`; the repositories of the port in order; no multilib, no XferCommand, no NoExtract |
| `tests/static/46-mirror-lag-status.sh` | with no later server, `check-mirror-lag` judges the GHCR mirror by its record; a record that cannot be used keeps the server with a warning; with `TRANSPORT=oci`, a drop names the `oci://` path and the Worker path, and the build stage reads the next server |
| `tests/static/47-pacman-oci-pin.sh` | the vendored pacman-oci has the sha256 of `bootstrap/pacman-oci.pin`, LF line ends and `--version` |
| `tests/static/48-gen-mirrorlist.sh` | `gen-mirrorlist` writes the lists of a port together, anchors first, or leaves each list as it was; the pool sources, the floors, the budget |
| `tests/static/49-resolve-anchor.sh` | `resolve-anchor` reads the lists as the build stage does, with `SKIP_SERVERS` pairs and `TRANSPORT`, and clears a port only when each repository reads; `--each` |
| `tests/static/50-supply-chain.sh` | no remote script piped into a shell; no download made executable with no hash check; no deprecated workflow command; a `# tag:` line above each image pin |
| `tests/static/51-workflow-policy.sh` | the shape of every workflow: permissions, timeouts, pins, checkout credentials, no untrusted value in `run:`, triggers, runners, concurrency, artifacts. No delete of a package. The behaviour of `ci.yml`: the concurrency groups, the verdict of `check`, the `changes` decision with renames |
| `tests/static/55-shipped-hooks.sh` | each shipped pacman hook has the five directives, one `[Trigger]` and one `[Action]`, and a valid `When`. Its `Exec` ships, and it has a `Depends` for each program it runs |
| `tests/static/60-tag-families.sh` | `scripts/tag-names` gives each tag family for each port of `scripts/ports`; `--existing` leaves out each pinned tag on the list |
| `tests/static/61-vercmp.sh` | `scripts/vercmp` against the vectors of pacman's `vercmptest.sh` and more, both ways; `check-anchor-floor` with a tag list fixture: the floor, the allow list, the revert rule, and an anchor that no tag can carry |
| `tests/static/62-publish-ghcr.sh` | `scripts/publish-ghcr --fixtures`: fresh, carried and absent sources; the platform check, the pinned tags, and the tag check before any write; the read back and the output `published`; a run with no fresh port; `scripts/report-build --dry-plan` |
| `tests/static/63-sync-hub.sh` | `scripts/sync-hub --fixtures` copies each missing pinned tag and each moved rolling tag, and stops on a tag list that cannot be read |
| `tests/static/64-plan-build.sh` | `scripts/plan-build` decides the ports and the targets; `scripts/binfmt-register` has the qemu magic and mask of each qemu emulator, and names the files to edit for an emulator it does not have; `scripts/pick-base-image` takes the first registry that serves the digest, with `--image` too, and passes over a registry with `ratelimit-remaining: 0`; `reg_head_limit` of `scripts/lib.sh` against a stand-in curl |
| `tests/static/65-fetch-policy.sh` | each curl call has `--connect-timeout`, and `--max-time` or `--speed-time`; each keyserver call has a timeout |
| `tests/static/66-mirror-lag.sh` | `check-mirror-lag` drops a first server that is behind the next one, for each list of a port. A copy of the first server is not the reference. The Dockerfile applies the drops to the build stage only |
| `tests/static/67-mangled-responses.sh` | `resolve-anchor` names a mirror that answers with the wrong thing, goes to the next one, and reads a Zstandard database of a repository named `base` |
| `tests/static/68-evidence-snapshot.sh` | the Dockerfile copies the databases out before it empties the directory; the leg exports the `dbsnapshot` target to the path that gen-evidence reads; gen-evidence refuses a snapshot it cannot use |
| `tests/static/69-evidence-damaged-database.sh` | gen-evidence reads past a sparse desc member and names it. It refuses a damaged entry of an installed package, and checks `EXPECT_ANCHOR`. With no `SOURCE_COMMIT` and no `BUILD_DATE`, it reads them from the labels of the image |
| `tests/static/70-executable-bits.sh` | a file with a `#!` line is 100755 in the index and a 100755 file has one; each file run by path is tracked and 100755; a sourced file is 100644 with no `#!` line; git ignores python bytecode, and bytecode is not a file run by path |
| `tests/static/75-architecture-set.sh` | `scripts/ports check` passes; each port has its files; no file belongs to a name that is not a port; each alias that mirror-archlinux pulls is an alias; no file outside `ports/`, `tests/fixtures/` and `docs/` names 3 or more ports in one line; each keyring pin names the `pacman_arch` of its ports |
| `tests/static/76-status-collect.sh` | `scripts/status-collect` on a fixture world: the record, the unknown values, the parity, the evidence choice, the history, the budget; dry runs and runs of a fork left out; the `run-name` of `build-deploy.yml` gives the names of the fixture runs; a parity with a digest that did not read is unknown |
| `tests/static/77-status-render.sh` | `scripts/status-render`: every page, chart and badge, valid SVG, no NaN or None, `unknown` for a value that did not read, one inline script, UTC times; the tiles, the build table and the mirror state; a load as a module writes no bytecode into the tree |
| `tests/static/78-status-issues.sh` | `check-status-record` and `check-status-site` raise and clear `status-down`, `registry-drift` and `pages-stale` against a fake gh |
| `tests/static/79-status-workflow.sh` | the shape of `status.yml`, read with yq, and the job `keep`; the step `read`, run with stand-ins, takes no artifact of a run of a fork |
| `tests/static/80-docs-claims.sh` | each example and each fenced bash block of each Markdown file parses; the architecture table and the port badges of `README.md` agree with `scripts/ports`; the README names both images of `build-deploy.yml`; no shipped `pacman.conf` has a NoExtract rule; the history directory is gone, and no document names it; each `localhost/` image of a document is built from a pinned file of the tree; no example installs with a partial upgrade; the keyring block of the bootstrap guide stops on a sha256 mismatch; example 06 counts the SBOM of each platform; the column `needs` of `examples/README.md` names each tool of an example; each script that a source of `measurements.md` runs is in the tree; no sentence of a Markdown file has more than 25 words |
| `tests/static/85-pacman-static-pin.sh` | `bootstrap/pacman-static/sources.pin` pins each input by content; the mirror lines and signer keys agree with it; the build script reads each target fact from `scripts/ports`; `--check-evidence` refuses a bad binary; `pacman-static.yml` reads its matrix from `scripts/ports`; `--zig` gives the zig of the pin, or of `ZIG` |
| `tests/static/88-keyring-pins-vendored.sh` | each keyring pin has its package in the tree, with the sha256, the trusted set and the expiry dates of the pin. Its first mirror line is https |
| `tests/static/89-bot-merge-guard.sh` | `merge-bot-pr --check-diff` reads the diff hunk by hunk, passes a pin bump and refuses more; `renovate.json` merges no major update and matches each image pin; the wiring of `bot-merge.yml`; `merge-bot-pr` reads the required check, against a fake gh; `check-image-pins --seen`, and the record steps of `freshness.yml` |
| `tests/static/90-package-lists.sh` | each bootstrap package list has one valid name on each line, and each port has one. A port with a keyring pin lists its keyring package. `pacstrap-docker` tries a failed download again, and stops at once on any other failure |
| `tests/static/91-schedule-watch.sh` | `watch-schedules`, `check-schedules-fired` and `dispatch-overdue` against a fake gh; a run of a fork, a `pull_request` run, and a run whose head is another repository do not count |
| `tests/static/92-rerun-bot-ci.sh` | `rerun-bot-ci` re-runs only the failed CI of open Renovate pull requests, at most `RERUN_MAX` times per head commit |
| `tests/static/93-track-issue.sh` | `track-issue` finds its issue by the body marker over every open issue, and puts the label back. Only an issue of `TRACK_ISSUE_AUTHOR` with the marker at the start of its body counts. `propose-change` edits and closes only a pull request of the bot |
| `tests/static/94-keyring-database.sh` | `check-keyring-pin` against file:// databases: current, behind, gone, changed bytes, changed set |
| `tests/static/95-publish-watchdog.sh` | `date-age`; `cron-tolerance`, and a tolerance of 60 days or less for every cron of the tree; `check-publish-recency` per port on both registries; no test seam in a workflow; the wiring of `watchdog.yml` and the job `watch`; the `watchdog.yml` step on each exit status of `watch-schedules` |
| `tests/static/96-release-assets.sh` | the release rules of `release.yml` and `pacman-static.yml`; `release-notes`, `gen-bootstrap-set` and `gen-manifest` on fixtures; `CONTAINER_RUNTIME` on each gen-evidence call; the steps `publish` and `verify` against a stand-in gh; the evidence that the release makes again; the job `report` against a stand-in track-issue |
| `tests/static/98-text-encoding.sh` | no text file holds a character encoded twice |
| `tests/static/99-docs-paths.sh` | each cited `docs/` and `tests/` path exists; no file names the history directory; the required check and the workflow name that bot-merge reads; each workflow started with `gh workflow run` has `workflow_dispatch` |

### Network

| file | checks |
| --- | --- |
| `tests/network/40-mirrors-reachable.sh` | each list: at least one anchor answers 200, at least half of the other servers answer 200; the header date is shown, not judged; each keyring pin: a mirror line serves the pinned package |

### Image

| file | checks |
| --- | --- |
| `tests/image/10-shell-present.sh` | `/bin/sh` and `/usr/bin/bash` are there and resolve |
| `tests/image/20-os-release.sh` | `/etc/os-release` has `ID` and `VERSION_ID`, and the label `org.opencontainers.image.version` is `VERSION_ID` |
| `tests/image/30-ca-bundle.sh` | the CA bundle resolves and holds at least `CA_BUNDLE_MIN_CERTS` certificates |
| `tests/image/40-evidence.sh` | the evidence file names this image: the platform, the digest and a full source commit. `source_commit` and `built` are the revision and created labels of the image. The file records each package that pacman in the image lists, with the same version. Each entry is complete, and the anchor is a recorded package |
| `tests/image/50-consumer-contract.sh` | the contract of `pkgforge/devscripts`: the first SigLevel line is global and Required, no multilib block, a populated keyring, `locale-gen` and the UTF-8 charmap, no empty root password |
| `tests/image/60-defect-parity.sh` | the faults of the archlinux-docker tracker, asked of this image: extended attributes, setuid bits, merged `/usr`, alpm, backup files, a quiet login shell; an empty `/etc/machine-id`, locales, no private key, the tools of pacman-key, and the `bindir-links` hook |

Tests `10`, `20`, `30` and `50` create a container, do not start it, and copy paths out. An image whose bootstrap installed nothing still fails them with a clear assertion. ⚠ `40` and `60` run the image: file modes, extended attributes and locale generation cannot be read through `cp`.

## Run the suites

The test container is an image of this repository with the tools of the static suite. `tests/Containerfile` builds it. Run the suites in it with the tree mounted read-only. From Git Bash, `MSYS_NO_PATHCONV=1` is necessary:

```bash
podman build -f tests/Containerfile -t localhost/dal-test tests
MSYS_NO_PATHCONV=1 podman run --rm -v "$PWD:/src:ro" -w /src localhost/dal-test:latest \
  bash -c 'TESTS_REQUIRE_TOOLS=1 tests/run.sh -j 4 static'
```

⚠ Nothing moves the pin of `tests/Containerfile`. Its `pacman -Syu` makes the tools current at each build.

On a host, with the pinned tools:

```bash
scripts/install-tools /tmp/tools
export PATH="/tmp/tools:$PATH"
TESTS_REQUIRE_TOOLS=1 tests/run.sh -j 4 static
tests/run.sh static 80-docs-claims
tests/run.sh network
tests/run.sh --list static
```

⚠ `py_compile` writes bytecode next to the script by default. Give it a prefix outside the tree, as the job `lint` does:

```bash
python3 -I -X pycache_prefix=/tmp/pycache -m py_compile scripts/status-render
```

| form | does |
| --- | --- |
| `tests/run.sh SUITE` | each file of SUITE, in name order |
| `tests/run.sh SUITE FILE...` | the files named: a basename with or without `.sh`, a path, or a number that one file starts with |
| `tests/run.sh -j N SUITE` | N files at once; the output of each file stays together, in file order |
| `tests/run.sh all` | static, then network, then image; takes no FILE |
| `tests/run.sh --list SUITE` | the basename of each file of SUITE |

Each file has a deadline of `TESTS_FILE_TIMEOUT` seconds. A file that does not end within it fails, and the summary says so. When the run stops early (INT, TERM or an error), it prints the output of each file that started, then the summary.

Exit status: 0 each file passed; 1 a file failed, gave no TAP plan line, did not end within its deadline, or no file ran; 2 usage. The summary names each failed file with the command that runs it again.

### The image suite

Against a published image, with its evidence written here. gen-evidence reads the commit and the build time from the labels of the image, and `40-evidence.sh` checks that they agree:

```bash
scripts/gen-evidence amd64 ghcr.io/pkgforge-dev/archlinux:x86_64 linux/amd64 /tmp/evidence.json
IMAGE=ghcr.io/pkgforge-dev/archlinux:x86_64 PLATFORM=linux/amd64 EVIDENCE=/tmp/evidence.json tests/run.sh image
```

⚠ `40-evidence.sh` needs the digest of the image. An image that was built here and never pushed has none. So push a local build to a registry on this host first, as the `image` job of `ci.yml` does. Give the build `SOURCE_COMMIT` and `BUILD_DATE`, so the labels hold a full commit and a time:

```bash
docker run -d --name registry -p 127.0.0.1:5000:5000 \
  docker.io/library/registry:3@sha256:ddf754342cfc8acc51a56d5d0ab6af06826461864460636d8bd5c546dab2a7b8
args=(--platform linux/amd64 --build-arg "IMAGE_VERSION=$(date -u +%Y.%m.%d)"
  --build-arg "SOURCE_COMMIT=$(git rev-parse HEAD)"
  --build-arg "BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)")
docker buildx build "${args[@]}" --load -t localhost:5000/archlinux-ci:amd64 .
docker push localhost:5000/archlinux-ci:amd64
docker buildx build "${args[@]}" --target dbsnapshot --output type=local,dest=/tmp/dbsnapshot .
IMAGE="$(docker image inspect localhost:5000/archlinux-ci:amd64 --format '{{ index .RepoDigests 0 }}')"
DB_SNAPSHOT=/tmp/dbsnapshot scripts/gen-evidence amd64 "$IMAGE" linux/amd64 /tmp/evidence.json
IMAGE="$IMAGE" PLATFORM=linux/amd64 EVIDENCE=/tmp/evidence.json tests/run.sh image
```

### Settings

| variable | default | for |
| --- | --- | --- |
| `IMAGE` | none, required | the image suite |
| `PLATFORM` | none, required | the image suite |
| `EVIDENCE` | none, required | `tests/image/40-evidence.sh` |
| `CONTAINER_RUNTIME` | `podman`, else `docker` | the image suite |
| `TESTS_REQUIRE_TOOLS` | `0`; `1` makes a missing tool a failure | every test that calls `need_tool` |
| `TESTS_FILE_TIMEOUT` | `600` seconds; `1800` for the image suite | `tests/run.sh`: the deadline of each file |
| `CA_BUNDLE_MIN_CERTS` | `1` | `tests/image/30-ca-bundle.sh` |
| `SETUID_MIN` | `10` | `tests/image/60-defect-parity.sh` |
| `PACKAGES_MIN` | `50` | `tests/image/60-defect-parity.sh` |
| `PROFILE_SCRIPTS_MIN` | `1` | `tests/image/60-defect-parity.sh` |
| `CHARMAPS_MIN` | `100` | `tests/image/60-defect-parity.sh` |
| `LOCALE_SOURCES_MIN` | `300` | `tests/image/60-defect-parity.sh` |
| `DIRECTIVES_MIN` | `20` | `tests/static/45-pacman-conf-shape.sh` |
| `MIRRORLIST_PROBE_TIMEOUT` | `20` seconds | `tests/network/40-mirrors-reachable.sh` |

The policy files of the static suite:

| file | holds |
| --- | --- |
| `tests/policy/swallowed-errors.allow` | the exceptions of `20-no-swallowed-errors.sh`: path, fixed string, reason |
| `tests/policy/image-inputs` | the paths whose change makes CI build the images |
| `tests/policy/required-checks` | the check that branch protection waits for: `Static suite and linters` |
| `tests/policy/vendored` | the files that come from another repository and keep their own style |

## CI

`.github/workflows/ci.yml`, name `CI`. `TESTS_REQUIRE_TOOLS=1` for each job. The tools come from `scripts/install-tools`, cached under the hash of the script.

| job | runs |
| --- | --- |
| `static` | `tests/static/05-harness.sh` with bash first, then `tests/run.sh -j 4 static` |
| `lint` | shellcheck over each tracked `#!` file in its dialect, actionlint over each workflow, `python3 -I -m py_compile` over each python file |
| `network` | `tests/run.sh -j 4 network`. ⚠ It reports and does not gate: `check` does not need it, and `bot-merge.yml` reads the check, not the conclusion of the run |
| `changes` | reads the diff against the base, and makes the image matrix from `tests/policy/image-inputs` and `scripts/ports matrix`. A change of the files of one port builds that port. A rename counts as its old path and its new path. A shared input, a dispatch or a base that is not in the clone builds every port |
| `image` | one leg per port, named `Image <arch>`: binfmt-register, pick-base-image, build with `--load`, a push to a registry on the runner, the `dbsnapshot` export, gen-evidence, `tests/run.sh image` |
| `check` | name `Static suite and linters`; needs static, lint, changes and image; runs always; fails when a needed job failed or was cancelled. A skipped image job passes |

`05-harness.sh` runs first, on its own: a `run.sh` that hides failures would also hide its failure.

## Seen to fail

⛔ A test that never failed shows nothing. So each test is seen to fail once:

1. Copy the repository.
2. Change one thing in one file of the copy: the code, a fixture or the tree.
3. Run the one test file with `REPO_ROOT` set to the copy.
4. Record the assertion that failed.

The tree itself is never changed. Each row gives the fault, then the `not ok` line that it gave. A number in a `not ok` line is the number of that run.

### The harness and the runner (05)

| fault | not ok |
| --- | --- |
| the plan-line check of run.sh removed | a file that exits 0 with no TAP plan line fails the run; and the summary names that file |
| `jobs=1` forced | -j 3: 20-second runs while 10-first runs |
| the output streamed with tee | -j 3: the output of each file stays together, in file order |
| the number match off | a number runs the one file that starts with it |
| `export REPO_ROOT` removed | a test file gets REPO_ROOT, the root of the tree (and 15 more) |
| the IMAGE/PLATFORM guard removed | the image suite stops when IMAGE is not set |
| `-j 0` allowed | -j 0 is a usage error |
| `--list` prints paths | --list static names each tests/static/*.sh, in order |
| the rc check removed | a failing file fails the run |
| no job limit | -j1: 20-second starts after 10-first ends |
| `all` without network | all runs the static, network and image files, in that order |
| an unknown suite runs static | an unknown suite is a usage error |
| the summary line removed | the summary names the failed file and the command that runs it alone |
| a FILE never recorded | a named file runs alone |
| the need_tool skip not counted | need_tool records a skip and returns 1 when a tool is missing |
| REQUIRE compared with 2 | need_tool records a failure under TESTS_REQUIRE_TOOLS=1 |
| check_eq with no reproduce | check_eq fails and prints both values and the reproduce line |
| mikefarah yq not found | yaml_json reads a workflow, and on stays a key |
| a wrong fixture path | fixture_dir names tests/fixtures/<test file name without .sh> |
| summary returns 0 when empty | summary returns 1 when no assertion ran |
| grep_matches returns 0 on an error | grep_matches returns 2 when the file cannot be read |
| no deadline, with a fixture file that sleeps 20 s | a file that does not end within TESTS_FILE_TIMEOUT fails the run; the summary names the file that did not end |
| no output after an early stop, with the same fixture | after TERM, the output of a file that ended before is printed; after TERM, the partial output of the file that did not end is printed |
| no summary and a stop of every file after an early stop | after TERM, the summary names the file that did not end; after TERM, no stop is tried on a file that ended |
| no check of the value of TESTS_FILE_TIMEOUT | a TESTS_FILE_TIMEOUT that is not a number is a usage error |

### Policy (00, 10, 15, 20, 25, 50, 65, 70, 98)

| test | fault | not ok |
| --- | --- | --- |
| 00 | a workflow with a `git clone`, a fixed ref with no path, a build of another context, a `scripts/` step before the checkout | a checkout with a fixed ref also has a path; each image build reads the checked-out tree; each job checks the tree out before it runs a file of scripts/ or tests/; no run: block runs git clone |
| 10 | a FROM of an image of this repository, with no digest and no default | each FROM of 6 that is not scratch or a stage is pinned by digest; no FROM of 6 names an image this repository publishes |
| 15 | `fail` calls with no `reproduce:` at the start of a line, after `*)`, after `\|\|` and after `then` | each of 443 fail calls in tests/ carries a reproduce: line, naming each of the 4 |
| 20 | `\|\| true`, `set +e`, `2>/dev/null`, `>/dev/null 2>&1` and `&>/dev/null` in a script | no construct hides a failure in 115 files (each line named) |
| 20 | the same in a test file, and `continue-on-error` in ci.yml | the same assertion, naming those lines |
| 20 | a dead and a malformed exception | each exception has a path, a fixed string and a reason; each exception still matches a line |
| 25 | `\| head`, `\| grep -q`, `\| grep -m`, `\| awk ... exit` and `grep -c` in a pipefail script | none of 105 pipefail scripts ends a pipeline early or counts with grep -c |
| 25 | `\| head -n 1` in a run block | none of 8 workflows ends a pipeline early or counts with grep -c |
| 50 | a remote script piped into sh, a download made executable, `::set-output`, a pin with no `# tag:` line | no remote script is piped into a shell; no download is made executable with no hash check; no workflow uses a deprecated workflow command; each image pinned by digest has its # tag: line at most 3 lines above |
| 65 | a curl with no `--connect-timeout`, one with no `--max-time`, a gpg keyserver call with no timeout | each of 14 curl calls sets --connect-timeout; ... --max-time or --speed-time; each of 3 gpg keyserver calls has a timeout |
| 70 | a tracked script at 100644; a data file at 100755; an untracked script run by path; a sourced file with `#!`; `scripts/lib.sh` out of the index | each tracked file has a #! line exactly when it is 100755; each file run by path is tracked; each file run by path is 100755 in the index; each sourced file is tracked, 100644, with no #! line |
| 70 | `__pycache__/` and `*.pyc` removed from .gitignore | git ignores python bytecode |
| 70 | a file under scripts/__pycache__, with the bytecode filter of the find removed | each of 105 files run by path is tracked |
| 98 | a marker encoded twice | no text file holds a character encoded twice |

### Workflow policy and cited paths (51, 99)

| test | fault | not ok |
| --- | --- | --- |
| 51 | one workflow that breaks each rule | not ok 113 to 126, one line per rule, for example `.github/workflows/zz-bad.yml: top-level permissions: {}` |
| 51 | a workflow that is not YAML | `.github/workflows/zz-broken.yml: reads as YAML` |
| 51 | a `gh api -X DELETE` line | no script or workflow deletes a package version or a manifest |
| 51 | the ci.yml group `ci-${{ github.ref }}` with cancel | a run on main never cancels a run in progress; two pushes to main and a dispatch get three concurrency groups |
| 51 | cancel false | a newer push to a pull request cancels the run of the older one |
| 51 | the group `pr.number \|\| run_id` | the group of a pull request is never the group of another run |
| 51 | check needs network in place of image, with `if: success()` | check needs static, lint and image; check does not need network; check runs when a needed job fails; the verdict reads the result of each needed job |
| 51 | check renamed | a job is named Static suite and linters |
| 51 | `MAY_SKIP` with static | the verdict fails when static was skipped |
| 51 | `success \| cancelled` taken | the verdict fails when X was cancelled, for each of the 4 jobs |
| 51 | the bad arm removed | the verdict fails when X failed, and when X was cancelled |
| 51 | `bad=" x"` | the verdict passes when every needed job passed; passes when the image job was skipped |
| 51 | the n=0 check removed | the verdict fails when it reads no result |
| 51 | the arm for the path of a port removed | changes: a change under rootfs/amd64/ builds amd64 only |
| 51 | `$picked` order changed | changes to two ports build those two, in port order |
| 51 | a dispatch sets `all=0` | a dispatch builds every port |
| 51 | `build=true` always | a diff with no image input builds nothing, with an empty matrix |
| 51 | a shared input sets `all=0` | a shared input builds every port |
| 51 | the BASE check removed | a push with no base builds every port; a base that is not in the clone builds every port |
| 51 | a missing path added to image-inputs; `bootstrap/`, gen-evidence, pick-base-image removed | tests/policy/image-inputs: each line names a path in the tree; covers each COPY source of the Dockerfile; covers each script the image job runs |
| 51 | network with no install step; another lint cache key | network (lint) installs its tools with scripts/install-tools, cached under the hash of the script |
| 51 | `TESTS_REQUIRE_TOOLS` removed | TESTS_REQUIRE_TOOLS is 1 for every job |
| 51 | static runs the network suite; network runs `true` | static runs tests/run.sh static; network runs tests/run.sh network |
| 51 | no py_compile | lint runs shellcheck for bash and sh, actionlint and py_compile |
| 51 | no image `if`, or another matrix | image builds the matrix of the changes job, and only when it says build |
| 51 | no binfmt step, the evidence step first, or no `--load` | image registers the emulator, picks the base image, builds with --load, writes the evidence, then runs the image suite |
| 51 | the step `changes` reads `git diff --name-only` with `read -r path`, so a rename gives its new path only | changes: a file moved from rootfs/amd64/ to a path that is not an input builds amd64; changes: a file moved out of a shared input builds every port; changes: a file moved from one port to another builds both; changes: a moved path with a non-ASCII name still counts |
| 99 | a cited path that does not exist | each cited docs/ and tests/ path exists |
| 99 | a file that names the history directory | no file names the history directory |
| 99 | the check job renamed, or given a matrix | the required check 'Static suite and linters' is the name of one job of .github/workflows/ci.yml, with no matrix |
| 99 | bot-merge listens to `[Tests]` | bot-merge.yml starts on the workflow name of ci.yml |
| 99 | `gh workflow run no-such.yml`, or of `bot-merge.yml` | each workflow started with gh workflow run exists and has workflow_dispatch |
| 99 | a vendored file that does not exist | tests/policy/vendored names files in the tree |

### Mirrors, transport and the build stage (30, 41 to 49, 55, 66, 67, 88, 90, network 40)

| test | fault | not ok |
| --- | --- | --- |
| 30 | `SigLevel = Never` in amd64 pacman.conf | rootfs/amd64/etc/pacman.conf sets no SigLevel to Never |
| 41 | the first two servers of ppc64le mirrorlist-any swapped | ...mirrorlist-any starts with the servers of mirrors/ppc64le.any-anchors, in order |
| 41 | an `oci://` server in amd64 | ...has no oci:// server |
| 41 | the header date 2999-01-01 in ppc | ...gives a valid date that is not in the future |
| 41 | a `mirrorlist-extra` that no pacman.conf includes | each mirrorlist file in rootfs/ is a list that a pacman.conf includes |
| 41 | a bare URL in riscv64.pool | each line of mirrors/*.pool is a comment, a Server line or a known source |
| 41 | an arm64 list with one http server | ...has at least 2 servers and one over https |
| 42 | a 2xx of the Worker not taken | the registry is not asked when the Worker answers |
| 42 | never `oci` | oci when only the registry serves the database |
| 42 | no database check of the registry body | worker when the registry serves a file that is not a database |
| 42 | `oci` when the Worker answers | worker when the Worker serves the database of the first repository |
| 42 | the Docker arch in place of pacman_arch | the registry is asked for the database of the first repository, with pacman_arch |
| 42 | `oci` when neither answers | worker when neither path answers |
| 42 | an unknown arch taken | an architecture with no ports/<arch>.conf is refused |
| 43 | no rootfs guard | a complete stage named rootfs is refused, and stays as it was |
| 43 | the first-line or the XferCommand check removed | a second oci run changes nothing |
| 43 | an oci line in mirrors/ppc.anchors | no file in rootfs/ or mirrors/ has an XferCommand or an oci:// server |
| 43 | the oci server put last | oci puts the oci:// server first in mirrorlist, and keeps the other servers in order |
| 43 | worker acts as oci | worker changes nothing |
| 43 | the XferCommand at the end of the file | oci puts one XferCommand of pacman-oci in [options] |
| 43 | only the first list changed | ...first in mirrorlist-any... |
| 43 | only Server lines written | oci keeps the comments of a list |
| 43 | the guard removed, exit 0 on a missing conf | ROOT=/rootfs, the tree that ships, is refused |
| 43 | any TRANSPORT taken | a TRANSPORT that is not worker or oci is refused |
| 43 | goes on with no client | a ROOT with no pacman-oci is refused, and pacman.conf gets no XferCommand |
| 44 | the empty-list guard removed | drop-server refuses to leave a list with no server |
| 44 | a path as LIST taken | --pairs refuses a LIST that is a path |
| 44 | stops after the first pair | --pairs drops one server from each list it names |
| 44 | only Server lines written | drop-server removes the one line and keeps the rest, comments too |
| 44 | spaces at the end kept | drop-server finds a line with spaces at the end |
| 44 | an absent server taken | a server that is no Server line is refused |
| 44 | a prefix match | a part of a Server value is refused |
| 44 | always edits DIR/mirrorlist | --pairs leaves a list that no pair names as it was |
| 44 | no pair refused | --pairs with no pair changes nothing |
| 44 | a malformed pair skipped | --pairs refuses a pair that is not LIST=SERVER |
| 44 | a missing list taken | --pairs refuses a LIST that is not in DIR |
| 45 | an XferCommand in amd64 | ...has no XferCommand |
| 45 | SigLevel in a comment above the global line | ...the first line with SigLevel is the global SigLevel |
| 45 | a `#[multilib]` block | ...does not have the word multilib |
| 45 | `[aur]` before `[alarm]` | ...enables the repos of ports/arm64.conf, in order |
| 45 | `Architecture = x86_64` in riscv64 | ...sets Architecture to the pacman_arch of ports/riscv64.conf |
| 45 | NoExtract in ppc | ...has no NoExtract rule |
| 45 | a rootfs/i686 pacman.conf | each pacman.conf in rootfs/ belongs to a port |
| 46 | the record never read | lag_seconds above MIRROR_LAG_MAX drops the GHCR mirror from that list only |
| 46 | no age check | a record older than MIRROR_STATUS_MAX_AGE is not used |
| 46 | no schema check | a record of another schema is not used |
| 46 | a later GHCR path taken as the reference | with TRANSPORT=oci the Worker is not the reference, and the drop names the oci:// path and the Worker path |
| 46 | the drop names the first server only | with TRANSPORT=oci the Worker is not the reference, and the drop names the oci:// path and the Worker path; after the drop, resolve-anchor gives the version of the server after the GHCR mirror (it gave `1-1`); with the oci:// path of use-transport, the drop names it and the Worker path; the build stage reads the server after the GHCR mirror first |
| 46 | a list stays only when it has fewer than 2 servers | with TRANSPORT=oci, a list with no server other than the GHCR mirror stays |
| 46 | the record used before a later server | a later server that answers is the reference, and the record is not used |
| 46 | a fixed limit of 43200 | MIRROR_LAG_MAX sets the limit for the record too |
| 46 | exit 1 on a record that cannot be read | a record that cannot be read keeps the GHCR mirror |
| 46 | the URL not named | the warning gives the URL of the record that cannot be read |
| 46 | the variable not named | the warning names MIRROR_STATUS_MAX_AGE, the limit it passed |
| 46 | an absent target taken as behind | a record with no target for the repository keeps the GHCR mirror |
| 46 | the target not named | the warning names the target that is not there |
| 46 | a lag that is not a number taken as behind | a lag_seconds that is not a number keeps the GHCR mirror |
| 46 | the record judges any first server | the record does not judge a first server that is not the GHCR mirror |
| 47 | one byte added to the copy | the copy has the sha256 of the pin |
| 47 | `raw` names another commit | the pin names one commit in source and raw, and a sha256 |
| 47 | a CRLF copy, the pin updated | the copy has LF line ends, starts with #!/bin/sh, and sh -n reads it |
| 47 | `PACMAN_OCI_VERSION=two`, the pin updated | --version prints 'pacman-oci N' |
| 48 | each list moved at once | each any-anchor dead: exit 3, and mirrorlist stays too, although its anchors answer |
| 48 | no dead-anchor refusal | the same, and each main anchor dead: exit 3, and both lists stay |
| 48 | no anchors written | mirrorlist has both anchors in file order |
| 48 | only the first pool source read | the second source is used when the first does not answer |
| 48 | no shrink guard | 6 ranked servers in the tree and 1 that answers now |
| 48 | no budget | a budget of 0 seconds |
| 48 | goes on when no pool source answers | no pool source answers |
| 48 | an oci:// anchor taken | an oci:// anchor: exit 1 |
| 48 | `all` always exits 0 | all writes the port that answers |
| 48 | no MIN_SERVERS floor | a list with fewer servers than MIN_SERVERS |
| 48 | status-json takes an inactive mirror, or one with no score | status-json gives only the https, active, complete, recent mirrors with a score |
| 48 | the package URL next to the database file; no candidates from the package list | mirrorlist-package reads the list in the package that the database names |
| 48 | only live anchors written | mirrorlist-any has its anchors in file order, and one dead anchor does not stop it |
| 48 | no date in the header | the header of each list gives the date it was generated |
| 48 | no pool file refused | with no pool file, mirrorlist is the anchors |
| 48 | a bad pool line ignored | a pool line that is not Server or source: exit 1 |
| 48 | an unknown arch exits 3 | an architecture with no ports/<arch>.conf: exit 1 |
| 49 | other repositories not read | [base-any] with no readable server stops the port, with no version on stdout |
| 49 | a pair applies to every list | a SKIP_SERVERS pair for mirrorlist-any does not change mirrorlist |
| 49 | --each lists plain http | --each gives one line for each server that is not plain http, in list order |
| 49 | no skip check | a SKIP_SERVERS value that is not LIST=SERVER is refused |
| 49 | the lists ignore TRANSPORT | TRANSPORT=oci reads the oci:// server first |
| 49 | the first server passed over | the version comes from the first server of the primary list |
| 49 | skips ignored | a SKIP_SERVERS pair for mirrorlist passes its server |
| 49 | an unknown list taken | a SKIP_SERVERS pair for a list the port does not have is refused |
| 49 | stops at the first readable database | a database with no pacman is passed, and the next server gives the version |
| 49 | the repository not named | the refusal names [base-any] |
| 49 | other repositories read with no skips | SKIP_SERVERS that leaves [base-any] with no server stops the port |
| 49 | --each reads a skipped server | --each gives - for a server that SKIP_SERVERS names |
| 49 | the oci server first after the skip filter | TRANSPORT=oci with the oci:// server in SKIP_SERVERS reads the next server |
| 55 | `Depends = coreutils` | ...package-cleanup.hook depends on findutils, which owns /usr/bin/find |
| 55 | a hook that runs /usr/bin/rm | the table OWNERS in this test names the package of /usr/bin/rm |
| 66 | only the first repository judged | a first server new for core and behind for extra is dropped: the build reads both |
| 66 | only the first list judged | each list gets its own line: base is kept, base-any is dropped |
| 66 | drop-server before use-transport in the Dockerfile | the Dockerfile sets the transport, then drops SKIP_SERVERS from /etc/pacman.d, then runs pacstrap |
| 66 | a later server is passed over as the reference only when both servers are GHCR paths | a copy of the first server is not the reference, and the drop names the server once (it gave `keep`) |
| 67 | db_open takes any body | it prints 9.9.9.r1.gfeedface-7, from the good mirror |
| 67 | a complaint with no reason | the empty mirror is named once, with a reason |
| 88 | the first mirror line of archpower.pin is http | ...has a mirror line, and the first is https |
| 88 | another sha256 in archlinuxarm.pin | ...has the sha256 of the pin |
| 90 | a comment line in the amd64 list | ...has only package names |
| 90 | the riscv64 list removed | bootstrap/riscv64/etc/bootstrap-packages.txt exists |
| 90 | pacstrap-docker tries again on `failed retrieving file` or `failed to synchronize` | a database with a bad signature stops at once; a download that the next server gave, then a bad signature, stops at once |
| 90 | pacstrap-docker never tries again | two failed downloads, then a pass: three attempts, exit 0; a database download that fails through the XferCommand is tried again; a package download that fails through the XferCommand is tried again; three failed downloads stop after the third attempt, exit 1 |
| 90 | no reason of an XferCommand failure in the match | a database download that fails through the XferCommand is tried again |
| 90 | no limit on the attempts | three failed downloads stop after the third attempt, exit 1; PACSTRAP_TRIES=1 makes one attempt |
| 90 | no check of the value of `PACSTRAP_TRIES` | a PACSTRAP_TRIES that is not a whole number from 1 is refused before pacman starts |
| 90 | `--noconfirm` removed from the pacman call | each attempt gives pacman the root and the packages |
| network 40 | each ppc mirrorlist-any server dead | rootfs/ppc/etc/pacman.d/mirrorlist-any: at least one anchor answers 200 |
| network 40 | each archlinuxarm.pin mirror dead | ...a mirror line serves the pinned package |
| network 40 | each ranked riscv64 server dead | rootfs/riscv64/etc/pacman.d/mirrorlist: at least half of the ranked servers answer 200 |

### Build and publish (35, 60 to 64, 68, 69, 75)

| test | fault | not ok |
| --- | --- | --- |
| 35 | publish with cancel-in-progress true | ⛔ a publish never cancels another |
| 35 | top-level cancel | ⛔ a run never cancels another |
| 35 | `secrets.GITHUB_TOKEN` in a leg | ⛔ no secret in a build leg |
| 35 | EXPECT_ANCHOR removed | ⛔ the evidence must have the resolved anchor |
| 35 | the plan result dropped from the publish condition | the publish runs only after a passed plan and gate |
| 35 | gate on ubuntu-latest, or watch with no timeout | every job runs on ubuntu-24.04 with a timeout |
| 35 | `permissions: read-all` | the top level grants no permission |
| 35 | plan-build gives the real hub target | a dry run plans the scratch images; ⛔ a dry run with dry_run_hub copies between the scratch images only |
| 35 | the name, a job id, a cron, an input or the allow-list default changed | the assertion of each |
| 35 | each `needs` changed | the needs assertion of each job |
| 35 | the leg renamed | the build leg is named Build <arch> |
| 35 | fail-fast true | the legs come from the plan matrix |
| 35 | id-token added | a build leg can read the tree |
| 35 | the hub condition dropped | ...only when the plan says publish_hub |
| 35 | a Docker Hub secret in publish | no Docker Hub secret outside the hub job |
| 35 | watch runs in a dry run | the report and watch jobs do not run in a dry run |
| 35 | report not always | the report job runs after a failure too |
| 35 | a third env key | the top level env sets the two published image names |
| 35 | `$GHCR_IMAGE` in a run | no job reads GHCR_IMAGE or HUB_IMAGE itself |
| 35 | each of the 8 scripts renamed | a build leg runs scripts/X (8 lines) |
| 35 | a fixed allow list | the anchor floor takes its allow list |
| 35 | the export build arg dropped; an extra arg | both builds get the same build args; the build args are those of the Dockerfile contract |
| 35 | ignore-error removed | the build cache ignores a cache service error |
| 35 | the buildkit pin in `driver-opts`, and no step `buildkit` | the buildkit image is pinned by digest; Buildx runs the buildkit image that the step buildkit picked, after that step |
| 35 | the matrix check back in the `if` of the publish | the publish runs on a stand-down too |
| 35 | one run group for a dry run and a real run | a dry run has its own run group, so it never takes the place of a pending real run |
| 35 | the hub `if` takes a skipped publish | the Docker Hub copy runs only when the plan says publish_hub, after a passed publish |
| 35 | the report reads the publish output `fresh` | ⛔ the report clears build-<arch> from the publish output written after the read back |
| 35 | the watch step with no capture of the exit status | the watch step passes when watch-schedules exits 0 or 3, and fails when it exits 1 |
| 35 | the digest artifact renamed | the digest record is uploaded last |
| 35 | `docker info` added, or publish-ghcr renamed | the publish job runs scripts/publish-ghcr and no docker command |
| 35 | sync-hub renamed | the hub job runs scripts/sync-hub |
| 35 | tags on CARRY_IMAGE | ⛔ a dry run tags the scratch GHCR image only |
| 35 | the fresh ref on CARRY_IMAGE | a dry run takes each fresh digest from the scratch image |
| 60 | the pinned filter off | a pinned port tag on the list is left out; an existing v<version> is left out |
| 60 | `sort -r` on the aliases | arm64: tag-names aliases is the alias list |
| 60 | the anchor family dropped | <arch>: each alias has a rolling, a dated and an anchor tag (all 8 ports); rolling tags are printed |
| 60 | a shared alias | no alias belongs to two ports |
| 60 | the index v dropped | the index has latest and v<version> |
| 60 | the version, anchor, tag and list checks removed | their 4 refusal assertions |
| 61 | numeric and alpha order swapped, or the epoch ignored | vercmp gives the expected result for all 65 vectors, both ways |
| 61 | usage exits 1 | vercmp with one argument exits 2 |
| 61 | `-ge 1` | a revert with 1 reachable https server is refused |
| 61 | the first alias only | the floor is the highest anchor over all aliases (and 8 more) |
| 61 | `-gt 0` | an anchor equal to the floor passes |
| 61 | any version counts as a revert | a revert is refused when one https server serves another version |
| 61 | `all` ignored | ALLOW_ANCHOR_DOWNGRADE=all takes the downgrade |
| 61 | the port check off; any name allows | ...that names the port takes the downgrade; ...that names another port refuses it |
| 61 | an anchor class that takes `+`, and no tag check of the anchor tags | an anchor with a + stops the check; an anchor that makes a tag of more than 128 characters stops the check |
| 62 | the platform check off | lose: a latest that would lose a platform stops the publish before any write |
| 62 | no `--existing` | day: a pinned tag that exists is left out |
| 62 | 503 read as absent | dark: ...stops the publish; flaky: ... |
| 62 | Docker Hub not asked | flaky: a carried digest comes from Docker Hub |
| 62 | the manifest compare off | write: a latest that does not hold every child |
| 62 | the index with no `-t` | write: one imagetools create for the fresh port, then one for the index |
| 62 | the clear removed | report: a published port clears build-<arch> |
| 62 | no check of `PUBLISH_RESULT` in report-build | report: a failed publish clears no build-<arch>, even when its output names the port, and raises publish-ghcr |
| 62 | `published=` written before the read back | ⛔ write: published= names the fresh ports after the read back, and a failed read back writes no published= |
| 62 | no tag check before the first write | a tag that scripts/tag-names refuses stops the publish before the first write; a digest file with an anchor that no tag can carry stops the publish before any write |
| 62 | an exit with no write when no port is fresh | ⭐ no fresh port, and latest holds older images: latest is made again from each first alias, with no v2030.01.02; no fresh port, and a first alias was built on 2030.01.02: latest and v2030.01.02 are made; no fresh port, and a carried source cannot be read: the publish fails, so publish-ghcr is not cleared |
| 62 | `dated=1` when no port is fresh | ⭐ no fresh port, and latest holds older images: latest is made again from each first alias, with no v2030.01.02 |
| 63 | latest read as pinned | mixed: the missing pinned tags are copied; mixed: the summary counts each tag once |
| 63 | a list error read as empty | a Docker Hub tag list that cannot be read stops the copy |
| 63 | a GHCR list error, and the empty guard off | a GHCR tag list ...; an empty GHCR tag list stops the copy |
| 63 | pinned compared again | mixed: a pinned tag with another digest on Docker Hub is not moved |
| 64 | the dry_run_hub check off | dry_run_hub without dry_run stops the plan |
| 64 | the wrong tag looked up | a port that has its dated tag for today is not built again (and 3 more) |
| 64 | the ppc mask byte changed | the fallback table has the magic and mask of qemu |
| 64 | F not checked | a registration without the F flag fails the check |
| 64 | the wrong endian | each emulated port has a fallback registration with its byte order |
| 64 | a table of the 7 emulators that the ports use | the fallback table has the magic and mask of qemu for each emulator; a port with an emulator of the table that no port uses yet (qemu-aarch64_be) needs no edit of the script |
| 64 | the table and the fixture cut to the emulators that the ports use | a port with an emulator of the table that no port uses yet (qemu-aarch64_be) needs no edit of the script |
| 64 | no file names in the message for an emulator that the table does not have | an emulator that the table does not have stops binfmt-register, and the message names the files to edit |
| 64 | pick-base-image with no `--image` | --image: when docker.io serves the digest, the value is the image as given; --image: when docker.io does not answer, the value is the same digest on mirror.gcr.io; --image: ECR Public is not asked for an image that is not a Docker official image; --image: an image with no digest is refused |
| 64 | ECR Public asked for every image | --image: ECR Public is not asked for an image that is not a Docker official image |
| 64 | flags OCF | the fallback registration line names /usr/bin/qemu-aarch64-static with the F flag |
| 64 | the registered check off | a registration that is enabled with the F flag passes |
| 64 | the native branch off | a native port needs no emulator |
| 64 | the digest not compared | a registry that answers with another digest is passed over |
| 64 | the Dockerfile pin with no registry | the Dockerfile has one BASE_IMAGE pin that pick-base-image can move |
| 64 | FORCE off | FORCE=true builds every port |
| 64 | the port check off | ARCHES with a name that is not a port stops the plan |
| 64 | `listed=1` | a tag list that cannot be read builds every port |
| 64 | a version with no dots | the version is the UTC date of the plan |
| 64 | pick-base-image does not read ratelimit-remaining | ⭐ when the Docker Hub pull limit is used up (ratelimit-remaining 0), BASE_IMAGE is the same digest on mirror.gcr.io |
| 64 | reg_head_limit reads the header name in lower case only | reg_head_limit reads the headers in any case |
| 64 | reg_head_limit keeps the window (`;w=`) of the count | reg_head_limit gives the digest and a remaining count of 0; reg_head_limit reads the headers in any case |
| 64 | reg_head_limit prints an empty digest as nothing | reg_head_limit gives - for the digest of an answer that is not 200 |
| 68 | `die_rc 1` | a DB_SNAPSHOT that is not a directory is refused with exit 3; the partial snapshot assertion |
| 68 | another path | the export directory and DB_SNAPSHOT are the same path |
| 68 | each snapshot refused | a snapshot with each enabled database passes |
| 68 | the stage renamed | the Dockerfile has a dbsnapshot stage |
| 68 | `--from=other` | the dbsnapshot stage takes its files from the bootstrap stage |
| 69 | tar writes into a file | gen-evidence writes the evidence past a sparse member |
| 69 | the damaged check off | the damaged member is named in the log |
| 69 | a file written before exit 4 | an installed package with a damaged entry is refused with exit 4, named, and no file is written |
| 69 | exit 1 | a package that the snapshot does not have is refused with exit 5 |
| 69 | any EXPECT_ANCHOR stops | the evidence anchor equals EXPECT_ANCHOR |
| 69 | the compare off | an anchor that is not EXPECT_ANCHOR stops the leg with exit 6 |
| 69 | the labels not read | with no SOURCE_COMMIT and no BUILD_DATE, the evidence has the revision and created labels of the image; an image with no labels gives unknown for the commit and the time; an empty revision label gives unknown, and the created label stays; labels that are not JSON stop gen-evidence, and no file is written |
| 75 | a 3-port comment in vercmp | scripts/vercmp writes no list of 3 or more ports |
| 75 | the aarch64 alias dropped | each alias that mirror-archlinux pulls is an alias of a port |
| 75 | the riscv64 mirrorlist removed | riscv64 has its rootfs, bootstrap and mirrors files |
| 75 | `rootfs/sparc` added | no rootfs, bootstrap or mirrors entry belongs to a name that is not a port |
| 75 | powerpc64le dropped from archpower.pin | bootstrap/keyrings/archpower.pin names the pacman_arch of each port with keyring = archpower |
| 75 | `platform = linux/AMD64` in ports/amd64.conf | scripts/ports check passes ("platform 'linux/AMD64' is not linux/<arch>[/v<n>]") |
| 75 | `aliases = X86_64` in ports/amd64.conf | scripts/ports check passes ("alias 'X86_64' is not a valid tag") |
| 75 | a port named `risc_v64`, with its files | scripts/ports check passes |

⚠ In 69, the "tar writes into a file" fault gave no `not ok` line until each fixture desc record had a 1000-byte `%DESC%`.

### Upkeep (89, 91 to 95)

| test | fault | not ok |
| --- | --- | --- |
| 89 | `return 5` changed to `return 0` in merge-bot-pr | an action with a major version change is refused (also 6, 7, 8) |
| 89 | `docker\.io\|` removed from the renovate regex | the regex manager of renovate.json matches each image pin |
| 89 | "major" added to the automerge rule | no rule of renovate.json merges a major update with no person |
| 89 | `workflows: [CI2]` | bot-merge.yml starts when the workflow named by ci.yml completes |
| 89 | `--check-diff` compares the removed and the added lines as two sets, not hunk by hunk | a line moved down inside one hunk is refused; a line moved from one hunk to another is refused; a changed line that starts with -- or ++ is read as a changed line, not as a header; a hunk with fewer lines than its header is refused |
| 89 | `--check-diff` reads no file header line | a pin bump with a file that git shows as binary is refused; a pin bump with a mode change is refused; a pin bump with a rename is refused; a pin bump in a file that a pin bump may not change is refused |
| 89 | merge-bot-pr reads no check run | merge-bot-pr: the required check failed: left alone; merge-bot-pr: the required check did not end: left alone; merge-bot-pr: no required check on the head commit: left alone; merge-bot-pr: a check with the required name from another app: left alone; merge-bot-pr: the newest run of the required check failed: left alone |
| 89 | merge-bot-pr counts the pull requests of a fork with the same head branch | merge-bot-pr: a fork pull request with the same branch name does not stop the merge |
| 89 | bot-merge.yml starts only on a CI run that passed, with no `checks: read` | bot-merge.yml starts whatever the conclusion of the CI run; the script reads the required check; bot-merge.yml runs scripts/merge-bot-pr, with checks: read |
| 89 | check-image-pins with no `--seen` | check-image-pins --seen: a pin behind for the first time is not overdue, and its first day is today; check-image-pins --seen: a pin seen behind since long ago is overdue, though its tag moved today; check-image-pins --seen: the record of another pinned digest does not count; check-image-pins --seen: a pin that is current leaves the record; check-image-pins --seen: a line that is not a record line is left out |
| 89 | freshness.yml with no step `seen` and no upload of the record | freshness.yml job image-pins has a step with id seen that reads the record; freshness.yml keeps the record that check-image-pins --seen writes, as the artifact image-pins-seen |
| 91 | `n >= 4` in judge | 3 failed scheduled runs in a row: failing-weekly opens |
| 91 | the 404 case changed | every schedule fires and passes |
| 91 | `--ref main` in dispatch-overdue | dispatch-overdue: a newest run 300 min old ... started on the default branch |
| 91 | `elif` changed to `else` in watch-schedules | a run list that cannot be read: exit 1, and schedules-stopped is not closed |
| 91 | the commit-date rule removed | no scheduled run, an old record, and a file changed 2 days ago: new, not stopped |
| 91 | the select of the repository and the event removed from dispatch-overdue | dispatch-overdue: a run 10 min old from a fork, with the head branch trunk, does not count: started |
| 92 | a limit of 100 | only the failed runs of renovate/ branches under the limit are re-run |
| 93 | a label filter in jq; the labels POST removed | raise finds an issue with the marker and no label |
| 93 | the list failure taken | an issue list that cannot be read: exit 1, and no second issue opens |
| 93 | track-issue takes each issue with the marker, of any author, anywhere in the body | an issue with the marker that another user opened is not the issue: a new issue opens; an issue whose body has the marker after other text is not the issue: a new issue opens; the issue of the bot wins over an issue of another user with a lower number; clear does not close an issue of another user with the marker |
| 93 | propose-change finds a pull request by its head branch only | propose-change: a fork pull request with the same branch name is not edited; propose-change: with a fork pull request listed first, the pull request of the bot is edited; propose-change --withdraw leaves a fork pull request with the same branch name open; propose-change --withdraw closes the pull request of the bot |
| 94 | the desc pattern broken; `servers_for` removed | the database names the pinned package: current |
| 94 | `trusted_set` always same | a newer package that trusts one more key |
| 95 | Docker Hub not read | Docker Hub lacks the newest tag of a port: that port is stale |
| 95 | the year prefix `^2029` | the newest dated tag of each port is found across a year boundary |
| 95 | `RECENCY_TODAY` set in watchdog.yml | no workflow names a test seam |
| 95 | the `!cancelled()` removed | watchdog.yml measures each port, then raises or clears stale-<arch> |
| 95 | `needs: plan` on watch | build-deploy.yml has a job watch |
| 95 | the default `HUB_IMAGE` of check-publish-recency written as `docker.io/pkgforge/archlinux` | the GHCR and Docker Hub images are the env GHCR_IMAGE and HUB_IMAGE of the publish workflow |
| 95 | the owner in the GHCR image replaced with `nobody` | the GHCR and Docker Hub images are the env GHCR_IMAGE and HUB_IMAGE of the publish workflow |
| 95 | the two empty-image guards removed | a publish workflow with no image env stops the check with exit 1 |
| 95 | the tolerance `gap * 2 + 1`, with no limit | cron '0 0 1 * *' gives '31 39'; cron '0 0 1,15 * *' gives '17 25'; cron '0 0 1 1 *' is refused; cron '0 0 1 */2 *' is refused |
| 95 | the `watchdog.yml` step runs `scripts/watch-schedules` with no capture of the exit status | the watchdog.yml step passes when watch-schedules exits 0 or 3, and fails when it exits 1 |
| 91 | the event filter of dispatch-overdue replaced with `true` | dispatch-overdue: a pull_request run of this repository does not count |
| 91 | the repository filter of dispatch-overdue removed | dispatch-overdue: a scheduled run whose head is another repository does not count |

A broken config `{"automerge":"yes","bogusKey":1}` fails `renovate-config-validator --strict`: "Configuration option `automerge` should be boolean", "Invalid configuration option: bogusKey".

### The status site (76 to 79)

| test | fault | not ok |
| --- | --- | --- |
| 76 | `exit 1` after status.json is written | status-collect measures the fixture world and exits 0 |
| 76 | a size +1 byte | status.json is expected-status.json; history: a measured port is not marked carried |
| 76 | the ports in reverse order | every fixture port, in the order of scripts/ports |
| 76 | an error state called absent | ppc64: the image did not read, so its state is error |
| 76 | a size that did not read is 0 | ppc64: age, size, created, packages and mirror lag are null, not 0 |
| 76 | Hub match false when GHCR did not read | ppc64: Docker Hub match is unknown while the GHCR image is unknown |
| 76 | the oldest job taken | ppc: the newest Build job failed, in run 1002 |
| 76 | the age +3600 | ppc: the age counts from the created label: 41.1 days |
| 76 | any digest counts | parity: 16 of 17 rolling tags with the same digest, 42 of 43 pinned tags present, of 60 GHCR tags |
| 76 | the rolling tags of a port always present | parity is (16 + 42) / 60, and the per port sums agree |
| 76 | `missing_names .[:0]` | the rolling tag that differs and the pinned tag that is missing are named |
| 76 | drift_runs always 1 | drift_runs: the previous line has 1, parity is below 1, so 2 |
| 76 | in_latest always true | latest lacks the platform of ppc64le, and ppc64le is not in latest |
| 76 | the dated family counts anchors | tag families of armv7: 3 rolling, 6 dated, 3 anchor on GHCR; 5 dated on Docker Hub |
| 76 | is_pub takes only the image-manifest digest | evidence: amd64 takes the artifact of run 1002, which describes the published image (also 16, 17) |
| 76 | `limit=1` | evidence: armv7 takes the artifact of run 1001, because run 1002 describes another image |
| 76 | the stored file not found | evidence: arm64 keeps its stored file, which describes the published image |
| 76 | matches=true for an old image | evidence: ppc64le keeps its stored file, which names an older image |
| 76 | the expired filter removed | evidence: loong64 has only an expired artifact, so no evidence |
| 76 | the .digest file gets `$pub` | each evidence/<arch>.digest names the digest inside its evidence file |
| 76 | the old history dropped | history.jsonl: the previous line and this run's line |
| 76 | carry off | history: ppc64 keeps its last size, marked carried; its age is unknown |
| 76 | each line marked k:1 | history: a measured port is not marked carried |
| 76 | `.dr = 1` | a second run counts 3 runs in a row below parity 1 |
| 76 | `tail -n 2000` | the history keeps the last STATUS_HISTORY_LINES lines |
| 76 | the ARTIFACTS check removed | STATUS_ARTIFACTS=0: amd64 has no evidence, arm64 keeps its stored evidence |
| 76 | a token that does not read dies | no registry: the collect measures and exits 0 |
| 76 | a null parity resets the drift count | no registry: every image is unread, parity is unknown, the drift count stays |
| 76 | age 0 when unread | no registry: no age and no size reads as 0 |
| 76 | builds read only when GHCR answers | no registry: the builds still read |
| 76 | fx_time exits 1 | STATUS_BUDGET=4: the collect exits 0 |
| 76 | exhausted=false | STATUS_BUDGET=4: budget.exhausted, no image read, no build read |
| 76 | `sleep 61` when exhausted | STATUS_BUDGET=4: the collect ends within a minute |
| 76 | the owner replaced by "nobody" | no GHCR_IMAGE: the GHCR image is the one build-deploy.yml names, for the owner of GITHUB_REPOSITORY |
| 76 | HUB_IMAGE from GHCR_IMAGE | no HUB_IMAGE: the Docker Hub image is the env HUB_IMAGE of build-deploy.yml |
| 76 | a default slug | no GITHUB_REPOSITORY: the collect stops with exit 1 and writes nothing |
| 76 | `DRY_RUN_JOB` renamed | status.json is expected-status.json; ppc: the newest Build job failed, in run 1002; builds: only runs 1002 and 1001 count |
| 76 | the dry mark of the run name always false | status.json is expected-status.json; ppc: the newest Build job failed, in run 1002; builds: only runs 1002 and 1001 count |
| 76 | `&& github.event_name == 'schedule'` added to the `if` of the job watch of build-deploy.yml | build-deploy.yml has one job 'Watch the schedules' that needs nothing and runs when dry_run is not true, as fixture run 1003 has it |
| 76 | the select of the repository and the event removed | status.json is expected-status.json; builds: only runs 1002 and 1001 count; evidence: amd64 takes the artifact of run 1002, which describes the published image |
| 76 | a rolling digest that did not read counted as a tag that Docker Hub lacks | amd64 and the index: same and ratio are unknown, not a tag that Docker Hub lacks |
| 77 | main returns 1 | status-render site1 exits 0 |
| 77 | the packages badge of the first port not written | site1: every page, chart, badge, data and evidence file is written |
| 77 | `</titl>` in the badge | site1: all 44 SVG files parse as XML, each with a title and a dark style |
| 77 | NARROW=440 | site1: each chart is 760 wide, and 420 wide under charts/narrow |
| 77 | a size badge "None" | site1: no chart or badge says NaN, None, null, undefined or inf |
| 77 | the class `l-%d` | site1: every chart mark names a defined slot class |
| 77 | `ports[:-1]` in the charts | site1: chart freshness (size, packages, coverage, build, history-build) names every port |
| 77 | `i % 4 + 1` | site1: each port has a colour swatch of its own, and none is the grey |
| 77 | "not read" in the port badge | site1: badge ppc64 says unknown |
| 77 | "missing" in the packages badge | site1: badge packages-ppc64 says unknown |
| 77 | the summary badges say "n/a" | site2: badge latest (registries, build) says unknown |
| 77 | the source "None" | site1: the page says no NaN, None, null, undefined or inf |
| 77 | the narrow srcset names the wide chart | site1: index.html references every chart, in both widths, and every badge |
| 77 | the evidence link `.jsn` | site1: every file index.html references exists |
| 77 | a second `<script src>` | site1: index.html has one script, inline, and no other |
| 77 | `onload` on body | site1: index.html has no event handler attribute and no javascript: URL |
| 77 | no "UTC" | site1: every <time> has a datetime in UTC and shows it as UTC text |
| 77 | `history[1:]` | site1: history.json holds 722 line(s) |
| 77 | schema 2 written | site1: status.json on the site is the collected record |
| 77 | `latest` not reserved | a port named like a summary badge stops the render with exit 1 |
| 77 | exit 0 with no status.json | no status.json stops the render with exit 1 |
| 77 | schema 2 taken | a status.json of another schema stops the render with exit 1 |
| 77 | a usage error returns 1 | a call with one argument is a usage error, exit 2 |
| 77 | the execv line replaced with `pass` | run without -I, the renderer starts itself with -I: a json.py beside it is not read |
| 77 | `row()` reads only the tags, and `same or 0` | site-parity: a port parity whose same did not read draws no bar in the coverage chart |
| 77 | the tile tests `unread == 0` only | site-one-absent: the sub-line of the first tile changes, and counts 1 port(s), when a port has no image |
| 77 | the build table counts every day of the history | site-long-history: the build table counts the passed days that the 30 day build chart shows |
| 77 | `mirror_state` reads the lag of any target, and says behind for a lag of 0 | mirror_state: a target not current with lag 0 states no lag, and gives its share of files; mirror_state: the lag comes from the target that is not current, not from a current target |
| 77 | `sys.dont_write_bytecode` removed from the module load | the load of status-render as a module writes no bytecode into the tree |
| 76 | the `run-name` line removed from build-deploy.yml | the run-name of build-deploy.yml gives the names of fixture dry run 1005 and real run 1002 |
| 76 | the dry run name changed to `Build and publish, dry` | the run-name of build-deploy.yml gives the names of fixture dry run 1005 and real run 1002 |
| 78 | the build result not used | record: a build that failed raises status-down; the fresh record still clears registry-drift |
| 78 | no run URL in the body | record: the status-down body names the run |
| 78 | the clear names another key | record: a build that succeeded with a fresh record closes status-down |
| 78 | STATUS_MAX_AGE=20000 | record: a record 4 h old raises status-down, judges no drift, and fails |
| 78 | `die` changed to `note` | record: a skipped build and no record raise status-down, and fail |
| 78 | DRIFT_RUNS=3 | record: parity below 1 in 2 runs in a row raises registry-drift |
| 78 | no tags in the body | record: the registry-drift body names the missing tag and the tag that differs |
| 78 | DRIFT_RUNS=1 | record: parity below 1 in 1 run raises nothing yet |
| 78 | `= nil` | record: parity unknown neither raises nor clears registry-drift |
| 78 | `= 1.0` | record: parity 1 closes registry-drift |
| 78 | a default slug in check-status-record and in track-issue | record: no GITHUB_REPOSITORY stops the check with exit 1, and touches no issue |
| 78 | the clear of pages-stale off | site: a fresh record and its copy on Pages close pages-stale, and leave status-down alone |
| 78 | STATUS_SITE_MAX_AGE=30000 | site: a record 7 h old raises status-down, exit 3 |
| 78 | PAGES_MAX_LAG=20000 | site: a copy on Pages 4 h behind the branch raises pages-stale, exit 3 |
| 78 | no answer counts as current | site: a copy on Pages that does not answer raises pages-stale, exit 3 |
| 78 | the path `status2.json` | site: with no argument the record is read through gh api; fresh, so nothing is raised |
| 78 | 'HTTP 4040' | site: with no argument and no status.json on the branch (HTTP 404), status-down is raised, exit 3 |
| 78 | a default slug in check-status-site and in track-issue | site: no GITHUB_REPOSITORY stops the check with exit 1, and touches no issue |
| 79 | the name Statuz | the workflow is named Status |
| 79 | the cron at minute 17 | an hourly cron at minute 23, and workflow_dispatch |
| 79 | contents read at the top | no permission at the top |
| 79 | cancel-in-progress true | one concurrency group, and a run is never cancelled |
| 79 | the job check renamed verify | the jobs are build, check, deploy and keep |
| 79 | ubuntu-latest | every job runs on ubuntu-24.04 with a timeout |
| 79 | pull-requests read added | build: actions read and contents write, nothing more |
| 79 | `scripts/collect` | build: runs scripts/status-collect, then scripts/status-render |
| 79 | the `if` removed from the push step | build: the push to the branch status and the Pages artifact run on the default branch only |
| 79 | one artifact name for every attempt | build: the Pages artifact is named for this run attempt, and deploy takes that name |
| 79 | 30 days | keep: status-history is kept 90 days, a re-run overwrites it, and no file is an error |
| 79 | contents read on deploy | deploy: pages and id-token write, nothing more |
| 79 | the group pagez | deploy: environment github-pages, group pages, never cancelled, needs build |
| 79 | buildtype | deploy: the build type of Pages is read before the deploy |
| 79 | issues read | check: contents read and issues write |
| 79 | `!cancelled()` | check: runs whatever build did, on the default branch, after build |
| 79 | BUILD_RESULT success | check: calls scripts/check-status-record with the result of build |
| 79 | STATUS_NOW set in the env | no workflow sets STATUS_FIXTURE_DIR or STATUS_NOW |
| 79 | the select of the step read set to `select(true)` | read, no branch status: the step ends 0 and takes the artifact of run 9001, not the forged one of fork run 9003; read, no branch status, only the fork run has an artifact: the step ends 0 and the history starts empty |
| 79 | the upload of status-history in the job build, and no job keep | the jobs are build, check, deploy and keep; build: no step uploads status-history, so a fault of the artifact store cannot stop the record; keep: contents read, nothing more; keep: needs build, runs only after a build that passed, on the default branch; keep: status-history is kept 90 days, a re-run overwrites it, and no file is an error |
| 79 | deploy needs build and keep | no job needs keep |

### Release and the static pacman (85, 96)

| test | fault | not ok |
| --- | --- | --- |
| 85 | the zlib sha256 cut to 63 hex | each source record has an https URL and a sha256 |
| 85 | the zig host renamed `x86_64-linuxx` | zig is pinned by sha256, with a record for the x86_64-linux runner |
| 85 | the zlib mirror file name changed to 1.3.3 | each mirror line names a record and the same file name |
| 85 | the pacman commit cut to 7 digits, its URL http | pacman is pinned at a 40 digit commit from an https URL |
| 85 | the describe hash changed | describe names the pinned commit |
| 85 | the tag object cut to 39 hex | one tag line names the tag and its 40 digit object sha |
| 85 | a signer fingerprint in lower case | each signer line is a 40 digit fingerprint |
| 85 | one keyserver line removed | at least two keyservers, all hkps |
| 85 | the two key files swapped | keys/ holds one key file per signer line, with that fingerprint |
| 85 | `TRIPLE=x86_64-linux-musl` in the script | build-pacman-static --describe reads each target fact from the port table |
| 85 | the port check removed | build-pacman-static refuses a port that the port table does not have |
| 85 | a host triplet in a comment | build-pacman-static writes no fact of ports/*.conf itself |
| 85 | `build_xz` renamed | one build function for each source record |
| 85 | `step` writes to stdout | step writes progress to stderr |
| 85 | an `echo` in `fetch` | ensure_zig, fetch and src_of write no progress to stdout |
| 85 | `make > /dev/null` | no library build sends its output to /dev/null |
| 85 | the `--check-evidence` regex `{41}` | --check-evidence passes a verified, run, static binary |
| 85 | `return 0` at the start of check_evidence | the refusals of NOT VERIFIED, SKIPPED, NOT MEASURED, interp_segments = 1 and no sha256 |
| 85 | a literal `arch: [amd64]` matrix | pacman-static.yml builds the ports of scripts/ports matrix |
| 85 | `--check-evidence` renamed in the workflow | pacman-static.yml checks the evidence after the build and before the upload |
| 85 | a daily schedule | pacman-static.yml runs once a week and release.yml can call it |
| 85 | `MESON_VERSION=1.5.0` in scripts/install-tools; an empty MESON_VERSION; `pipx install meson==1.10.1` in pacman-static.yml | pacman-static.yml installs meson with scripts/install-tools, at or above MESON_MIN of the build script |
| 85 | `# pacman-static` in the Dockerfile | the Dockerfile and bootstrap/any do not name the static pacman |
| 85 | zig unpacked into `WORK/zig`, a name with no sha256 | after a pin change, a reused WORK gives the zig of the new pin |
| 85 | the zig version read from the pin, not from the binary | with ZIG set, --zig gives that binary and the version that it reports, not the pinned one |
| 96 | `push: tags: v*` in pacman-static.yml | release.yml is the one workflow that a v* tag starts |
| 96 | a weekly release cron | release.yml runs once a month and on dispatch |
| 96 | top-level `contents: read` | release.yml grants no permission at the top |
| 96 | the `pacman` job uses `other.yml` | release.yml calls pacman-static.yml for the binaries |
| 96 | `manifest` removed from publish needs | the publish job needs every producing job |
| 96 | publish `if: always()` | the publish job runs only when guard chose to publish |
| 96 | rootfs `contents: write` | publish is the one job with contents: write |
| 96 | a literal rootfs matrix | release.yml reads the ports from scripts/ports for the matrix and for the notes |
| 96 | the `static` step id renamed | the guard job runs the static suite |
| 96 | `--clobber` removed | the publish job makes the draft, checks the assets, then publishes the draft as its last step |
| 96 | `c + 1` changed to `c` | release-notes --next-tag reads only vX.Y.Z tags and adds one to the patch |
| 96 | the manifest schema check fails | release-notes accepts a complete release with a port left out |
| 96 | SHA256SUMS lists itself | SHA256SUMS lists every asset but itself, and sha256sum -c passes |
| 96 | the row of a port left out printed as `x \| y` | the body has a row for the port left out, and the evidence source of each rootfs |
| 96 | a fixed date in the body | the body names no version or date that its inputs do not give |
| 96 | the missing-companion rule removed | release-notes refuses a rootfs with no package set and no note; a port with no rootfs and no note |
| 96 | the absent-and-present rule removed | release-notes refuses rootfs assets for a port that the notes call absent |
| 96 | the stray-file rule removed | release-notes refuses an asset of a port outside RELEASE_ARCHES |
| 96 | the missing-evidence rule removed | release-notes refuses a binary with no evidence file |
| 96 | the `--check-evidence` call skipped | release-notes refuses a binary that did not run; whose tag check was skipped |
| 96 | the commit count `-ge 1` | release-notes refuses binaries from two pacman commits |
| 96 | the manifest rule removed | release-notes refuses a release with no manifest.json |
| 96 | the count with no sha256 printed as 0 | gen-bootstrap-set writes one line per package and counts the lines with no sha256 |
| 96 | `sort` replaced with `cat` | gen-bootstrap-set sorts by package name |
| 96 | the count check `-ge 0` | gen-bootstrap-set refuses an evidence file with no packages |
| 96 | gen-manifest gives each tag shape an anchor | gen-manifest gives each tag shape its port and its anchor |
| 96 | a wrong `anchor` line in tests/fixtures/96-release-assets/manifest-expect.txt | gen-manifest gives each tag shape its port and its anchor |
| 96 | the `port` line removed from manifest-expect.txt, and the port filter made empty | gen-manifest gives each tag shape its port and its anchor |
| 96 | `CONTAINER_RUNTIME: docker` removed from release.yml | all 3 workflow steps that call gen-evidence set CONTAINER_RUNTIME |
| 96 | `isDraft` not read | ⛔ a published release is not changed: no upload, no edit, no delete, and the state published |
| 96 | a draft at another commit finished, not deleted | a draft at another commit is deleted and made again at the commit of the run, with no old asset |
| 96 | no delete of an asset that the run did not make | a draft at the commit of the run is finished: the extra asset goes, the draft stays |
| 96 | `verify` only warns on an extra asset | verify refuses a draft with an asset that the run did not make |
| 96 | the `if` removed from `verify` and `undraft` | the steps verify and undraft run only on the state that publish gives |
| 96 | gen-evidence given the commit and the time of the release run | regenerated release evidence has the revision and created labels of the image, not the release run; regenerated release evidence of an image with no labels says unknown |
| 96 | `env -u` removed, so `SOURCE_COMMIT` comes from the environment | regenerated release evidence has the revision and created labels of the image, not the release run; regenerated release evidence of an image with no labels says unknown |
| 96 | the anchor sentence in the body whatever the anchors | the body names an image whose pacman is not the describe value, and then drops the claim that they agree |
| 96 | the `if` of the job `report` set to `always()` | report runs after a failure, and only for a scheduled run |
| 96 | `publish` removed from the needs of `report` | report needs every other job of release.yml |
| 96 | `actions: read` added to `report` | report has contents read and issues write, nothing more |
| 96 | `cancelled` not counted as a failure | report: a cancelled job raises failing-release |

The signed tag check of `scripts/build-pacman-static`, driven directly:

| fault | result |
| --- | --- |
| none | v7.1.0 is signed by Allan McRae, `6645B0A8C7005E78DB1D7864F99FFE0FEAE999BD` |
| the pinned tag object set to zeros | exit 1; the message gives the object of the tag and the object of the pin |
| a signer that did not sign the tag | exit 1, no valid signature, `NO_PUBKEY` |
| the `tag` line removed | exit 1; the pin names no tag |
| `PACMAN_TAG_VERIFY=skip` | exit 0, `SKIPPED` in the evidence, and `--check-evidence` refuses the asset |
| gpg removed from the host | exit 1; gpg is named as missing |

⚠ The refusal of a `VALIDSIG` of a key that the pin does not name cannot be reached by a fault: the keyring is new on each run and holds only the pinned keys, so an unpinned key fails before it with `NO_PUBKEY`.

### The documents (80)

| fault | not ok |
| --- | --- |
| a bash block with a syntax error in `docs/design.md` | each fenced bash block of the Markdown files parses |
| an indented bash block with a syntax error in a list item of `docs/operations.md` | each fenced bash block of the Markdown files parses |
| the aliases of armv7 in another order in `README.md` | README.md architecture row 3 is armv7: port, platform, aliases and distribution |
| the riscv64 row removed from `README.md` | README.md has one architecture row for each port of scripts/ports; README.md architecture row 8 is riscv64 |
| a new port `zz` in `ports/` that `README.md` does not have | README.md has one architecture row for each port of scripts/ports; README.md architecture row 9 is zz; README.md shows the badge of each port |
| another homepage for amd64 in `README.md` | README.md architecture row 1 is amd64: port, platform, aliases and distribution |
| the ppc64 badge removed from `README.md` | README.md shows the badge of each port |
| `HUB_IMAGE` changed in `build-deploy.yml` | README.md names the Docker Hub image |
| `GHCR_IMAGE` changed in `build-deploy.yml` | README.md names the GHCR image |
| a link to `github.com/pkgforge/docker-archlinux` in `README.md` | README.md has no link to github.com/pkgforge/docker-archlinux |
| a NoExtract rule in `rootfs/ppc/etc/pacman.conf` | none of the 8 shipped pacman.conf files has a NoExtract rule |
| the history directory back in the tree | the history directory is not in the tree |
| `examples/README.md` names the history directory | no document names the history directory |
| an example with a syntax error | examples/99-broken.sh parses as bash |
| an example with pipefail and a pipe into head | no example sets pipefail and pipes into a reader that stops early |
| `examples/` removed | examples/ is in the tree |
| each row of the table removed | README.md has an architecture table |
| `docs/tests.md` runs `localhost/dal-test` with no build of it | each localhost/ image that a document names is made by a bash block of a document |
| `tests/Containerfile` removed | each file that a bash block of a document builds an image from is in the tree; each script and build file that a source of docs/measurements.md runs is in the tree |
| the `FROM` of `tests/Containerfile` with no digest; with no `# tag:` line; with `# tag: edge` | each FROM of a build file of a document, outside examples/, is pinned by digest under its # tag: marker |
| `pacman -Sy --noconfirm --needed qt6-base` in examples/03, and the same in 04 and 05 | no example and no bash block installs a package with pacman -Sy and no -u (a partial upgrade) |
| `pacman -S -y` with packages in a bash block of the bootstrap guide | no example and no bash block installs a package with pacman -Sy and no -u (a partial upgrade) |
| `pacman -Sy --noconfirm archlinux-keyring && pacman -Su` in examples/03 | none: a keyring package alone is allowed |
| no `false` after the sha256 mismatch of the keyring block | the keyring block of docs/bootstrap-with-pacman-static.md stops on a sha256 mismatch under set -e, before pac -U |
| `keyring="$pin"` set before the sha256 check | after a sha256 mismatch, keyring has no value, so pass two stops |
| `jq -r '.SPDX.packages \| length'` in examples/06 | examples/06 gives the SBOM package count of each platform of an index (it printed `0`) |
| examples/README.md with no column `needs` | examples/README.md has a row with the column needs for each example |
| `jq` removed from the row of 07; `buildx` removed from the row of 06 | the column needs of examples/README.md names each tool that an example runs |
| a source cell that runs `agentB/sparse-probe.sh` or `podman build -f scratchpad/agentA/Dockerfile.trunc`; one that runs `scripts/pick-transportx` | each script and build file that a source of docs/measurements.md runs is in the tree |
| sentences of 26 to 43 words in `docs/design.md`, `docs/operations.md`, `docs/tests.md`, `docs/measurements.md` and `THIRD-PARTY.md` | no sentence of a Markdown file has more than 25 words |

### Image tests (10 to 60)

The faults below were made in fixture images: `FROM` a published image with one group of faults, or `FROM scratch` with one file. The column gives the assertion that failed.

| test | fault | assertion that failed |
| --- | --- | --- |
| 10 | `FROM scratch` with one file | /bin/sh and /usr/bin/bash are in the image and resolve |
| 20 | `/etc/os-release` and `/usr/lib/os-release` removed | /etc/os-release is in the image |
| 30 | the CA bundle removed; a published image whose bundle link had no target | the bundle resolves |
| 40 | a null sha256, a sha256 that is not 64 hex, a size of 0, a release date `-` | each package entry has a name, a version, a positive size, a sha256 and a release date |
| 40 | `platform` of another port | the platform of the evidence is the platform under test |
| 40 | `digest` set to zeros | the digest of the evidence is the digest of the image |
| 40 | `source_commit` cut to 7 hex (`da5fffa`) | source_commit of the evidence is a full commit hash |
| 40 | `anchor.version` that no package has | the anchor is a recorded package |
| 40 | `packages` emptied | the evidence records at least one package |
| 40 | a top-level key removed | the evidence has the top-level key built |
| 40 | one package removed from `.packages`, `package_count` kept | the evidence records each package that the image has installed: "the image has 137, the evidence records 136" |
| 40 | a runtime whose `run` exits 125 | the image gives its installed packages: "run exited 125", with the stderr of the runtime |
| 40 | a stand-in runtime: `pacman -Q` gives `zlib 1:1.3.1-3`, the evidence records `zlib 1:1.3.1-2` | the evidence records each package that the image has installed, with its version: "in the image only: zlib 1:1.3.1-3" |
| 40 | a stand-in runtime: `pacman -Q` gives one package more than the evidence | the evidence records each package that the image has installed, with its version: "in the image only: xz 5.6-1" |
| 40 | a stand-in runtime: the evidence has the commit and the time of a later run, the labels those of the build | source_commit and built of the evidence are the revision and created labels of the image |
| 50 | `LocalFileSigLevel` above the global `SigLevel` | the first SigLevel line of /etc/pacman.conf is the global one |
| 50 | each `SigLevel` line removed | /etc/pacman.conf has a SigLevel line; SigLevel is Required in the shipped /etc/pacman.conf |
| 50 | a commented `#[multilib]` block added | /etc/pacman.conf has no multilib block |
| 50 | `pubring.gpg` cut to 0 bytes | the pacman keyring is populated |
| 50 | `/usr/bin/locale-gen` removed | locale-gen is in the image |
| 50 | `/usr/share/i18n/charmaps/UTF-8.gz` removed | the UTF-8 charmap is in the image |
| 50 | the password field of root emptied (`root::`) | the password field of root in /etc/shadow is not empty |
| 60 | `FROM scratch` with one file, so the probe cannot run | the probe runs inside the image; the file stops there |
| 60 | `/usr/bin/getfattr` removed | getfattr is in the image, and the two capability assertions after it |
| 60 | `/usr/bin/newuidmap` removed | /usr/bin/newuidmap is in the image |
| 60 | `setfattr -x security.capability /usr/bin/newgidmap` | /usr/bin/newgidmap has the attribute security.capability |
| 60 | `chmod ug-s` on each setuid and setgid file | /usr/bin/passwd keeps its setuid bit; at least 10 files keep a setuid or setgid bit |
| 60 | `/usr/bin/passwd` removed | /usr/bin/passwd is in the image |
| 60 | `/usr/sbin`, `/sbin` and `/bin` made real directories | /usr/sbin (/sbin, /bin) is a link |
| 60 | `ENV PATH="/usr/local/bin:/bin"` | PATH has /usr/bin |
| 60 | `/var/lib/pacman` removed; only `/var/lib/pacman/local` removed | /var/lib/pacman (local) is a directory; pacman starts and lists at least 50 installed packages |
| 60 | the `%BACKUP%` section of the filesystem package removed | /etc/hosts and /etc/resolv.conf are pacman backup files |
| 60 | `/etc/profile.d` emptied | at least 1 script runs on a login shell |
| 60 | a command that does not exist added to a profile script | a login shell writes nothing to stderr |
| 60 | `/etc/machine-id` removed; a published image with a 33-byte ID | the image has /etc/machine-id, and it is empty |
| 60 | the locale sources emptied, the charmaps cut to one file | the charmap and locale source counts, each of the 4 sources, the charmap of ja_JP and the date check |
| 60 | `/usr/bin/locale-gen` removed | locale-gen runs after ja_JP.UTF-8 is added to /etc/locale.gen |
| 60 | a file in `private-keys-v1.d` | the image has no private signing key in /etc/pacman.d/gnupg |
| 60 | `/usr/bin/awk` removed | each tool that pacman-key calls is on PATH |
| 60 | the hook and the linker removed | each assertion of section 9 |
| 60 | the linker at mode 0644 | bindir-links is executable, and the three assertions after it |
| 60 | a linker that links each file and never removes a link | the linker never hides a name that already resolves; a link goes when the executable it names goes |

⚠ Some faults fail more than one assertion: a missing `/var/lib/pacman/local` takes the `%BACKUP%` read with it, and a missing `awk` takes each fact that the probe reads with awk.

`locale-gen` exits 0 for a locale with no source, so its exit status is not the assertion. With `/usr/share/i18n/locales` emptied, the `locale-gen runs` assertion still passes, and the three checks after it fail.

### Scripts of the build stage

`install-port-keyring`, driven against the loong64 pin in a copy:

| fault | result |
| --- | --- |
| one character of the pinned sha256 changed | exit 1; both hashes printed |
| one trusted fingerprint removed from the pin | exit 1; the fingerprint in the package and not in the pin is named |
| one pinned expiry moved | exit 1; the key, the pinned date and the date of the keyring are named |
| the validity read pointed at an empty gpg homedir | exit 1; each of the 8 keys that must be usable is named, and the 2 expired keys are not |
| a second pin for the same architecture | exit 1; both pin files are named |
| none | 8 of 10 pinned keys are fully valid, and SigLevel stays Required |

`scripts/gen-evidence` refuses evidence with a hole: an installed package that is in no database of the snapshot fails the leg, and the message names the package. `tests/static/69-evidence-damaged-database.sh` checks the exit code.
