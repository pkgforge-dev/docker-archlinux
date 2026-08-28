# Releases, and what a git tag means here

⭐ **The framing this answers**: other tools import, extract and reuse these
images without container tooling. ArchPOWER, Arch Linux ARM and Arch RISC-V all
publish a rootfs tarball and this project did not.

## The two tag namespaces, decided before the first tag

⛔ **A git tag in this repository is a version of the tooling and the assets. It
is not an image version.** The two namespaces are deliberately different shapes
so neither can be mistaken for the other:

| namespace | shape | created by | means |
| --- | --- | --- | --- |
| image tags | `v2026.08.28` | `build-deploy.yml`, daily | the package set resolved on that date |
| git tags | `v0.1.0` | a person, rarely | a version of this repository's tooling and release assets |

⚠ **Both start with `v` and a `v*` tag is what `release.yml` triggers on.** A
date-shaped git tag would therefore read as an image version on the releases
page while behaving as a release. Semantic versioning was chosen for the git
side on 2026-08-29 by the maintainer, matching `pkgforge-dev/cross-libc-dlopen`,
which is at `v0.1.0` and is the repository whose release mechanics this one was
mined from.

## What a release carries

| asset | per | what it is |
| --- | --- | --- |
| `pacman-static-<arch>` | architecture | a static pacman, built from source |
| `pacman-static-<arch>.json` | architecture | its evidence: sources, versions, checksums, what it reported when run |
| `rootfs-<arch>.tar.gz` | architecture | the image filesystem, `docker export`, gzipped |
| `rootfs-<arch>.json` | architecture | its evidence: every package, version, size, sha256, release date |
| `bootstrap-set-<arch>.txt` | architecture | the resolved package set, `name version sha256`, no JSON and no tooling |
| `oci-<arch>.tar.gz` | architecture | the same image with its metadata, `podman load` with no network |
| `manifest.json` | release | every published tag with its digest, platforms and anchor |
| `SHA256SUMS` | release | one file covering all of the above |

⛔ **`docker export`, not `docker save`, for the rootfs.** export writes the
container filesystem, which is what a consumer with no container tooling
untars. save writes an image with layers and metadata, which is the `oci` asset.
They are different artefacts and both were asked for.

## The size, measured rather than estimated

Measured 2026-08-29 on this workstation, `linux/amd64`, gzip level 9:

| asset | bytes | |
| --- | --- | --- |
| `rootfs-amd64.tar.gz` | 188542400 | 179.8 MiB |
| `oci-amd64.tar.gz` | 189231028 | 180.5 MiB |
| `bootstrap-set-amd64.txt` | 19304 | 137 packages |
| `manifest.json` | 56936 | 176 tags |

```bash
stat -c '%s %n' rootfs-amd64.tar.gz oci-amd64.tar.gz bootstrap-set-amd64.txt manifest.json
```

```bash
cid=$(podman create --platform linux/amd64 localhost/archlinux:amd64 true)
podman export "$cid" | gzip -9 > rootfs-amd64.tar.gz
podman save localhost/archlinux:amd64 | gzip -9 > oci-amd64.tar.gz
```

⚠ **Eight architectures is 3132 MiB per release, measured on `v0.1.0`, and about
half of that is a near duplicate.** The OCI archive is 180.5 MiB against the rootfs tarball's
179.8 MiB because it is the same single layer plus a manifest and a config. A
consumer with a runtime can reach most of the same place with
`podman import rootfs-amd64.tar.gz`, losing only the recorded env, cmd and
labels.

⛔ **Both are published anyway, and the reason is written down rather than
assumed.** The maintainer chose the full asset list on 2026-08-29 after this
redundancy was raised. The measurement is here so the decision can be revisited
against a number rather than a feeling.

⚠ **gzip, not zstd.** zstd compresses this better and both runtimes read it, but
the stated point of the rootfs tarball is a consumer with no container tooling,
and gzip is the one decompressor that is always already there.

## The shape of the workflow

```
guard      the tag is on the default branch, and the static suite passes
  pacman   uses ./.github/workflows/pacman-static.yml, eight binaries
  rootfs   eight jobs: build, evidence, image suite, export, package set
  manifest read every published tag from the registry
publish    needs all four, only for a v* tag
```

⛔ **`needs:` over every producing job is what makes a partial failure publish
nothing.** A release missing one architecture is worse than no release: it looks
complete. The publish job counts the assets against the architecture set read
from `build-deploy.yml` before it creates anything.

⛔ **The guard runs first and everything needs it.** Eight image builds and eight
cross compiled pacmans is most of an hour of runner time, and a tag pointing at
a commit that never reached the default branch must cost none of it.

⛔ **`contents: write` is on the publish job and nowhere else.**
`tests/static/96-release-assets.sh` asserts that, and that `release.yml` is the
only workflow triggered by a `v*` tag: two workflows racing to create one
release means the loser fails after the winner published.

## The body is generated

⛔ **`scripts/release-notes` reads the evidence files beside the assets**, so
the release notes and the assets cannot disagree. A hand written body is a
second record that goes stale on the first bump while still reading as
authoritative. It refuses:

- a binary with no evidence file, and an evidence file with no binary;
- a rootfs archive with no evidence, no package set or no OCI archive;
- an evidence file recording zero packages;
- a `manifest.json` whose schema is not `docker-archlinux/manifest/1`;
- assets built from more than one pacman commit.

⚠ **`SHA256SUMS` excludes itself.** A checksum file that lists itself cannot
verify.

## First release: v0.1.0, 2026-08-29

⭐ **Run `33213236059`, green.** 50 assets: eight each of six families, plus
`manifest.json` and `SHA256SUMS`.

```bash
gh api repos/pkgforge-dev/docker-archlinux/releases/tags/v0.1.0 --jq '[.assets[].size]|add'
```

**3284077162 bytes, 3132 MiB, across 50 assets.** ⚠ The estimate on this page before the release was
2.9 GB, from doubling one architecture's measurement. The real figure is 13
percent higher because the eight architectures are not the same size.

⛔ **Verified by downloading, not by reading the run.** Three assets pulled from
the release page and checked against the published `SHA256SUMS`: `manifest.json`,
`bootstrap-set-ppc.txt` and `pacman-static-ppc`, all three matching. The ppc
evidence file records `Pacman v7.1.0 - libalpm v16.0.1`, machine `PowerPC`,
`interp_segments: 0`, and the signed tag verified by Allan McRae.
`manifest.json` carries 194 tags with 194 resolved to a digest.

### It took three attempts, and the first two are the useful part

| run | outcome | cause |
| --- | --- | --- |
| `33211181473` | all eight rootfs jobs failed | `gen-evidence` prefers podman, and the runner now has both podman and docker |
| `33212195947` | evidence passed, the image suite failed | a never-pushed local image has no `RepoDigests` |
| `33213236059` | green | the rootfs is exported from the published image, by digest |

⭐ **The second failure produced a better design than the one it replaced.** The
release used to build its own image and export that, so the asset's evidence
recorded the digest of something that was never published and matched nothing in
`manifest.json`. It now resolves the published per architecture tag to a digest,
pulls that, and exports it. The bytes in the tarball are the bytes consumers
already pull.

⛔ **Both failures published nothing.** `Publish the release` is gated on every
producing job and was skipped both times. That is the invariant working, seen
rather than argued.

⚠ **What is still unexercised.** A second release, so no upgrade path has been
walked. A release cut when a per architecture tag does not exist, which now
fails by design. And `docker save` output has never been loaded back with
`podman load`; the workflow asserts `gzip -t` and a size floor.

## What a release does not carry, found by review 25

⛔ **A rootfs tarball cannot be tied to a published image digest.** The release
job builds its own image, `release:<arch>`, exports it and never pushes it, so
`rootfs-<arch>.json` records the digest of a local build. That digest matches
nothing in `manifest.json` and nothing on either registry, and a consumer
comparing the two finds no match with no way to know that is expected.

⭐ **What it does carry.** `source_commit` in the evidence file ties the asset to
a revision of this repository, and `/etc/os-release` inside the tarball carries
`VERSION_ID` and `IMAGE_VERSION`. ⚠ It carries **no** commit: read out of a real
archive on 2026-08-29, `os-release` holds thirteen keys and none is a revision.
So the tarball alone dates itself and nothing more.

⚠ **The fix is not in the release.** Exporting the rootfs from the pushed image
rather than from a fresh local build would make the digest meaningful, and that
is a change to `build-deploy.yml`, which is where the pushed image exists. ⛔ Not
done, because it moves work from a job that runs on a tag into a job that runs
every day.
