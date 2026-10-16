# Examples

Each file runs as it is. `tests/static/80-docs-claims.sh` parses each shell example, and each fenced bash block of the documents, with `bash -n`.

| file | shows | runs | needs |
| --- | --- | --- | --- |
| [`01-pull-a-per-architecture-tag.sh`](01-pull-a-per-architecture-tag.sh) | a pull of one port, not the index; two tags of one port have one digest | on the host | `docker` with `buildx`, `jq` |
| [`02-pin-to-a-dated-tag.sh`](02-pin-to-a-dated-tag.sh) | the four things that never move: a dated index tag, a dated tag of one port, an anchor tag, and a digest | on the host | `docker` with `buildx`, `jq`, `curl` |
| [`03-database-and-filesystem-agree.sh`](03-database-and-filesystem-agree.sh) | each path that `pacman -Ql` lists is on disk, for the installed packages and for a package installed later | inside the container | the image |
| [`04-add-a-locale.sh`](04-add-a-locale.sh) | a locale that is not English | inside the container | the image |
| [`05-as-a-base-image.Dockerfile`](05-as-a-base-image.Dockerfile) | the image in `FROM`, pinned by digest | as a Dockerfile | `docker` |
| [`06-verify-provenance.sh`](06-verify-provenance.sh) | the provenance attestation, the SBOM and the OCI labels | on the host | `docker` with `buildx`, `jq` |
| [`07-consume-the-evidence-file.sh`](07-consume-the-evidence-file.sh) | the evidence file of a port | on the host | `jq`. The download of its input needs `curl` or `gh` |

`tests/static/80-docs-claims.sh` checks that the column `needs` names each tool that an example runs.

Start a container for 03 or 04:

```bash
docker run --rm -it ghcr.io/pkgforge-dev/archlinux:latest
```
