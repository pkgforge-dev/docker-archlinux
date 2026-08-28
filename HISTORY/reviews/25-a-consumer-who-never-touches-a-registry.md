# Review 25: a consumer who never touches a registry

**Lens.** Somebody wants this image and has no container runtime, or has one and
no network to a registry. An air-gapped build host, a distribution packager, a
board bring-up on a machine that cannot reach ghcr.io. They arrive at the
releases page with `curl`, `tar` and `sha256sum`. What can they actually do, and
where does the trail go cold.

**Date.** 2026-08-29. Read against `a7de21e`, then re-run against the published
`v0.1.0` release and updated, because finding 2 was acted on between the two.

⚠ Distinct from review 22, whoever holds the static pacman and no base image.
That one starts from the binary and builds a root. This one starts from the
release page and asks whether the shipped artefacts are usable and honest.

---

## What was opened

- `.github/workflows/release.yml`, whole, 425 lines after the change.
- `scripts/release-notes`, whole, 318 lines after the change.
- `scripts/gen-bootstrap-set`, whole, 99 lines.
- `scripts/gen-manifest`, whole, 252 lines.
- `README.md`, the new "Without a container runtime" section.
- `HISTORY/releases.md`, whole.
- A real `rootfs-amd64.tar.gz`, `oci-amd64.tar.gz` and
  `bootstrap-set-amd64.txt` built on this workstation, and a real
  `manifest.json` generated against the live registry with 176 tags resolved.
- The generated release body, read as a consumer would read it.
- After the release published: its 50 asset names, and three assets downloaded
  from the page and verified against the published `SHA256SUMS`.

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

⛔ **When this was first read, the registry digest was not recoverable.**
`rootfs-<arch>.json` carried a `digest`, but the release built its own image and
never pushed it, so that digest matched nothing on either registry. A consumer
comparing it against `manifest.json` found no match with no way to know that was
expected.

⭐ **Fixed properly rather than documented.** The release now resolves the
published per architecture tag to a digest, pulls that, and exports it. The
tarball is the bytes consumers already pull and its evidence names a reference
the registry knows. ⚠ The fix was forced by a second, unrelated failure: a
never-pushed image has no `RepoDigests`, so `tests/image/40-evidence.sh`
assertion 10 failed and the release could not be cut at all. `HISTORY/releases.md`
records both.

### 3. The OCI archive is the one asset whose value I could not demonstrate.

⚠ `oci-<arch>.tar.gz` is 180.5 MiB against the rootfs tarball's 179.8 MiB, for
the same single layer plus a manifest and a config. A consumer with a runtime
can reach most of the same place with `podman import rootfs-amd64.tar.gz`.

⭐ **What it buys, stated exactly:** `podman import` produces an image with no
`Env`, no `Cmd` and no labels, so `PATH` is unset and `podman run` on it needs
an explicit command and an explicit environment. `podman load` on the OCI
archive preserves all three. ⛔ That is a real difference and it is small.

⚠ **The measurement is in `HISTORY/releases.md` so the decision can be
revisited against a number.** `v0.1.0` measured 3132 MiB across 50 assets and
about half of that is the near duplicate. The maintainer chose the full list on
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

- **The OCI archive loading successfully.** `podman load` was not run against
  one, on the workstation or in CI. `gzip -t` and a size floor are what the
  workflow asserts, and that is the weakest assertion in the release.
- **Five of the six asset families on seven of the eight architectures.** After
  the release published, three assets were downloaded and checked against
  `SHA256SUMS`: `manifest.json`, `bootstrap-set-ppc.txt` and `pacman-static-ppc`,
  all matching. ⛔ No `rootfs-*.tar.gz` was downloaded from the release page and
  untarred; the one opened in finding 2 was built on this workstation by the same
  script. ⚠ Same code, different run.
- **Any architecture but amd64.** Every artefact opened here was amd64. The
  other seven are produced by the same matrix job with a different platform.
- **Download bandwidth or GitHub's release storage limits.** 3132 MiB per tag is
  recorded; whether it is acceptable is the maintainer's call.

## Change summary

Files touched: 3. ⚠ Session totals against `4992326`, not this review's share.

```bash
git diff --numstat 4992326 -- README.md scripts/release-notes .github/workflows/release.yml
```

| file | added | removed |
| --- | --- | --- |
| `.github/workflows/release.yml` | 425 | 0 |
| `scripts/release-notes` | 181 | 17 |
| `README.md` | 30 | 0 |

This review's own additions: one paragraph on URL stability and on where the
commit lives, one caveat on the unproven bootstrap claim, and the change from
building an image to exporting the published one.
