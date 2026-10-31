#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# crawl-links.sh — Discovers and lists ALL navigable links of a site using wget
#
# Usage:
#   ./crawl-links.sh <URL> [DEPTH]
#
# Options:
#   --no-robots              → ignore robots.txt (respected by default)
#   --span-hosts             → follow allowed subdomains/hosts
#   --allow-domains=a,b,c    → exact list of allowed domains
#
# Output:
#   links_<domain>/links.txt   → unique URLs (http/https)
#   links_<domain>/spider.log  → full wget log
#
# Requirements: bash, wget, grep, sed, awk
# ------------------------------------------------------------------------------
set -euo pipefail

# ---------- checks ----------
need() { command -v "$1" >/dev/null 2>&1 || { echo "[✗] Falta '$1'"; exit 1; }; }
for c in wget grep sed awk; do need "$c"; done

# ---------- parse args ----------
RESPECT_ROBOTS=1
SPAN_HOSTS=0
ALLOW_DOMAINS=""

while [[ $# -gt 0 && "$1" == --* ]]; do
  case "$1" in
    --no-robots) RESPECT_ROBOTS=0; shift ;;
    --span-hosts) SPAN_HOSTS=1; shift ;;
    --allow-domains=*) ALLOW_DOMAINS="${1#*=}"; shift ;;
    *) echo "[!] Opción desconocida: $1"; exit 1 ;;
  esac
done

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Uso: $0 [--no-robots] [--span-hosts] [--allow-domains=a,b] <URL> [PROFUNDIDAD]"
  exit 1
fi

URL="$1"
DEPTH="${2:-3}"

[[ "$URL" =~ ^https?:// ]] || { echo "[!] URL debe iniciar con http:// o https://"; exit 1; }
[[ "$DEPTH" =~ ^[0-9]+$ && "$DEPTH" -ge 1 ]] || { echo "[!] PROFUNDIDAD debe ser entero ≥ 1"; exit 1; }

DOMAIN="$(printf '%s\n' "$URL" | awk -F/ '{print $3}')"
OUTDIR="links_${DOMAIN}"
LOG="$OUTDIR/spider.log"
LINKS_TXT="$OUTDIR/links.txt"
mkdir -p "$OUTDIR"

# ---------- allowed domains ----------
if [[ -n "$ALLOW_DOMAINS" ]]; then
  DOMAINS="$ALLOW_DOMAINS"
else
  BASE_APEX="$(echo "$DOMAIN" | sed -E 's/^[Ww]{3}\.//')"
  WITH_WWW="www.${BASE_APEX}"
  DOMAINS="$DOMAIN"
  case ",$DOMAINS," in *,"$WITH_WWW",*) : ;; *) DOMAINS="${DOMAINS},${WITH_WWW}";; esac
  case ",$DOMAINS," in *,"$BASE_APEX",*) : ;; *) DOMAINS="${DOMAINS},${BASE_APEX}";; esac
fi

# ---------- wget flags (arrays ALWAYS initialized) ----------
declare -a ROBOT_FLAG=()
declare -a SPAN_FLAG=()

if (( RESPECT_ROBOTS == 1 )); then
  ROBOT_FLAG=(-e robots=on)
else
  ROBOT_FLAG=(--ignore-robots -e robots=off)
fi

if (( SPAN_HOSTS == 1 )); then
  SPAN_FLAG=(--span-hosts)
fi

# We use --debug to make sure "Found … / URL: …" lines show up in the log.
# *** Careful with set -u: use safe array expansion ***
WGET_SPIDER_FLAGS=(
  --spider --recursive --level="$DEPTH" --no-parent
  --domains="$DOMAINS"
  ${SPAN_FLAG[@]+"${SPAN_FLAG[@]}"}      # only expands if set
  ${ROBOT_FLAG[@]+"${ROBOT_FLAG[@]}"}    # only expands if set
  --user-agent="Mozilla/5.0"
  --timeout=20 --tries=2
  --no-verbose --debug
  -o "$LOG"
)

echo "[i] Descubriendo links desde: $URL"
echo "[i] Profundidad: $DEPTH  | Respeta robots: $((RESPECT_ROBOTS==1 ? 1 : 0))  | Dominios: $DOMAINS"
(( SPAN_HOSTS == 1 )) && echo "[i] span-hosts: ON (seguirá subdominios/hosts permitidos)"

# ---------- spider ----------
wget "${WGET_SPIDER_FLAGS[@]}" "$URL" || true

# ---------- robust URL extraction from the log ----------
awk '
  /Found|URL:/ { print }
  { if ($1 ~ /^https?:\/\//) print }
' "$LOG" \
| grep -Eo 'https?://[^ ]+' \
| sed 's/[")'\''\r]$//' \
| sed 's/#.*$//' \
| sort -u > "$LINKS_TXT"

TOTAL=$(wc -l < "$LINKS_TXT" | tr -d '[:space:]')
echo "[✓] Links únicos descubiertos: $TOTAL"
echo "[→] Archivo: $LINKS_TXT"
echo "[→] Log: $LOG"

# ---------- robots info ----------
if (( RESPECT_ROBOTS == 1 )); then
  echo
  echo "[i] Posibles bloqueos por robots.txt:"
  grep -iE 'robots\.txt|disallow|blocked by robots|not retrieving|denied' "$LOG" || echo "(ninguno)"
fi