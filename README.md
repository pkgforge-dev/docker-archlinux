- #### [Docker images of Arch Linux](https://hub.docker.com/r/pkgforge/archlinux/tags) [![Build and Deploy](https://github.com/pkgforge/docker-archlinux/actions/workflows/build-deploy.yml/badge.svg)](https://github.com/pkgforge/docker-archlinux/actions/workflows/build-deploy.yml)

Unofficial, automated Docker multi-platform images of Arch Linux for the following architectures:

| Architecture | Docker Platform | Distribution |
| ------------ | --------------- | ------------ |
| x86_64 | `linux/amd64` | [Arch Linux](https://archlinux.org) |
| aarch64 | `linux/arm64` | [Arch Linux ARM](https://archlinuxarm.org) |
| armv7h | `linux/arm/v7` | [Arch Linux ARM](https://archlinuxarm.org) |
| riscv64 | `linux/riscv64` | [Arch Linux RISC-V](https://archriscv.felixc.at) |

- #### Usage
```bash
!# --privileged is DANGEROUS but often fixes lots of DNS & Internet Issues
!# --platform="${PLATFORM}" can be set to run other ArchLinux on Supported System (Requires QEMU)
## --platform="linux/arm64" --> Lets you test the aarch64 version of ArchLinux on x86_64 Host
!# --rm will delete the container upon exit

!# This will drop you in a bash shell
docker run --rm -it --privileged --net="host" "pkgforge/archlinux:latest"
```
