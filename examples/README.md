# Examples

Each file runs as written. `tests/static/80-docs-claims.sh` parses every one of
them and every fenced block in the two README files, so a command here that
does not parse fails the build.

| file | what it shows |
| --- | --- |
| [`01-pull-a-per-architecture-tag.sh`](01-pull-a-per-architecture-tag.sh) | pulling one architecture instead of the index, and that the alias names share a digest |
| [`02-pin-to-a-dated-tag.sh`](02-pin-to-a-dated-tag.sh) | the four things that never move: a dated index tag, a dated architecture tag, an anchor tag, and a digest |
| [`03-database-and-filesystem-agree.sh`](03-database-and-filesystem-agree.sh) | checking that every path `pacman -Ql` lists is on disk, for the base install and for a package added afterwards |
| [`04-add-a-locale.sh`](04-add-a-locale.sh) | adding a non-English locale |
| [`05-as-a-base-image.Dockerfile`](05-as-a-base-image.Dockerfile) | using the image as a `FROM`, pinned by digest |
| [`06-verify-provenance.sh`](06-verify-provenance.sh) | reading the provenance attestation, the SBOM and the OCI labels |
| [`07-consume-the-evidence-file.sh`](07-consume-the-evidence-file.sh) | reading the per-platform evidence file a build publishes |

Where to run each one:

| | on the host | inside the container |
| --- | --- | --- |
| 01, 02, 06, 07 | yes | |
| 03, 04 | | yes |
| 05 | it is a Dockerfile | |

Start a container to run 03 or 04 in:

```bash
docker run --rm -it ghcr.io/pkgforge-dev/archlinux:latest
```
