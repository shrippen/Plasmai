#!/bin/sh
# Compile *.po → contents/locale/<lang>/LC_MESSAGES/plasma_applet_<id>.mo
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT/translate"

PLUGIN_ID="com.github.shrippen.plasmai"
DOMAIN="plasma_applet_${PLUGIN_ID}"

for po in *.po; do
    [ -f "$po" ] || continue
    lang="${po%.po}"
    outdir="$ROOT/contents/locale/${lang}/LC_MESSAGES"
    mkdir -p "$outdir"
    msgfmt -o "${outdir}/${DOMAIN}.mo" "$po"
    echo "Built ${lang} → contents/locale/${lang}/LC_MESSAGES/${DOMAIN}.mo"
done
