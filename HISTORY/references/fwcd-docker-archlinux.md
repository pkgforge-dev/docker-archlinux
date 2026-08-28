# fwcd/docker-archlinux

⚠ **Scratch paths in this document** name fixtures under `.tmp/`, which is
gitignored and wiped between sessions. They record what a measurement was
taken against, not something a reader can open. ⛔ Nothing in the
repository depends on them. To re-run one, copy the tree to a scratch
directory, rebuild the fixture the surrounding text describes, and point the
command at that copy.

Reference study of where this repository's files came from. GitHub records this
repository as a fork of it. ⛔ It is treated as an independent project and
nothing is synced from it. This study is archaeology, and it answers questions
no other source can: why the bootstrap was circular, and where the signature
weakening came from.

## Provenance

| item | value |
| --- | --- |
| repository | `https://github.com/fwcd/docker-archlinux` |
| commit read | `e2ef381b78ac3f06b5bda5e0ce869871c43baddd` |
| commit date | 2025-08-29 |
| clone depth | 1 |
| licence | MIT, `LICENSE:1`, holders Stefan Agner 2020 and fwcd 2023 |
| tracker read | 5 items, 4 pull requests and 1 issue, all closed, all merged |
| studied on | 2026-08-26 |

```bash
git clone --depth 1 -q "https://github.com/fwcd/docker-archlinux.git" fwcd-docker-archlinux
git -C fwcd-docker-archlinux rev-parse HEAD
gh api --paginate "repos/fwcd/docker-archlinux/issues?state=all&per_page=100" \
  --jq '.[] | "\(.number)\t[\(.state)]\t\(if .pull_request then "PR" else "IS" end)\t\(.title)"'
```

## Verdict: confirms, and one anti-pattern exhibit kept on purpose

⭐ **Nothing here is adopted.** Every mechanism worth taking was already taken
before this study, because this repository started as a copy of the tree. What
the study produces is the **reason** behind three choices that were inherited
without an explanation, and one licence correction that was already right.

## The licence has three holders, and this repository names all three

`LICENSE:3` and `LICENSE:4` at the read commit:

```
Copyright (c) 2020 Stefan Agner
Copyright (c) 2023 fwcd
```

⭐ Stefan Agner predates the project this repository forked. `LICENSE` here
carries both lines and adds `Copyright (c) 2026 pkgforge`. Checked:

```bash
head -8 LICENSE
```

Both original holders are kept. That is the correct handling of an MIT
derivative and it needs no change.

## Finding 1: the circular bootstrap was a return, not an original state

`Dockerfile:1` at the read commit:

```
FROM ghcr.io/fwcd/archlinux:latest AS bootstrap
```

The image bootstraps from its own published output. `tests/static/10-bootstrap-not-circular.sh`
here fails on exactly that shape.

The history explains it:

```bash
gh api --paginate 'repos/fwcd/docker-archlinux/commits?path=Dockerfile&per_page=100' \
  --jq '.[] | "\(.sha[0:12])\t\(.commit.author.date[0:10])\t\(.commit.message | split("\n")[0])"'
```

| commit | date | subject |
| --- | --- | --- |
| `1dd7187a62e6` | 2023-08-30 | Bootstrap the image from itself |
| `c69ca9247283` | 2023-08-30 | Bootstrap from alpine |
| `a489faaa8797` | 2023-09-13 | Bootstrap from alpine edge |
| `6a6594e2afab` | 2023-12-16 | Fix marginal trust issues on ARM by allowing weak key signatures |
| `8b1beabac09b` | 2024-03-18 | Bootstrap from archlinux again |

⭐ **A non-circular bootstrap ran for six and a half months**, from 2023-08-30
to 2024-03-18, across amd64, arm64, armv7 and riscv64.

## Finding 2: the Alpine bootstrap's price was signature checking

This is the finding that matters for D3, and it is visible in the diff of the
pull request that introduced it. Pull request 1, `Bootstrap Arch Linux from
Alpine`, merged 2023-08-30, seven files, +375/-14:

```bash
gh api "repos/fwcd/docker-archlinux/pulls/1" --jq '"merged=\(.merged) +\(.additions)/-\(.deletions)"'
```

The four lines it added to the Dockerfile:

```dockerfile
RUN apk add pacman && \
    cp -r /rootfs/etc/pacman.d /etc/ && \
    cp /rootfs/etc/pacman.conf /etc/pacman.conf && \
    sed -i 's/\(SigLevel\s\+=\s\+\).\+/\1Never/g' /etc/pacman.conf
```

⛔ **`SigLevel` is set to `Never` for the whole bootstrap.** Alpine's `pacman`
package carries no Arch keyring, so nothing can verify an Arch package, and the
build works by not checking.

⭐ **So "bootstrap from a smaller base" and "keep signatures on" are not the
same problem, and solving the first this way loses the second.** Policy 5
forbids that trade here.

⚠ The move to `alpine:edge` at `a489faaa8797` states its reason in the commit
message: `...since this image seems to actually provide a riscv64 port`. The
constraint was the base image's architecture coverage, not pacman's version.

⚠ The return to the self-referencing base at `8b1beabac09b` carries a one line
subject and no stated reason. The record does not say why.

⭐ **What this means for D3.** `pacman-static` plus a pinned keyring is a
different proposal from the one that was tried here, and it is different in the
exact place this one failed: it keeps `SigLevel = Required`. The Alpine result
is evidence about the shortcut, not about the goal.

## Finding 3: the signature weakening, and what replaced it

`Dockerfile:18` at the read commit:

```bash
RUN sed -i 's/^\(GPG_PACMAN=(.*\))/\1 --allow-weak-key-signatures)/g' /rootfs/usr/bin/pacman-key
```

Issue 5 is why it exists. Reported 2023-12-03, closed 2023-12-16, five comments.
The reporter's build broke overnight:

```
error: asciidoc: signature from "Arch Linux ARM Build System <builder@archlinuxarm.org>" is marginal trust
error: failed to commit transaction (invalid or corrupted package (PGP signature))
```

The reporter's own interim workaround, from the thread, was to sign the key
locally:

```bash
gpg --homedir=/etc/pacman.d/gnupg/ --quick-sign-key "$fingerprint"
```

⭐ **This repository's answer is that workaround made durable.**
`bootstrap/any/usr/local/bin/install-alarm-keyring` fetches the Arch Linux ARM
keyring package, checks it against a pinned sha256 and a pinned master key
fingerprint in `bootstrap/keyrings/archlinuxarm.pin`, installs it, and runs
`pacman-key --populate archlinux archlinuxarm`, which does the local signing
properly. `SigLevel = Required` stays on and no pacman file is patched.

⛔ Policy 5 records that the `--allow-weak-key-signatures` patch was removed and
must not return. `tests/static/30-signature-checking-on.sh` is the guard.

### The same failure, on a different port

⚠ **Marginal trust is not an ARM-only story.** `HISTORY/removed-architectures.md`
records i686 excluded because a packager key reaches only two valid master
signatures where gpg needs three, so it stays marginal and `SigLevel = Required`
refuses it. Issue 5 is the same mechanism on Arch Linux ARM in 2023.

⭐ Two independent ports, two years apart, one cause. That is the argument for
the ARM keyring being pinned and watched rather than assumed, which is what
`.github/workflows/freshness-keyring.yml` and `scripts/check-keyring-pin` do.

## Finding 4: two shellcheck defects, and what they were

`bootstrap/any/usr/local/bin/pacstrap-docker` at the read commit is 37 lines.
Diffed against this repository's version:

```bash
diff -u .tmp/phased/refs/fwcd-docker-archlinux/bootstrap/any/usr/local/bin/pacstrap-docker \
        bootstrap/any/usr/local/bin/pacstrap-docker
```

| line there | shape | what it does |
| --- | --- | --- |
| 4 and 8 | `echo "==> $@"` | `$@` inside a quoted string. Every argument after the first is dropped from the message. |
| 32 | `trap "rm '$newroot/dev/null'" EXIT` | double quotes expand `$newroot` when the trap is set rather than when it runs |

Both are fixed here, at `bootstrap/any/usr/local/bin/pacstrap-docker:22`, `:26`
and `:51`.

⭐ **A third change is not a shellcheck finding and matters more.** There:

```bash
mkdir -m 0755 -p "$newroot"/{var/{cache/pacman/pkg,lib/pacman,log},dev,run,etc}
```

`mkdir -m` applies the mode to the final component only, so the intermediate
directories `var`, `var/cache` and `var/lib` are created with the umask instead.
Here that is split into `mkdir -p` followed by explicit `chmod` on each path.

## Finding 5: the daily build is a commit, and it fires the build twice

`.github/workflows/trigger-build.yml:23`:

```bash
git commit --allow-empty -m "Trigger build ($(date -I))"
```

`.github/workflows/build-deploy.yml:4` triggers on `push` to `main`, and
`:11` also triggers on `workflow_run` of `Trigger Build` with
`types: [completed]`.

⚠ Two observations, both about the record rather than about anyone:

- An empty commit pushed to `main` matches the `push` trigger, and the
  `workflow_run` completion matches too. Both fire from one scheduled run.
- ⛔ `types: [completed]` fires on failure as well as success. There is no
  `if: github.event.workflow_run.conclusion == 'success'` guard, so a failed
  trigger job still starts a build.

⭐ **Kept as an anti-pattern exhibit.** `.github/workflows/build-deploy.yml`
here runs from `schedule` directly and writes no commit, so neither shape is
present. The exhibit is worth keeping because the second one is silent: a
workflow that starts after a failure looks identical in the run list to one that
started after a success.

## Finding 6: the actions are unpinned

`.github/workflows/build-deploy.yml` names `actions/checkout@v3`,
`docker/setup-qemu-action@v2`, `docker/setup-buildx-action@v2`,
`docker/login-action@v1` and `docker/build-push-action@v4`. All are moving tags.

⭐ Policy 10 is the rule this repository applies instead, and
`tests/static/50-supply-chain.sh` is the check. Recorded as the contrast, not as
a defect anybody has to act on.

## What this study did not do

- The build was not run and no image from it was pulled.
- `bootstrap/*/etc/bootstrap-packages.txt` and the `rootfs/*` trees were not
  compared file by file against this repository's. Only `pacstrap-docker`,
  `Dockerfile` and the two workflows were diffed or read in full.
- Pull requests 2, 3 and 4 were confirmed merged and their titles and sizes
  recorded. Only pull request 1's diff was read.
- ⚠ The `ppc64le` tree present there is not present here.
  `HISTORY/removed-architectures.md` carries that measurement and this study did
  not re-derive it.
- Nothing was written to the upstream repository. Reads only.
