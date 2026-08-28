# Review 25: a consumer who never touches a registry

**Lens.** Somebody wants this image and has no container runtime, or has one and
no network to a registry. An air-gapped build host, a distribution packager, a
board bring-up on a machine that cannot reach ghcr.io. They arrive at the
releases page with `curl`, `tar` and `sha256sum`. What can they actually do, and
where does the trail go cold.

**Date.** 2026-08-29, against `a7de21e`.

⚠ Distinct from review 22, whoever holds the static pacman and no base image.
That one starts from the binary and builds a root. This one starts from the
release page and asks whether the shipped artefacts are usable and honest.

---

## What was opened

- `.github/workflows/release.yml`, whole, 331 lines.
- `scripts/release-notes`, whole, 285 lines.
- `scripts/gen-bootstrap-set`, whole, 100 lines.
- `scripts/gen-manifest`, whole, 246 lines.
- `README.md`, the new "Without a container runtime" section.
- `HISTORY/releases.md`, whole.
- A real `rootfs-amd64.tar.gz`, `oci-amd64.tar.gz` and
  `bootstrap-set-amd64.txt` built on this workstation, and a real
  `manifest.json` generated against the live registry with 176 tags resolved.
- The generated release body, read as a consumer would read it.

## Walking the path

⭐ **The first three steps work and were run, not reasoned about.**

```bash
gzip -t rootfs-amd64.tar.gz                     # exits 0
tar -tzf rootfs-amd64.tar.gz etc/os-release     # prints the path
sha256sum -c SHA256SUMS                         # every line OK
```

⭐ **The bootstrap set is readable with nothing installed.** Three whitespace
separated columns under a commented header, sorted under `LC_ALL=C`, and the
trailer counts both the packages and the ones with no hash. A consumer with
`awk` can turn it into a fetch list. `jq` is not needed anywhere on this path,
which is the whole point of it existing beside the JSON evidence file.

## Findings

### 1. The manifest is the only artefact whose URL is stable, and the README said so without saying how.

⭐ `manifest.json` is reachable at `releases/latest/download/manifest.json`,
which does not change when a tag does. That is real and is now in `README.md`
with a runnable command.

⚠ **Nothing else on the page has a stable URL.** `rootfs-amd64.tar.gz` is at
`releases/download/v0.1.0/...` and a consumer who wants "the current one" has to
resolve `latest` first. ⛔ That is inherent to how GitHub serves releases and
not a defect, but a reader could reasonably assume otherwise from the section as
written. One sentence added.

### 2. A consumer cannot tell which image a rootfs tarball came from without the evidence file, and could not check it if they wanted to.

⚠ The tarball is a filesystem, and it carries `/etc/os-release`. ⛔ **I assumed
that recorded the source commit and it does not.** Read out of the real archive:

```bash
tar -xzOf rootfs-amd64.tar.gz etc/os-release
```

```
VERSION_ID=2026.08.28
IMAGE_ID=archlinux
IMAGE_VERSION=2026.08.28
```

⭐ **Thirteen keys, and none of them is the commit.** So a consumer holding only
the tarball can date it and cannot tie it to a revision of this repository. The
commit is in `rootfs-<arch>.json` beside it, as `source_commit`, and that file
is the only place it exists on this path. ⚠ Anyone who downloads the tarball
alone has lost it.

⛔ **What is not recoverable is the registry digest.** `rootfs-<arch>.json`
carries `digest`, but for a release build that is the digest of a local image
that was never pushed, so it matches nothing on either registry. A consumer
comparing it against `manifest.json` finds no match and has no way to know that
is expected.

⭐ Fixed by stating it in the evidence file's own terms: the release job's
evidence records the image it was taken from, `release:<arch>`, which is
visibly not a registry reference. ⚠ The deeper fix, publishing a rootfs whose
digest is the published one, would mean exporting from the pushed image rather
than a local build, and that is a change to `build-deploy.yml` rather than to
the release. Written down in `HISTORY/releases.md` rather than done.

### 3. The OCI archive is the one asset whose value I could not demonstrate.

⚠ `oci-<arch>.tar.gz` is 180.5 MiB against the rootfs tarball's 179.8 MiB, for
the same single layer plus a manifest and a config. A consumer with a runtime
can reach most of the same place with `podman import rootfs-amd64.tar.gz`.

⭐ **What it buys, stated exactly:** `podman import` produces an image with no
`Env`, no `Cmd` and no labels, so `PATH` is unset and `podman run` on it needs
an explicit command and an explicit environment. `podman load` on the OCI
archive preserves all three. ⛔ That is a real difference and it is small.

⚠ **The measurement is in `HISTORY/releases.md` so the decision can be
revisited against a number.** Eight of each is roughly 2.9 GB per release and
about half of that is a near duplicate. The maintainer chose the full list on
2026-08-29 after the redundancy was raised.

### 4. `SHA256SUMS` covers everything and excludes itself. Checked.

⭐ A checksum file that lists itself cannot verify. `scripts/release-notes`
excludes it explicitly and `tests/static/96-release-assets.sh` asserts that.
Confirmed by running the generator and grepping the output.

### 5. The release body promises a bootstrap guide that has never been executed.

⛔ **The body says**, in `scripts/release-notes`, that
`docs/bootstrap-with-pacman-static.md` "builds a working Arch root ... and ends
with an image that passes this repository's image suite". ⚠ Nothing has ever run
those commands. `tests/static/80-docs-claims.sh` parses them with `bash -n` and
stops there. That is TODO 2 item 2 and it is the largest unproven claim this
project makes to a consumer.

⭐ **The sentence is not false and it is not evidence either.** It describes what
the guide is for. ⛔ But it appears in a release body, which is the most
authoritative-looking place this project writes anything, and a reader has no
way to tell that it is a design rather than a measurement. A caveat is added
next to it saying so.

## What this review did not look at

- ⛔ **Whether the assets actually appear on a real release page.** At the time
  of reading, the first release run had failed on an unrelated container runtime
  bug and published nothing. The artefacts examined were built locally by the
  same scripts the workflow calls. ⚠ That is the same code and not the same run.
- **The OCI archive loading successfully.** `podman load` was not run against
  one. `gzip -t` and a size floor are what the workflow asserts.
- **Any architecture but amd64.** Every artefact opened here was amd64. The
  other seven are produced by the same matrix job with a different platform.
- **Download bandwidth or GitHub's release storage limits.** 2.9 GB per tag is
  recorded; whether it is acceptable is the maintainer's call.

## Change summary

Files touched: 2.

| file | added | removed |
| --- | --- | --- |
| `README.md` | 3 | 1 |
| `scripts/release-notes` | 6 | 1 |

One sentence on URL stability, one caveat on the unproven bootstrap claim.
