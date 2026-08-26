# Review 2: an attacker at build time

**Lens.** Assume an attacker who controls one thing: a mirror, a registry, an
action, or a merged pull request. For each, what do they get?

**What was looked at.** Every `FROM`, every `curl`, every `pacman` invocation
reachable from a build, every `uses:` across all four workflows, every
`secrets.` reference, the `permissions:` block of every job, and the transport
of every one of the 46 mirror entries.

**Date.** 2026-08-26.

---

## The fetch surface, complete

A build reaches the network in exactly three places:

| # | what | where | transport | what pins it |
| --- | --- | --- | --- | --- |
| 1 | the base image | `Dockerfile:10` | https, registry | `@sha256:b860afd5...`, a content digest |
| 2 | the Arch Linux ARM keyring | `install-alarm-keyring:52` | **http** | sha256 of the package, plus the master fingerprint read from inside it |
| 3 | packages and databases | `pacstrap-docker:36`, via pacman | 26 https, 20 http | `SigLevel = Required` on packages. `DatabaseOptional` on databases |

Nothing else fetches. Verified:

```bash
grep -nE 'curl|wget|https?://' Dockerfile bootstrap/any/usr/local/bin/*
```

## Fetch 2, the keyring over plain http

⭐ **This is safe, and the reason is worth stating precisely.** The transport is
`http://mirror.archlinuxarm.org/aarch64/core`, so an on-path attacker can
replace the bytes. They gain nothing:

```
install-alarm-keyring:66   got_sha="$(sha256sum "$work/keyring.pkg" | ...)"
install-alarm-keyring:67   if [ "$got_sha" != "$want_sha" ]; then ... exit 1
install-alarm-keyring:85   got_fpr="$(cut -d: -f1 < .../archlinuxarm-trusted)"
install-alarm-keyring:86   if [ "$got_fpr" != "$want_fpr" ]; then ... exit 1
```

Substituted bytes fail the sha256 and the build stops. The plain http is a
transport detail, not a trust dependency. ⚠ Arch Linux ARM does not serve https
on that endpoint at all, so switching the scheme is not available.

## Fetch 3, the real finding

⛔ **An on-path attacker on the two ARM ports can force a rollback.**

- 20 of the 46 mirror entries are plain http: 10 on arm64, 10 on armv7. amd64
  and riscv64 are https only.
- `SigLevel = Required` means a forged or unsigned package is refused. That
  holds.
- `DatabaseOptional` means the *database* is not signature checked, and it has
  to be: `core.db.sig` is 404 on Arch Linux ARM.

```bash
curl -s -o /dev/null -w '%{http_code}\n' -L http://mirror.archlinuxarm.org/aarch64/core/core.db.sig   # 404
curl -s -o /dev/null -w '%{http_code}\n' -L http://mirror.archlinuxarm.org/aarch64/core/core.db       # 200
```

So an attacker who can rewrite http traffic can serve an **older database**.
Every package it names is genuinely signed, so every signature check passes, and
the build produces an image pinned to superseded package versions. That is a
rollback to known vulnerable versions, achieved without breaking any signature.

⭐ **What limits it.** The evidence file records every package version, size and
sha256, and the anchor version names the `pacman` build. A rollback is visible
in the published evidence and in the pinned tag family: an image built from a
stale database gets an anchor tag naming the older `pacman`, which does not match
the other three architectures. It is detectable after the fact, not prevented.

⚠ **What would fix it, and neither is available today.** Signed databases from
upstream, or https on every ARM mirror. Of 20 Arch Linux ARM subdomains, three
answer https.

## Credentials

```bash
awk '/^  [a-z_]+:$/ { job=$1 } /secrets\./ { print job, $0 }' .github/workflows/build-deploy.yml
```

| job | holds | scope |
| --- | --- | --- |
| `resolve` | nothing | `contents: read` |
| `build` | `GITHUB_TOKEN` | `contents: read`, `packages: write` |
| `publish` | `GITHUB_TOKEN`, `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN` | `contents: read`, `packages: write` |

⭐ The Docker Hub credentials exist in one job only, and that job runs nothing
from the tree except `scripts/tag-names`, which takes no input from the network.

⚠ `build` holds `packages: write` because push-by-digest requires it. A
compromised build job can push arbitrary blobs to GHCR. It cannot create a tag,
because tags are created only in `publish` from the digests the matrix exported,
and `publish` refuses when any digest is missing.

## Actions

All seven are pinned to a 40 character commit hash with the version in a
comment, and `tests/static/50-supply-chain.sh` fails if that ever stops being
true. Seen to fail against `actions/checkout@v7.0.1`.

`persist-credentials: false` is set on every checkout in `build-deploy.yml` and
`ci.yml`, so the token is not written into `.git/config` where a later step could
read it.

⚠ **It is deliberately absent in the two freshness workflows**, which need the
credential to push a branch. Those are the highest privilege jobs in the
repository, at `contents: write` plus `pull-requests: write`. They run only on a
schedule or a dispatch, never on a pull request, so untrusted code cannot reach
them.

## A merged pull request

Before this review: any merge reached `packages: write` and the Docker Hub token
with no review at all. `main` was unprotected.

Now: one approving review from one of the four people with push access, a
passing `Static suite and linters` check, and the branch has to be up to date.
Applied and verified:

```bash
gh api repos/pkgforge-dev/docker-archlinux/branches/main/protection
```

⚠ `enforce_admins` is off, so the three admins can still push to `main`
directly. That is the deliberate trade for the low maintenance requirement, and
it means the protection is a guard against outside contributions, not against
the admins.

## What this review did NOT look at

- ⛔ **The contents of the seven pinned actions.** They are pinned to a hash, so
  they cannot change under us, but no one here has read what they do at those
  hashes.
- ⛔ **The official Arch image at the pinned digest.** Its contents are trusted
  wholesale. Review 3 covers what happens when it moves, not what is in it.
- **The GitHub Actions cache.** `cache-from`/`cache-to` use `type=gha` scoped
  per architecture. A poisoned cache entry could inject a layer. Not analysed.
- **The runner itself**, and anything about GitHub's own infrastructure.
- **Docker Hub's account security**, or how `DOCKERHUB_TOKEN` was scoped when it
  was created. That token's permissions were not read, because reading it is not
  possible from here.
- **Dependency confusion in the package names** in `bootstrap/*/etc/bootstrap-packages.txt`.
  They are `base` and `archlinuxarm-keyring`, both real, but no check asserts a
  name there resolves to the repository it is expected to come from.
