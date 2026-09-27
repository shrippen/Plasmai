#!/usr/bin/env bash
# Opens the Plasmai widget in plasmoidviewer with the demo profile (made-up Kimai data in
# memory, the shrippen demo world "Studio Weber"). Uses the working tree, not the installed copy.
#   demo/start.sh [de|en]
set -euo pipefail
source "$(dirname "$0")/common.sh"
XDG_CONFIG_HOME="${CONFIG}" LANGUAGE="${LANG_}" LANG="${LOCALE}" LC_MESSAGES="${LOCALE}" \
    plasmoidviewer -a "${ROOT}" -f horizontal -l bottomedge -s 900x60
