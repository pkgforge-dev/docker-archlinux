# Operations

This document tells what runs by itself, which issues the automation raises and clears, and what a person must do. [design.md](design.md) gives the rules behind each job.

## Workflows and schedules

| workflow | name | triggers | does |
| --- | --- | --- | --- |
| `build-deploy.yml` | `Build and publish` | cron `30 5 * * *` and `30 17 * * *`, dispatch | plan, build each port, publish to GHCR, copy to Docker Hub, report, start the status site, watch the schedules |
| `status.yml` | `Status` | cron `23 * * * *`, dispatch, and `build-deploy.yml` after each build | measure the images, render the site, push the branch `status`, deploy Pages, raise or clear `status-down` and `registry-drift` |
| `watchdog.yml` | `Watchdog` | cron `40 7 * * *`, dispatch | recency of each port, the schedules, the status site, re-runs of the CI of Renovate pull requests |
| `freshness.yml` | `Freshness` | cron `45 4 * * 1`, dispatch | each pin against its upstream |
| `pacman-static.yml` | `Static pacman` | cron `20 3 * * 0`, dispatch, and `release.yml` | build the static pacman of each port |
| `release.yml` | `Release` | push of a `v*` tag, cron `15 6 1 * *`, dispatch | the release assets |
| `ci.yml` | `CI` | pull request, push to `main`, dispatch | the test suites and the linters |
| `bot-merge.yml` | `Merge Renovate's pin bumps` | `workflow_run` of `CI`, completed | approve and merge a Renovate pull request that only moves pins |

Every workflow keeps these rules, and `tests/static/51-workflow-policy.sh` checks each one:

- `permissions: {}` at the top.
- `ubuntu-24.04` and `timeout-minutes` on each job. A job that calls a reusable workflow has no timeout of its own.
- Each action pinned by commit.

### The jobs of the watchdog

| job | does |
| --- | --- |
| `recency` | `scripts/check-publish-recency`, then a step that runs after a failure too: raises or clears `stale-<arch>` and `stale-index` |
| `schedules` | `scripts/watch-schedules`, then `dispatch-overdue build-deploy.yml 1560` and `dispatch-overdue status.yml 180` |
| `status-site` | reads `status.json` from the branch `status`, then `scripts/check-status-site`: `status-down` and `pages-stale` |
| `bot-ci` | `scripts/rerun-bot-ci` |

### The jobs of freshness

| job | compares | issue |
| --- | --- | --- |
| `image-pins` | each `# tag:` image pin of `Dockerfile`, the workflows and `scripts/` with the digest of its tag (`scripts/check-image-pins --max-age 14 --seen RECORD`). RECORD is the artifact `image-pins-seen` (90 days) of the newest run on the default branch | `image-pins-stale` |
| `keyring-list`, `keyring` | each `bootstrap/keyrings/*.pin` with the database of its port (`scripts/check-keyring-pin`); a newer package goes into a pull request (`scripts/propose-change`) | `keyring-<pin>` |
| `pacman-static` | each source of `bootstrap/pacman-static/sources.pin` with its newest release, and the pinned pacman commit with the pacman of each port | `pacman-static-sources`, `pacman-static-pin` |
| `tools` | each tool of `scripts/install-tools --pins` with its newest release | `tools-drift` |
| `pacman-oci` | `bootstrap/any/usr/local/bin/pacman-oci` with the copy on the default branch of mirror-archlinux | `pacman-oci-drift` |

### Concurrency

| workflow | group | cancels a run in progress |
| --- | --- | --- |
| `build-deploy.yml` | `build-deploy-<ref>`, and `build-deploy-<ref>-dry` for a dry run; job `publish` `publish-<target image>`; job `hub` `hub-<hub target>` | ⛔ never |
| `status.yml` | `status`; job `deploy` `pages` | never |
| `watchdog.yml` | `watchdog` | never |
| `freshness.yml` | `freshness` | never |
| `release.yml` | `release-<ref>` | never |
| `ci.yml` | `ci-pr-<number>` for a pull request, else the run id | a newer push to a pull request cancels its older run |
| `bot-merge.yml` | `bot-merge-<head branch>` | never |

`pacman-static.yml` has no group, so a dispatch cannot cancel the jobs that `release.yml` calls.

⚠ GitHub keeps one pending run in a group, and a newer run replaces it. So a third run of `build-deploy.yml` replaces a pending second run. A dry run has a group of its own, so it never replaces a pending real run.

## Each scheduled workflow starts the others

⛔ GitHub can delay or drop a scheduled run, and a dropped run leaves nothing that can report it. So the scheduled workflows run `scripts/dispatch-overdue WORKFLOW MAX_MINUTES` for each other.

| runs in | starts | when its newest run on the default branch is older than |
| --- | --- | --- |
| `build-deploy.yml` job `watch` | `watchdog.yml` | 1560 minutes |
| `build-deploy.yml` job `watch` | `status.yml` | 180 minutes |
| `watchdog.yml` job `schedules` | `build-deploy.yml` | 1560 minutes |
| `watchdog.yml` job `schedules` | `status.yml` | 180 minutes |

A run that is queued or in progress counts as fresh. A workflow with no run is started. A workflow that is not active is not started: GitHub refuses the dispatch.

`scripts/keep-schedules-enabled` runs inside `scripts/watch-schedules`. GitHub disables the schedules of a repository after 60 days with no activity. The script enables each workflow that GitHub disabled. ⚠ A workflow that a person disabled stays disabled, and `schedules-stopped` names it.

`scripts/check-schedules-fired` reads every workflow with a cron line, and measures it against its own cron. The tolerance is `gap + min(gap, 7) + 1` days (`scripts/cron-tolerance`): 3 for a daily cron, 15 for a weekly cron, 39 for a monthly cron. ⛔ A tolerance above 60 days is refused: GitHub stops the schedules of a repository after 60 days with no activity. ⚠ The tolerance has day resolution, so a stop of an hourly cron shows after 3 days.

⚠ When every schedule stops at once, no run is left to notice. Start `watchdog.yml` by hand.

## Issues the automation raises and clears

`scripts/track-issue` keeps one issue per problem, with the label `automation`. `raise` opens the issue once and then only writes its title and body. `clear` comments and closes it. The key is in the body as `<!-- track: KEY -->`. The script lists every open issue to find it, and never searches. ⛔ Only an issue that `github-actions[bot]` (`TRACK_ISSUE_AUTHOR`) opened, with the marker at the start of its body, counts.

| issue | raised when | cleared when | by |
| --- | --- | --- | --- |
| `build-<arch>` | the leg of a planned port fails | the job `publish` passes, and its output `published` names the port | `scripts/report-build`, `build-deploy.yml` job `report` |
| `publish-ghcr` | the job `publish` fails, or does not run while ports were planned | the job `publish` passes | `scripts/report-build` |
| `publish-hub` | the job `hub` fails | the job `hub` passes | `scripts/report-build` |
| `stale-<arch>` | GHCR or Docker Hub has no `<first alias>-v<date>` within the tolerance of the build cron | each registry has one within the tolerance | `watchdog.yml` job `recency` |
| `stale-index` | the same, for `v<date>` | the same | `watchdog.yml` job `recency` |
| `schedules-stopped` | a schedule did not fire within its tolerance, or a person disabled a workflow | both checks ran, every schedule fires, no workflow is disabled by a person | `scripts/watch-schedules`, in `watchdog.yml` and in `build-deploy.yml` job `watch` |
| `failing-<stem>` | the newest 3 completed scheduled runs of `<stem>.yml` failed | its newest completed scheduled run succeeded | `scripts/watch-schedules` |
| `failing-release` | one scheduled run of `release.yml` failed: it fires once a month | a scheduled run of `release.yml` succeeded | `release.yml` job `report`, and `scripts/watch-schedules` |
| `status-down` | `status.yml` job `build` did not succeed, or the record is older than 3 hours (`status.yml`); the record on the branch `status` is missing or older than 6 hours (watchdog) | a `build` succeeds and its record is at most 3 hours old | `scripts/check-status-record`, `scripts/check-status-site` |
| `pages-stale` | the Pages copy of `status.json` does not answer, or trails the branch `status` by more than 3 hours | the copy answers and trails by 3 hours or less | `scripts/check-status-site`, `watchdog.yml` job `status-site` |
| `registry-drift` | the parity of GHCR and Docker Hub is below 1 in 2 runs in a row | a fresh record has parity 1 | `scripts/check-status-record`, `status.yml` job `check` |
| `image-pins-stale` | an image pin is behind its tag for more than 14 days, counted from the first weekly run that saw it behind (artifact `image-pins-seen`) | no pin is behind for more than 14 days | `freshness.yml` job `image-pins` |
| `keyring-<pin>` | one of: the pinned package is served with other bytes (5); no server answered (6); a newer package has no trusted signer (7); a newer package trusts another set of fingerprints; every usable key expires within 1 year | none of these | `freshness.yml` job `keyring` |
| `pacman-static-sources` | a pinned source of the static pacman is behind its newest release | each source is at its newest release | `freshness.yml` job `pacman-static` |
| `pacman-static-pin` | a port that answered publishes another pacman commit than the pin | each port that answered publishes the pinned commit | `freshness.yml` job `pacman-static` |
| `tools-drift` | a tool of `scripts/install-tools` is behind its newest release | each tool is at its newest release | `freshness.yml` job `tools` |
| `pacman-oci-drift` | the vendored pacman-oci differs from the copy on the default branch of mirror-archlinux | the copies are the same | `freshness.yml` job `pacman-oci` |

⛔ The keys `build-ppc`, `build-ppc64` and `build-ppc64le` keep that exact shape. Issues 13, 14 and 15 carry them, and close on the first publish of those ports.

⚠ A failing workflow raises `failing-<stem>` and does not turn `scripts/watch-schedules` red: the watchers are scheduled workflows too. Only a stopped schedule exits 3. The jobs `watch` of `build-deploy.yml` and `schedules` of `watchdog.yml` take exit 3 as handled and stay green.

A dry run of `build-deploy.yml` raises no issue: the jobs `report` and `watch` do not run.

## What runs by itself

- A build of each port twice each day. The second cron builds only the ports that did not publish in the first.
- The mirror lists of each port, generated in each build leg. The committed lists are the fallback, and need no pull request.
- The status site every hour, and after each build.
- The watchdog every day, freshness every week, the static pacman every week, a release every month.
- The scheduled workflows start each other when a newest run is overdue, and keep every schedule enabled.
- Renovate moves action pins, image digests and runner labels. `bot-merge.yml` approves and merges a Renovate pull request that only moves pins, with no major version change. It merges when the required check `Static suite and linters` passed on the head commit. A failed `network` job does not stop it. ⚠ A pull request opened by Renovate on a `renovate/` branch of this repository is the only kind it merges.
- `scripts/rerun-bot-ci` re-runs the failed CI of an open Renovate pull request once a day, at most 3 times for one head commit.
- A keyring pin whose newer package has the same fingerprints needs no person for the build: `install-port-keyring` follows the newer package forward, through pacman's signature check against the pinned keys.

## What needs a person

- **A keyring pull request.** `freshness.yml` opens it on a `freshness/` branch with the built-in token. GitHub refuses the approval of the account that opened a pull request, so a person merges it. With new fingerprints, `keyring-<pin>` also asks a person to check the keys.
- **A major Renovate update, and a runner label update.** Renovate opens it, and it waits for a person.
- **The static pacman sources.** `pacman-static-sources` names the newer release. Measure the new sha256, then change `bootstrap/pacman-static/sources.pin`:

  ```bash
  curl -sSfL --connect-timeout 20 --max-time 900 -o f URL && sha256sum f
  ```

- **The pacman commit of the static pacman.** `pacman-static-pin` names the commit that the ports publish. Change the `pacman`, `describe` and `tag` records of the pin.
- **A tool pin.** Each pin of `scripts/install-tools` has a sha256, which Renovate cannot write. `tools-drift` names the release. Read the asset ids and digests, then change `scripts/install-tools`:

  ```bash
  gh api repos/OWNER/REPO/releases/tags/TAG --jq '.assets[] | [.id, .name, .digest] | @tsv'
  ```

  meson is a source tarball. Read its sha256 from PyPI:

  ```bash
  curl -sSf --connect-timeout 20 --max-time 60 https://pypi.org/pypi/meson/VERSION/json | jq -r '.urls[] | select(.packagetype == "sdist") | .digests.sha256'
  ```

- **The vendored pacman-oci.** `pacman-oci-drift` names the difference. Copy the file at the new commit, then set the three values of `bootstrap/pacman-oci.pin` from it.
- **The Docker Hub token.** `DOCKERHUB_TOKEN` and `DOCKERHUB_USERNAME` are repository secrets. When the token expires, `publish-hub` opens. Make a new token and set the secret.
- **Pages.** Pages is enabled with `build_type=workflow`. Only a person can do that, with an admin token. When Pages is off, `pages-stale` opens:

  ```bash
  gh api -X POST repos/pkgforge-dev/docker-archlinux/pages -f build_type=workflow
  ```

- **A disabled workflow.** Enable a workflow that a person disabled, when that decision no longer holds. `schedules-stopped` names it.
- **An anchor below the floor.** When `check-anchor-floor` refuses a port and the revert rule does not apply, check the anchor upstream. To take it, start a build with `allow_anchor_downgrade` set to the port.

## Branch protection and settings

The branch `main`, measured with `gh api repos/pkgforge-dev/docker-archlinux/branches/main/protection`:

| setting | value |
| --- | --- |
| required check | `Static suite and linters` |
| approving reviews | 1 |
| stale reviews dismissed | yes |
| enforced on admins | no |
| force push | denied |
| deletion | denied |
| conversations must resolve | yes |

⛔ Keep two names. The job `check` of `ci.yml` is named `Static suite and linters`, and branch protection waits for a check of that name. `bot-merge.yml` starts on the workflow named `CI`. `tests/policy/required-checks` names the check, and `tests/static/99-docs-paths.sh` checks both names.

| repository setting | value |
| --- | --- |
| `default_workflow_permissions` | `write`. Every workflow sets `permissions: {}` at the top, so the default applies to none |
| `can_approve_pull_request_reviews` | `true`. ⛔ `bot-merge.yml` needs it to approve a Renovate pull request |
| Pages | `build_type=workflow`, `https://pkgforge-dev.github.io/docker-archlinux/` |

The branch `history-archive` holds the history before the rewrite, tip `9d1e1429259625323139cb39dd1c81764c73501d`. ⚠ It has no protection, and `main` has no ancestry that keeps its objects.

## Secrets

| secret | used in |
| --- | --- |
| `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN` | `build-deploy.yml` job `hub` only |

Every other job uses the workflow's own `GITHUB_TOKEN`, with the permissions of its job. ⛔ No build leg has a secret.

## The status branch and Pages

On the default branch, `status.yml` job `build` pushes the branch `status` as one orphan commit, with force, on each run. The branch holds the site and:

| file | contents |
| --- | --- |
| `status.json` | the record of the run, schema 1 |
| `history.jsonl` | one line per run, the last 2000 lines. A port that a run could not read keeps the values of its last line, marked `"k": 1` |
| `evidence/<arch>.json` | the newest evidence of each port, carried for a port that did not build |
| `evidence/<arch>.digest` | the image digest that this evidence describes |

The next run reads `history.jsonl` and `evidence/` from the branch. On a first run, with no branch, it reads the newest `status-history` artifact (90 days). Only a run of `status.yml` by this repository on the default branch counts. The job `keep` uploads that artifact after a `build` that passed. `release.yml` reads `evidence/<arch>.json` from the branch. The watchdog reads `status.json` from it.

The badge and chart URLs:

```text
https://pkgforge-dev.github.io/docker-archlinux/badges/<name>.svg
https://pkgforge-dev.github.io/docker-archlinux/charts/<name>.svg
https://pkgforge-dev.github.io/docker-archlinux/charts/narrow/<name>.svg
```

## Start a build

The inputs of `build-deploy.yml`:

| input | default | does |
| --- | --- | --- |
| `arches` | empty: every port | the ports to build, space separated |
| `force` | false | build a port also when its dated tag for today exists |
| `dry_run` | false | push to the scratch images `<image>-ci`, raise no issue |
| `dry_run_hub` | false | with `dry_run`, also copy to the Docker Hub scratch image |
| `allow_anchor_downgrade` | `none` | `none`, `all`, or the ports whose anchor may go below the floor |

```bash
gh workflow run build-deploy.yml --ref main
gh workflow run build-deploy.yml --ref main -f arches='riscv64' -f force=true
```

⚠ A dispatch on a day that already published moves the rolling tags only. The dated tags of that day keep the first image.

### A dry run

A dry run builds, tests and tags the scratch images `ghcr.io/<owner>/archlinux-ci` and, with `dry_run_hub`, `docker.io/pkgforge/archlinux-ci`. It reads the published images for the floor and the carried digests, and never writes them. Its run name is `Build and publish (dry run)`, and the status site does not count it as a build.

```bash
gh workflow run build-deploy.yml --ref BRANCH -f dry_run=true
gh workflow run build-deploy.yml --ref BRANCH -f dry_run=true -f dry_run_hub=true
```

Each publish script also has a plan mode that reads the registries and writes nothing:

```bash
GHCR_IMAGE=ghcr.io/pkgforge-dev/archlinux HUB_IMAGE=docker.io/pkgforge/archlinux scripts/plan-build --dry-plan
SOURCE_IMAGE=ghcr.io/pkgforge-dev/archlinux HUB_TARGET=docker.io/pkgforge/archlinux scripts/sync-hub --dry-plan
```

## Add a port

1. Write `ports/<arch>.conf` with every key of the port table ([design.md](design.md#the-port-table)).
2. Write `rootfs/<arch>/etc/pacman.conf`. Copy the `[options]` block of another port, and change only `Architecture`.
3. Write `mirrors/<arch>.anchors`, the GHCR mirror first. Add `mirrors/<arch>.<X>-anchors` for each other list that pacman.conf includes, and an optional `mirrors/<arch>.pool`.
4. Run `scripts/gen-mirrorlist <arch>` to write the committed lists.
5. Write `bootstrap/<arch>/etc/bootstrap-packages.txt`: one package name per line, no comment.
6. When the keys of the port are not in `archlinux-keyring`, add `bootstrap/keyrings/<name>.pin` and its package. Name the pin in the key `keyring`, and add the `pacman_arch` to the `arch` line of the pin.
7. Check the emulator. `scripts/binfmt-register` needs no edit when its fallback table has the emulator that the key `qemu` names. The table holds every emulator of qemu's `scripts/qemu-binfmt-conf.sh`. For an emulator that the table does not have, add its name, magic and mask from that qemu file. Add them to `TABLE` in `scripts/binfmt-register` and to `tests/fixtures/64-plan-build/binfmt.tsv`. `scripts/binfmt-register --line ARCH` and `tests/static/64-plan-build.sh` stop and name both files.
8. Run the static suite. `tests/static/75-architecture-set.sh` names each file that is missing.
9. Start a dry run with `arches` set to the port.

The workflows, the other scripts and the tests read the port table, and need no edit.

## Recovery

| state | do |
| --- | --- |
| `build-<arch>` is open | read the failed step in the run that the issue names. The port keeps its last image in `latest` while it waits. The issue closes on the first publish of the port |
| a port that no server answers for | the leg fails at `resolve-anchor`. The port comes back with no edit on the first day a server of its lists answers from a runner |
| the GHCR mirror is behind | the build drops it for that run (`drop LIST SERVER` in the log). The image still ships it. Nothing to do |
| the Worker does not answer | `pick-transport` gives `oci`, and the build stage reads GHCR through pacman-oci. Nothing to do |
| the base image registry does not answer | `pick-base-image` takes the same digest from `mirror.gcr.io`, or for the base image from `public.ecr.aws`. The buildkit image falls back to `mirror.gcr.io` too. Nothing to do |
| `publish-hub` is open | the next run copies each missing tag. A failure there never touches GHCR. Check the Docker Hub secrets |
| `registry-drift` is open | the job `hub` of the next build copies the missing and moved tags. A build with nothing to build runs `hub` too |
| `status-down` or `pages-stale` is open | read the run of `status.yml` that the issue names, and start it again: `gh workflow run status.yml --ref main` |
| a release failed part way | start the workflow again. A draft at the commit of the run is finished. A draft at another commit is deleted and made again. To make a published release again, delete it first: `gh release delete TAG` |
| `stale-<arch>` is open, and no `build-<arch>` | the builds do not start. Check `schedules-stopped`, then start a build by hand |
