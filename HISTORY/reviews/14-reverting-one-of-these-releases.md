# Review 14: somebody who has to revert one of these releases

**Lens.** The loong64 port turns out to be a mistake, or the port itself goes
away. Somebody reverts the commit. What comes back, what does not, and what does
a consumer see on the day after.

**Date.** 2026-08-28, against the tree that adds loong64 and the evidence
snapshot. The revert was performed, not reasoned about.

---

## What was checked

The revert itself, in a scratch clone:

```bash
git clone --no-hardlinks . /tmp/revert
cd /tmp/revert && git revert --no-edit HEAD
REPO_ROOT="$PWD" bash tests/run.sh static
```

⭐ **It applies cleanly and the reverted tree passes `20 files, failed: 0`.**
Nothing in the four architecture tree depends on a file the fifth added. The
seven added files come out, the twenty edited files go back, and
`75-architecture-set.sh` reads four from the matrix again and stops asking for
the fifth.

Then what the revert does **not** undo.

| what | after a revert |
| --- | --- |
| the six published loong64 tags | ⛔ still there and still resolving. No tag is ever removed |
| `:latest` and `:v<date>` | rebuilt over four platforms on the next run |
| a loong64 consumer pulling `:latest` | an error, measured below |
| a loong64 consumer pulling `:loong64` | the last loong64 image ever built, frozen |
| `scripts/check-anchor-floor` | never asked about loong64 again, because the matrix no longer names it |

## What a loong64 consumer sees

The real index carries no loong64 today, so this is measurable now rather than
hypothetical:

```bash
podman manifest inspect docker.io/pkgforge/archlinux:latest \
  | jq -r '[.manifests[].platform | select(.os != "unknown")
            | .architecture + (if .variant then "/" + .variant else "" end)] | sort | join(" ")'
podman pull --platform linux/loong64 docker.io/pkgforge/archlinux:latest
```

```
amd64 arm/v7 arm64 riscv64
Error: ... no image found in image index for architecture "loong64", variant "", OS "linux"
```

⭐ **That is the good failure.** The consumer gets an error naming the
architecture, not an image of the wrong one. Standing policy 7 says an existing
consumer must notice no difference; a consumer who arrived because of this change
notices a clear one, which is the best available outcome for a withdrawal.

⚠ **The frozen single architecture tag is the sharper edge.**
`:loong64` keeps resolving after a revert, to an image that stops receiving
updates and says nothing about it. Nothing in this repository can express
"withdrawn" through a tag, because nothing is ever removed. The only signal is
that `.built` in the evidence file and the `org.opencontainers.image.created`
label stop moving.

## What is coupled, and would break a partial revert

⛔ **The keyring change cannot be half reverted.** `install-alarm-keyring` was
replaced by `install-port-keyring`, and the pin format changed at the same time:
`archlinuxarm.pin` gained `keyring`, `arch` and `mirror` fields and traded
`master = <fpr>` for `trusted = <fpr> <expiry>`. The Dockerfile also stopped
copying one pin to a fixed path and started copying the whole directory.

Both halves of that were run, with the old script taken out of `HEAD~1`:

```bash
git show HEAD~1:bootstrap/any/usr/local/bin/install-alarm-keyring > old-installer
ALARM_KEYRING_PIN=bootstrap/keyrings/archlinuxarm.pin bash old-installer
ALARM_KEYRING_PIN=/usr/local/share/docker-archlinux/archlinuxarm.pin bash old-installer
```

| partial revert | what the ARM build says |
| --- | --- |
| the script only, pin kept | `install-alarm-keyring: pin file not found: /usr/local/share/docker-archlinux/archlinuxarm.pin`, exit 1 |
| the script and the copy path, pin kept | `install-alarm-keyring: ... is missing a value for fpr`, exit 1 |

⭐ **Both are loud and both name the file.** Neither produces an image. Reverting
the whole commit is safe, was tested, and is the only shape that works.

⭐ **The evidence snapshot reverts independently.** It is a separate commit,
`30d75ed`, and touches no file the loong64 commit touches except the Dockerfile
and the build workflow, in different places. Reverting it restores the fetch
path, which still works: `scripts/gen-evidence` keeps both paths and the fetch
one was exercised on the same image, producing an identical package table.

---

## What was found and changed

Nothing. This review changed no file.

## What was ruled out

- **A dirty revert.** Tried, clean, suite green.
- **A test that only passes with five architectures.** The reverted tree passes
  the whole static suite, so no assertion was written to require loong64.
- **A dangling reference from the four architecture tree into a loong64 file.**
  `git revert` deleted `rootfs/loong64/`, `bootstrap/loong64/`,
  `mirrors/loong64.*` and `bootstrap/keyrings/archlinux-lcpu.pin`, and nothing
  broke, which is the check.

## ⚠ What this did not look at

- **Reverting after loong64 tags exist.** None are published yet. The dry run
  wrote to `archlinux-ci`, so the frozen tag behaviour above is derived from how
  the registry treats a tag nobody moves, not observed on a real one.
- **The Docker Hub side.** Only GHCR indexes were inspected.
- **A revert of the evidence snapshot in CI.** The reasoning above is from
  reading the diff and from the fetch path having been exercised locally, not
  from a run with it reverted.
- **Whether a consumer would notice.** No downstream repository was contacted or
  inspected for a loong64 reference. There cannot be one yet.

## Change summary

Files touched: 0. Lines added: 0. Lines removed: 0.
