#FROM ghcr.io/fwcd/archlinux:latest AS bootstrap
FROM pkgforge/archlinux:latest AS bootstrap

#------------------------------------------------------------------------------------#
##Build Args
ARG TARGETARCH
ARG TARGETVARIANT
#------------------------------------------------------------------------------------#

#------------------------------------------------------------------------------------#
##Bootstrap
COPY /bootstrap/any /
COPY /bootstrap/${TARGETARCH}${TARGETVARIANT} /
COPY /rootfs/any /rootfs
COPY /rootfs/${TARGETARCH}${TARGETVARIANT} /rootfs
#------------------------------------------------------------------------------------#

#------------------------------------------------------------------------------------#
##Install the base packages
RUN cat /etc/bootstrap-packages.txt | xargs pacstrap-docker /rootfs 2>/dev/null
#------------------------------------------------------------------------------------#

#------------------------------------------------------------------------------------#
##Fixes
# Fix marginal trust errors on Arch Linux ARM
RUN <<EOS
  set +e
  sed -i 's/^\(GPG_PACMAN=(.*\))/\1 --allow-weak-key-signatures)/g' "/rootfs/usr/bin/pacman-key" 2>/dev/null || true
  rm /rootfs/var/lib/pacman/sync/* 2>/dev/null || true
  sed 's/DownloadUser/#DownloadUser/g' -i "/etc/pacman.conf" 2>/dev/null || true
EOS
#------------------------------------------------------------------------------------#

#------------------------------------------------------------------------------------#
##Copy the bootstrapped rootfs
FROM scratch
COPY --from=bootstrap /rootfs /
#------------------------------------------------------------------------------------#

#------------------------------------------------------------------------------------#
##Initialize
# Set up pacman-key without distributing the lsign key
# See https://gitlab.archlinux.org/archlinux/archlinux-docker/-/blob/301942f9e5995770cb5e4dedb4fe9166afa4806d/README.md#principles
# Source: https://gitlab.archlinux.org/archlinux/archlinux-docker/-/blob/301942f9e5995770cb5e4dedb4fe9166afa4806d/Makefile#L22
RUN <<EOS
  set +e
  pacman-key --init 2>/dev/null || true
  pacman-key --populate 2>/dev/null || true
  bash -c "rm -rf etc/pacman.d/gnupg/{openpgp-revocs.d/,private-keys-v1.d/,pubring.gpg~,gnupg.S.}*" 2>/dev/null || true
  sed 's/DownloadUser/#DownloadUser/g' -i "/etc/pacman.conf" 2>/dev/null || true
EOS
#------------------------------------------------------------------------------------#

#------------------------------------------------------------------------------------#
#ENV
RUN <<EOS
 #Locale
  echo "LC_ALL=en_US.UTF-8" | tee -a "/etc/environment"
  echo "en_US.UTF-8 UTF-8" | tee -a "/etc/locale.gen"
  echo "LANG=en_US.UTF-8" | tee -a "/etc/locale.conf"
  locale-gen "en_US.UTF-8"
EOS
ENV LANG="en_US.UTF-8"
ENV LANGUAGE="en_US:en"
ENV LC_ALL="en_US.UTF-8"
#------------------------------------------------------------------------------------#

#------------------------------------------------------------------------------------#
#Entrypoint
CMD ["/usr/bin/bash"]
#------------------------------------------------------------------------------------#