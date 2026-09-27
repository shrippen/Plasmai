# Shared by demo/start.sh and demo/shots.sh: a scratch config home with the demo profile.
# The demo profile points at DemoKimai's reserved address (contents/code/demoKimai.js):
# Studio Weber, the demo world shared by all shrippen projects, in memory.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/plasmai-demo-XXXXXX")"
trap 'rm -rf "${WORK}"' EXIT
CONFIG="${WORK}/config"
mkdir -p "${CONFIG}/com.github.shrippen.plasmai"
cp -p "${XDG_CONFIG_HOME:-${HOME}/.config}/kdeglobals" "${CONFIG}/" 2>/dev/null || true
cat > "${CONFIG}/com.github.shrippen.plasmai/shared.json" <<'JSON'
{"profilesJson": "[{\"id\":\"demo\",\"name\":\"Demo\",\"url\":\"https://demo.invalid\",\"provider\":\"kimai\"}]",
 "activeProfileId": "demo"}
JSON
LANG_="${1:-${DEMO_LANG:-de}}"
case "${LANG_}" in de) LOCALE=de_DE.UTF-8 ;; *) LOCALE=en_GB.UTF-8 ;; esac
# The package's translations only load for an installed widget; offer them from a data dir.
mkdir -p "${WORK}/data/locale"
cp -r "${ROOT}/contents/locale/." "${WORK}/data/locale/"
export XDG_DATA_DIRS="${WORK}/data:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
