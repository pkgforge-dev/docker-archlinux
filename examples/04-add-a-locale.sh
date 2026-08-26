#!/usr/bin/env bash
#
# Add a non-English locale.
#
# This image ships no NoExtract rule, so the locale source data under
# /usr/share/i18n/locales is present and the obvious two lines work.
#
# ⚠ For one build they did not. usr/share/i18n was withheld and locale-gen
# printed "Generation complete" having generated nothing. See
# HISTORY/noextract-reverted.md.
#
# Run this inside the container.
#
# ⚠ pipefail is deliberately not set. `ls --help | head -1` makes head close the
# pipe after one line, ls takes SIGPIPE, and pipefail turns that into a failed
# pipeline. Under set -e the script then dies at 141 having done everything
# right. These are commands to run at a prompt, not a build step.
set -eu

# What the image starts with.
locale -a   # C, C.utf8, en_US.utf8, POSIX

# 1. The definition is already there.
ls /usr/share/i18n/locales/de_DE

# 2. Generate it.
echo "de_DE.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen

locale -a   # now includes de_DE.utf8

# 3. Use it. ⚠ The image sets all three of these, and they do not have equal
# weight:
#
#     LANG=en_US.UTF-8
#     LC_ALL=en_US.UTF-8      beats LANG
#     LANGUAGE=en_US:en       beats LC_ALL, for messages only
#
# So `LANG=de_DE.UTF-8 <cmd>` changes nothing on this image: LC_ALL wins.
env | grep -E '^(LANG|LC_ALL|LANGUAGE)='

# Formatting follows LC_ALL.
LC_ALL=de_DE.UTF-8 date '+%A'      # Mittwoch
LC_ALL=en_US.UTF-8 date '+%A'      # Wednesday

# Translated program messages are a separate set of files, under
# /usr/share/locale, and come back with the packages that own them.
pacman -S --noconfirm gettext coreutils
ls /usr/share/locale/de/LC_MESSAGES/

# ⚠ LC_ALL alone still prints English, because LANGUAGE is a GNU gettext
# variable that overrides it for messages. Clear it or set it too.
# These read ls's own help text to show whether it is translated, rather than
# listing files. LANGUAGE='' clears the variable for one command, which is the
# point being demonstrated.
# shellcheck disable=SC2012
{
  LC_ALL=de_DE.UTF-8 ls --help | head -1                  # Usage: ...  still English
  LANGUAGE='' LC_ALL=de_DE.UTF-8 ls --help | head -1      # Aufruf: ...  translated
  LANGUAGE=de LC_ALL=de_DE.UTF-8 ls --help | head -1      # Aufruf: ...  translated
}

# To make it the container default, override all three.
#   docker run --rm -it -e LANG=de_DE.UTF-8 -e LC_ALL=de_DE.UTF-8 -e LANGUAGE=de <image>
