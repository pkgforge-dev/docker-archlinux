#!/usr/bin/env bash
#
# Add a locale that is not English.
#
# The image has no NoExtract rule, so the locale sources under
# /usr/share/i18n/locales are there, and two commands generate a locale.
#
# ⚠ locale-gen exits 0 when a locale has no source. So check the result with
# locale -a, not with the exit status.
#
# Run this inside the container.
#
# ⚠ This script does not set pipefail. `ls --help | head -1` closes the pipe
# after one line, and ls gets SIGPIPE. With pipefail, that is a failed
# pipeline, and set -e stops the script with status 141.
set -eu

# What the image has.
locale -a   # C, C.utf8, en_US.utf8, POSIX

# 1. The source of the locale is there.
ls /usr/share/i18n/locales/de_DE

# 2. Generate it.
echo "de_DE.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen

locale -a   # now with de_DE.utf8

# 3. Use it. ⚠ The image sets three variables, and they do not have equal
# weight:
#
#     LANG=en_US.UTF-8
#     LC_ALL=en_US.UTF-8      overrides LANG
#     LANGUAGE=en_US:en       overrides LC_ALL, for messages only
#
# So `LANG=de_DE.UTF-8 <cmd>` changes nothing in this image: LC_ALL wins.
env | grep -E '^(LANG|LC_ALL|LANGUAGE)='

# Formats follow LC_ALL.
LC_ALL=de_DE.UTF-8 date '+%A'      # a German day name
LC_ALL=en_US.UTF-8 date '+%A'      # an English day name

# The translated messages of a program are in /usr/share/locale. They come
# with the package that owns them.
pacman -Syu --noconfirm --needed gettext coreutils
ls /usr/share/locale/de/LC_MESSAGES/

# ⚠ LC_ALL alone still gives English messages. LANGUAGE is a GNU gettext
# variable that overrides it for messages. Clear it, or set it too.
# These lines read the help text of ls to show whether it is translated.
# LANGUAGE='' clears the variable for one command.
# shellcheck disable=SC2012
{
  LC_ALL=de_DE.UTF-8 ls --help | head -1                  # Usage: ...  English
  LANGUAGE='' LC_ALL=de_DE.UTF-8 ls --help | head -1      # Aufruf: ...  German
  LANGUAGE=de LC_ALL=de_DE.UTF-8 ls --help | head -1      # Aufruf: ...  German
}

# To make it the default of a container, set all three.
#   docker run --rm -it -e LANG=de_DE.UTF-8 -e LC_ALL=de_DE.UTF-8 -e LANGUAGE=de <image>
