#!/bin/bash
#
# appcleanup — find and safely remove leftover files from software that is
# no longer needed on macOS, similar to what AppCleaner/AppZapper do.
#
# Final commands:
#   ./appcleanup "name"              remove that product's leftovers
#   ./appcleanup "name" --details    just show its references, don't remove
#   ./appcleanup --scan              scan and list ALL orphaned leftovers
#   ./appcleanup --scan --deep       scan, including unintelligible items too
#   ./appcleanup                     show usage
#
# Name-search mode removes by default (after a single confirmation prompt,
# unless -y is given) — that's the point of naming one product. --scan mode
# stays list-only by default; pass --remove to it explicitly to clean up
# what it finds.
#
# --scan first lists every application actually installed (in /Applications
# and ~/Applications, by name and CFBundleIdentifier), then scans the usual
# leftover locations (Application Support, Caches, Preferences, Containers,
# LaunchAgents, Application Scripts, plus stray items directly under
# ~/Library and /Library) and installer package receipts for anything that
# does NOT match any currently installed application — i.e. remnants of
# software that was removed without cleaning up after itself. Results are
# grouped by detected application (merging obvious name variants, e.g.
# "Familycircle"/"Familycircled", keeping whichever accounts for more
# space), shown as a one-line-per-app table by default, or with
# --scan --details as a full Location/Path breakdown, largest first.
#
# Items whose name is not human-readable (e.g. a bare UUID such as
# "B6C2DCC2-96A8-40E7-AED4-F8C3739A3A11") are hidden by default. Add --deep
# to a scan (--scan --deep) to include them too.
#
# By default nothing is ever permanently deleted with rm: matches are moved
# to Trash (user-level items) or a recoverable backup folder under
# /private/tmp (system-level items). Pass --force to skip Trash/backup
# entirely and permanently delete instead — this cannot be undone.
#
# Options:
#   -r, --remove       Move matches to Trash/backup (--scan mode; name-search
#                       mode already removes by default)
#   -y, --yes          Do not ask for confirmation before removing
#   --include-app      Also match the .app bundle itself in /Applications
#                       (name-search mode only; ignored with --scan)
#   --deep             Also include unintelligible (e.g. UUID-named) items
#                       (--scan mode only)
#   --details          Name-search mode: show references without removing.
#                       --scan mode: show the full path breakdown instead
#                       of the one-line-per-app summary.
#   -h, --help         Show this help
#
# Examples:
#   ./appcleanup Skype
#   ./appcleanup Skype --details
#   ./appcleanup Skype com.skype.skype --details
#   ./appcleanup --scan
#   ./appcleanup --scan --details
#   ./appcleanup --scan --deep
#   ./appcleanup --scan --remove
#
# Notes:
#   - This is a heuristic, name-based match, like AppCleaner itself. Always
#     review with --details before trusting a removal.
#   - Removing system-level items (under /Library, LaunchDaemons, or
#     installer package receipts) requires sudo; you'll be prompted for
#     your password only if such items are actually found.
#   - Anything named com.apple.* is skipped in --scan mode, to avoid
#     touching macOS's own files.

set -u

SCRIPT_NAME=$(basename "$0")
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
SYSTEM_BACKUP_DIR="/private/tmp/appcleanup-backup/${TIMESTAMP}"
LOGFILE="${LOGFILE:-$HOME/Library/Logs/appcleanup.log}"

REMOVE=0
ASSUME_YES=0
INCLUDE_APP=0
SCAN=0
DEEP=0
DETAILS=0
FORCE=0
NAME=""
BUNDLE_ID=""

log() {
	echo "$*" >> "$LOGFILE"
}

usage() {
	cat <<EOF
Usage:
  $SCRIPT_NAME "name"              remove that product's leftovers
  $SCRIPT_NAME "name" --details    just show its references, don't remove
  $SCRIPT_NAME --scan              scan and list ALL orphaned leftovers
  $SCRIPT_NAME --scan --deep       scan, including unintelligible items too
  $SCRIPT_NAME                     show this usage

Finds leftover files on this Mac from software that is no longer needed,
similar to AppCleaner. Naming a product removes its leftovers (after
confirming); --scan only lists, unless you also pass --remove to it.

Options:
  -r, --remove       Move matches to Trash/backup (--scan mode)
  -y, --yes          Skip the confirmation prompt before removing
  --include-app      Also match the .app bundle itself in /Applications
                      (name-search mode only)
  --deep             Also include unintelligible (e.g. UUID-named) items
                      (--scan mode only)
  --details          Name-search mode: show references, don't remove.
                      --scan mode: full path breakdown instead of summary.
  --force            Permanently delete instead of moving to Trash/backup —
                      no copy is kept anywhere, this cannot be undone.
  -h, --help         Show this help

Examples:
  $SCRIPT_NAME Skype
  $SCRIPT_NAME Skype --details
  $SCRIPT_NAME Skype com.skype.skype --details
  $SCRIPT_NAME Skype --force
  $SCRIPT_NAME --scan
  $SCRIPT_NAME --scan --details
  $SCRIPT_NAME --scan --deep
  $SCRIPT_NAME --scan --remove
EOF
}

# ---- argument parsing ----------------------------------------------------
while [ $# -gt 0 ]; do
	case "$1" in
		-h|--help)
			usage
			exit 0
			;;
		-r|--remove)
			REMOVE=1
			shift
			;;
		-y|--yes)
			ASSUME_YES=1
			shift
			;;
		--include-app)
			INCLUDE_APP=1
			shift
			;;
		--scan)
			SCAN=1
			shift
			;;
		--deep)
			DEEP=1
			shift
			;;
		--details)
			DETAILS=1
			shift
			;;
		--force)
			FORCE=1
			shift
			;;
		-*)
			echo "Unknown option: $1" >&2
			usage
			exit 1
			;;
		*)
			if [ -z "$NAME" ]; then
				NAME="$1"
			elif [ -z "$BUNDLE_ID" ]; then
				BUNDLE_ID="$1"
			else
				echo "Unexpected argument: $1" >&2
				exit 1
			fi
			shift
			;;
	esac
done

if [ "$SCAN" -eq 0 ] && [ -z "$NAME" ]; then
	usage
	exit 1
fi

if [ "$SCAN" -eq 0 ] && [ ${#NAME} -lt 3 ]; then
	echo "Error: please provide a search term of at least 3 characters, to avoid overly broad matches." >&2
	exit 1
fi

# Name-search mode removes by default (after the usual confirmation, unless
# -y is given) — that's the whole point of naming one product. Pass
# --details to just inspect it without removing anything. --scan mode stays
# list-only by default regardless; pass --remove there explicitly.
if [ "$SCAN" -eq 0 ]; then
	if [ "$DETAILS" -eq 1 ]; then
		REMOVE=0
	else
		REMOVE=1
	fi
fi

mkdir -p "$(dirname "$LOGFILE")"

log ""
if [ "$SCAN" -eq 1 ]; then
	log "=== appcleanup scan run at $(date) — deep=$DEEP remove=$REMOVE ==="
else
	log "=== appcleanup run at $(date) — name='$NAME' bundle-id='${BUNDLE_ID:-<none>}' remove=$REMOVE ==="
fi

# ---- locations to search (arrays, so entries with spaces are safe) -------
USER_DIRS=(
	"$HOME/Library/Application Support"
	"$HOME/Library/Caches"
	"$HOME/Library/Preferences"
	"$HOME/Library/Preferences/ByHost"
	"$HOME/Library/Saved Application State"
	"$HOME/Library/Logs"
	"$HOME/Library/Containers"
	"$HOME/Library/Group Containers"
	"$HOME/Library/WebKit"
	"$HOME/Library/HTTPStorages"
	"$HOME/Library/Cookies"
	"$HOME/Library/LaunchAgents"
	"$HOME/Library/Application Scripts"
)

# System-level locations; removing anything found here requires sudo.
SYSTEM_DIRS=(
	"/Library/Application Support"
	"/Library/Preferences"
	"/Library/Caches"
	"/Library/LaunchAgents"
	"/Library/LaunchDaemons"
)

# Names to ignore when scanning ~/Library or /Library themselves (their
# child folders are already covered above, or are stock macOS folders that
# are never leftovers from third-party software).
LIBRARY_SKIP_NAMES=(
	"Application Support" "Caches" "Preferences" "Saved Application State"
	"Logs" "Containers" "Group Containers" "WebKit" "HTTPStorages" "Cookies"
	"LaunchAgents" "LaunchDaemons" "Application Scripts" "Keychains" "Fonts"
	"ColorSync" "Mail" "Messages" "Calendars" "Reminders"
	"Autosave Information" "Assistant" "Audio" "CloudStorage"
	"Mobile Documents" "PreferencePanes" "Screen Savers" "Services"
	"Spelling" "Sounds" "Internet Plug-Ins" "Input Methods"
	"Keyboard Layouts" "Frameworks" "Developer" "Automator" "Safari"
	"Metadata" "Spotlight" "Accounts" "Icons" "Photos"
)

is_library_skip_name() {
	name="$1"
	for skip in "${LIBRARY_SKIP_NAMES[@]}"; do
		[ "$name" = "$skip" ] && return 0
	done
	return 1
}

# Identifiers that must never be reported or touched, regardless of what
# they look like or whether they seem "installed". Matched as a
# case-insensitive substring of the (already lowercased) candidate name.
# UBF8T346G9 = Microsoft's Apple Developer Team ID, used in Group
# Containers/Application Scripts/etc. for Outlook and the rest of Office.
FORBIDDEN_PATTERNS=(
	"ubf8t346g9"
)

# $1 = lowercase candidate identifier.
is_forbidden() {
	candidate="$1"
	for pattern in "${FORBIDDEN_PATTERNS[@]}"; do
		case "$candidate" in
			*"$pattern"*) return 0 ;;
		esac
	done
	return 1
}

MATCHES_FILE=$(mktemp "${TMPDIR:-/tmp}/appcleanup_matches.XXXXXX")
PKG_IDS_FILE=$(mktemp "${TMPDIR:-/tmp}/appcleanup_pkgs.XXXXXX")
GROUP_INFO_FILE=$(mktemp "${TMPDIR:-/tmp}/appcleanup_groupinfo.XXXXXX")
trap 'rm -f "$MATCHES_FILE" "$PKG_IDS_FILE" "$GROUP_INFO_FILE"' EXIT

# Strips common leftover-file extensions to get a matchable token.
candidate_name() {
	base=$(basename "$1")
	base=${base%.plist}
	base=${base%.savedState}
	base=${base%.cache}
	base=${base%.log}
	base=${base%.binarycookies}
	echo "$base" | tr '[:upper:]' '[:lower:]'
}

# Derives a human-friendly "detected application" label to group results
# by, e.g. "com.blackmagic-design.BlackmagicRawSpeed" -> "Blackmagic-design".
group_key() {
	cand=$(candidate_name "$1")
	case "$cand" in
		*.*.*)
			# reverse-DNS id (tld.vendor.product...) -> group by vendor
			vendor=$(echo "$cand" | cut -d '.' -f2)
			;;
		*.*)
			vendor=$(echo "$cand" | cut -d '.' -f1)
			;;
		*)
			vendor="$cand"
			;;
	esac
	first=$(printf '%s' "$vendor" | cut -c1 | tr '[:lower:]' '[:upper:]')
	rest=$(printf '%s' "$vendor" | cut -c2-)
	printf '%s%s' "$first" "$rest"
}

# True if the candidate looks like an opaque identifier (currently: a UUID)
# rather than something a human would recognize as an app/vendor name.
looks_unintelligible() {
	echo "$1" | grep -Eq '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
}

# Formats a size in KB as a short human-readable string (no bc/numfmt needed).
format_size_kb() {
	awk -v kb="$1" 'BEGIN {
		if (kb >= 1048576) printf "%.1fGB", kb/1048576;
		else if (kb >= 1024) printf "%.1fMB", kb/1024;
		else printf "%dKB", kb;
	}'
}

# ===========================================================================
# Mode 1: search for one specific product by name / bundle id
# ===========================================================================
name_search_mode() {
	if pgrep -qi -f "$NAME" 2>/dev/null; then
		echo "Warning: a running process matching '$NAME' was found. Consider quitting the app before removing its files."
		echo ""
	fi

	search_dir() {
		dir="$1"
		[ -d "$dir" ] || return 0
		find "$dir" -maxdepth 2 -iname "*${NAME}*" 2>/dev/null
		if [ -n "$BUNDLE_ID" ]; then
			find "$dir" -maxdepth 2 -iname "*${BUNDLE_ID}*" 2>/dev/null
		fi
	}

	echo "Searching user locations..."
	for d in "${USER_DIRS[@]}"; do
		search_dir "$d" >> "$MATCHES_FILE"
	done

	echo "Searching system locations..."
	for d in "${SYSTEM_DIRS[@]}"; do
		search_dir "$d" >> "$MATCHES_FILE"
	done

	if [ "$INCLUDE_APP" -eq 1 ]; then
		find /Applications -maxdepth 1 -iname "*${NAME}*.app" 2>/dev/null >> "$MATCHES_FILE"
	fi

	sort -u -o "$MATCHES_FILE" "$MATCHES_FILE"

	echo "Searching installer package receipts..."
	NAME_LC=$(echo "$NAME" | tr '[:upper:]' '[:lower:]')
	pkgutil --pkgs 2>/dev/null | grep -i "$NAME_LC" > "$PKG_IDS_FILE"
	if [ -n "$BUNDLE_ID" ]; then
		pkgutil --pkgs 2>/dev/null | grep -i "$BUNDLE_ID" >> "$PKG_IDS_FILE"
	fi
	sort -u -o "$PKG_IDS_FILE" "$PKG_IDS_FILE"

	REPORT_HEADER="matching '$NAME'${BUNDLE_ID:+ / '$BUNDLE_ID'}"
	EMPTY_MESSAGE="Nothing found. The system looks clean for '$NAME'."
}

# ===========================================================================
# Mode 2: --scan — cross-reference leftovers against what is actually
# installed right now, and report only the orphans, grouped by application.
# ===========================================================================
INSTALLED_FILE=""

list_installed_apps() {
	for app_root in /Applications "$HOME/Applications"; do
		[ -d "$app_root" ] || continue
		find "$app_root" -maxdepth 2 -iname "*.app" 2>/dev/null
	done | while IFS= read -r app; do
		name=$(basename "$app" .app)
		echo "$name" | tr '[:upper:]' '[:lower:]' >> "$INSTALLED_FILE"
		bid=$(defaults read "$app/Contents/Info" CFBundleIdentifier 2>/dev/null)
		if [ -n "$bid" ]; then
			echo "$bid" | tr '[:upper:]' '[:lower:]' >> "$INSTALLED_FILE"
		fi
	done
}

# $1 = lowercase candidate identifier. Returns success if it looks like it
# belongs to a currently installed application.
is_installed() {
	candidate="$1"
	[ -n "$candidate" ] || return 0
	grep -qiF "$candidate" "$INSTALLED_FILE" 2>/dev/null && return 0
	while IFS= read -r known <&9; do
		[ -n "$known" ] || continue
		case "$candidate" in
			*"$known"*) return 0 ;;
		esac
	done 9< "$INSTALLED_FILE"
	return 1
}

# Scans one directory's direct children and records orphaned items.
# $1 = directory to scan, $2 = 1 if this is a bare ~/Library or /Library
# root (apply LIBRARY_SKIP_NAMES), 0 otherwise.
scan_one_dir() {
	dir="$1"
	is_root="$2"
	[ -d "$dir" ] || return 0
	category=$(basename "$dir")
	find "$dir" -maxdepth 1 -mindepth 1 2>/dev/null | while IFS= read -r item; do
		[ "$item" = "$LOGFILE" ] && continue
		base=$(basename "$item")
		if [ "$is_root" -eq 1 ] && is_library_skip_name "$base"; then
			continue
		fi
		cand=$(candidate_name "$item")
		case "$cand" in
			com.apple.*|appcleanup|"") continue ;;
		esac
		if is_forbidden "$cand"; then
			continue
		fi
		if [ "$DEEP" -eq 0 ] && looks_unintelligible "$cand"; then
			continue
		fi
		if ! is_installed "$cand"; then
			echo "$item" >> "$MATCHES_FILE"
			key=$(group_key "$item")
			printf '%s\t%s\t%s\n' "$key" "$category" "$item" >> "$GROUP_INFO_FILE"
		fi
	done
}

scan_mode() {
	echo "Listing installed applications..."
	INSTALLED_FILE=$(mktemp "${TMPDIR:-/tmp}/appcleanup_installed.XXXXXX")
	list_installed_apps
	sort -u -o "$INSTALLED_FILE" "$INSTALLED_FILE"
	installed_count=$(grep -c . "$INSTALLED_FILE" 2>/dev/null)
	echo "Found $installed_count installed application identifier(s) (names + bundle ids)."
	echo ""

	echo "Scanning for leftovers with no matching installed application..."
	for d in "${USER_DIRS[@]}"; do
		scan_one_dir "$d" 0
	done
	scan_one_dir "$HOME/Library" 1
	for d in "${SYSTEM_DIRS[@]}"; do
		scan_one_dir "$d" 0
	done
	scan_one_dir "/Library" 1

	sort -u -o "$MATCHES_FILE" "$MATCHES_FILE"
	sort -u -o "$GROUP_INFO_FILE" "$GROUP_INFO_FILE"

	echo "Cross-checking installer package receipts..."
	pkgutil --pkgs 2>/dev/null | while IFS= read -r pkgid; do
		cand=$(echo "$pkgid" | tr '[:upper:]' '[:lower:]')
		is_forbidden "$cand" && continue
		if ! is_installed "$cand"; then
			echo "$pkgid" >> "$PKG_IDS_FILE"
		fi
	done
	sort -u -o "$PKG_IDS_FILE" "$PKG_IDS_FILE"

	rm -f "$INSTALLED_FILE"

	REPORT_HEADER="with no matching installed application"
	EMPTY_MESSAGE="Nothing found. No orphaned leftovers detected."
}

# ---- run the selected mode -------------------------------------------------
if [ "$SCAN" -eq 1 ]; then
	scan_mode
else
	name_search_mode
fi

# ---- report ---------------------------------------------------------------
FILE_COUNT=$(grep -c . "$MATCHES_FILE" 2>/dev/null)
PKG_COUNT=$(grep -c . "$PKG_IDS_FILE" 2>/dev/null)

echo ""
echo "-------------------------------------------------------------"
echo "Found $FILE_COUNT file(s)/folder(s) and $PKG_COUNT package receipt(s)"
echo "$REPORT_HEADER:"
echo "-------------------------------------------------------------"
echo ""

if [ "$FILE_COUNT" -gt 0 ] && [ "$SCAN" -eq 1 ]; then
	SIZED_FILE=$(mktemp "${TMPDIR:-/tmp}/appcleanup_sized.XXXXXX")
	while IFS=$'\t' read -r key category path; do
		[ -n "$path" ] || continue
		kb=$(du -sk "$path" 2>/dev/null | awk '{print $1}')
		printf '%s\t%s\t%s\t%s\n' "$key" "$category" "$path" "${kb:-0}" >> "$SIZED_FILE"
	done < "$GROUP_INFO_FILE"

	# Merge application names that likely refer to the same product (e.g.
	# "Familycircle"/"Familycircled", "Forticlien"/"Fortinet"), based on
	# string similarity. The variant with the most space involved wins the
	# name for the merged group. Tune with MERGE_SIMILARITY (0-1, higher =
	# stricter, default 0.55).
	MERGE_SIMILARITY="${MERGE_SIMILARITY:-0.55}"
	DISTINCT_FILE=$(mktemp "${TMPDIR:-/tmp}/appcleanup_distinct.XXXXXX")
	awk -F'\t' '{ total[$1] += $4 } END { for (k in total) print k "\t" total[k] }' "$SIZED_FILE" > "$DISTINCT_FILE"

	MAPPING_FILE=$(mktemp "${TMPDIR:-/tmp}/appcleanup_mapping.XXXXXX")
	awk -F'\t' -v threshold="$MERGE_SIMILARITY" '
		function levenshtein(s1, s2,    l1, l2, i, j, c1, c2, cost, a, b, c, m, prev, cur) {
			l1 = length(s1); l2 = length(s2)
			for (j = 0; j <= l2; j++) prev[j] = j
			for (i = 1; i <= l1; i++) {
				cur[0] = i
				c1 = substr(s1, i, 1)
				for (j = 1; j <= l2; j++) {
					c2 = substr(s2, j, 1)
					cost = (c1 == c2) ? 0 : 1
					a = prev[j] + 1
					b = cur[j-1] + 1
					c = prev[j-1] + cost
					m = a
					if (b < m) m = b
					if (c < m) m = c
					cur[j] = m
				}
				for (j = 0; j <= l2; j++) prev[j] = cur[j]
			}
			return prev[l2]
		}
		{
			n++
			keys[n] = $1
			sizes[n] = $2
		}
		END {
			nclusters = 0
			for (i = 1; i <= n; i++) cluster_of[i] = 0
			for (i = 1; i <= n; i++) {
				if (cluster_of[i] != 0) continue
				nclusters++
				cluster_of[i] = nclusters
				li = tolower(keys[i])
				for (j = i + 1; j <= n; j++) {
					if (cluster_of[j] != 0) continue
					lj = tolower(keys[j])
					maxlen = length(li)
					if (length(lj) > maxlen) maxlen = length(lj)
					if (maxlen == 0) continue
					dist = levenshtein(li, lj)
					sim = 1 - (dist / maxlen)
					if (sim >= threshold) cluster_of[j] = nclusters
				}
			}
			for (i = 1; i <= n; i++) {
				c = cluster_of[i]
				if (!(c in best_size) || sizes[i] + 0 > best_size[c] + 0) {
					best_size[c] = sizes[i]
					best_name[c] = keys[i]
				}
			}
			for (i = 1; i <= n; i++) {
				print keys[i] "\t" best_name[cluster_of[i]]
			}
		}
	' "$DISTINCT_FILE" > "$MAPPING_FILE"

	RECODED_FILE=$(mktemp "${TMPDIR:-/tmp}/appcleanup_recoded.XXXXXX")
	awk -F'\t' -v OFS='\t' '
		NR==FNR { map[$1] = $2; next }
		{ if ($1 in map) $1 = map[$1]; print }
	' "$MAPPING_FILE" "$SIZED_FILE" > "$RECODED_FILE"
	mv "$RECODED_FILE" "$SIZED_FILE"
	rm -f "$DISTINCT_FILE" "$MAPPING_FILE"

	if [ "$DETAILS" -eq 1 ]; then
		# Table view: Application (total size) header, then a Location/Path
		# table underneath, columns aligned. Applications are ordered by
		# total size, largest first.
		TOTALS_FILE=$(mktemp "${TMPDIR:-/tmp}/appcleanup_totals.XXXXXX")
		awk -F'\t' '{ total[$1] += $4 } END { for (k in total) print k "\t" total[k] }' "$SIZED_FILE" > "$TOTALS_FILE"

		JOINED_FILE=$(mktemp "${TMPDIR:-/tmp}/appcleanup_joined.XXXXXX")
		awk -F'\t' -v OFS='\t' '
			NR==FNR { total[$1] = $2; next }
			{ print (total[$1] ? total[$1] : 0), $1, $2, $3, $4 }
		' "$TOTALS_FILE" "$SIZED_FILE" > "$JOINED_FILE"
		sort -t "$(printf '\t')" -k1,1nr -k2,2f -k3,3f -o "$JOINED_FILE" "$JOINED_FILE"

		prev_key=""
		while IFS=$'\t' read -r total_kb key category path kb; do
			[ -n "$path" ] || continue
			if [ "$key" != "$prev_key" ]; then
				[ -n "$prev_key" ] && echo ""
				echo "$key ($(format_size_kb "${total_kb:-0}"))"
				printf "    %-24s %s\n" "LOCATION" "PATH"
				printf "    %-24s %s\n" "------------------------" "----"
				prev_key="$key"
			fi
			printf "    %-24s %s\n" "$category" "$path"
		done < "$JOINED_FILE"
		rm -f "$TOTALS_FILE" "$JOINED_FILE"
	else
		# Compact default view: one row per detected application, as a
		# table, ordered by total size, largest first.
		SUMMARY_FILE=$(mktemp "${TMPDIR:-/tmp}/appcleanup_summary.XXXXXX")
		awk -F'\t' '{ count[$1]++; total[$1] += $4 } END { for (k in count) print k "\t" count[k] "\t" total[k] }' "$SIZED_FILE" > "$SUMMARY_FILE"
		sort -t "$(printf '\t')" -k3,3nr -o "$SUMMARY_FILE" "$SUMMARY_FILE"

		printf "%-32s %11s %10s\n" "APPLICATION" "REFERENCES" "SIZE"
		printf "%-32s %11s %10s\n" "--------------------------------" "-----------" "----------"
		while IFS=$'\t' read -r key count kb; do
			[ -n "$key" ] || continue
			printf "%-32s %11s %10s\n" "$key" "$count" "$(format_size_kb "${kb:-0}")"
		done < "$SUMMARY_FILE"
		rm -f "$SUMMARY_FILE"

		echo ""
		echo "Re-run with --scan --details to see the individual paths for each application."
	fi
	rm -f "$SIZED_FILE"
elif [ "$FILE_COUNT" -gt 0 ]; then
	# Simple grouped view (name-search mode): Application -> path(s), with size
	GROUPED_FILE=$(mktemp "${TMPDIR:-/tmp}/appcleanup_grouped.XXXXXX")
	while IFS= read -r path; do
		[ -n "$path" ] || continue
		key=$(group_key "$path")
		printf '%s\t%s\n' "$key" "$path" >> "$GROUPED_FILE"
	done < "$MATCHES_FILE"
	sort -f -t "$(printf '\t')" -k1,1 -o "$GROUPED_FILE" "$GROUPED_FILE"

	prev_key=""
	while IFS=$'\t' read -r key path; do
		[ -n "$path" ] || continue
		if [ "$key" != "$prev_key" ]; then
			[ -n "$prev_key" ] && echo ""
			echo "$key"
			prev_key="$key"
		fi
		size=$(du -sh "$path" 2>/dev/null | awk '{print $1}')
		printf "    %-8s %s\n" "${size:-?}" "$path"
	done < "$GROUPED_FILE"
	rm -f "$GROUPED_FILE"
fi

if [ "$PKG_COUNT" -gt 0 ]; then
	echo ""
	echo "Package receipts:"
	while IFS= read -r pkgid; do
		[ -n "$pkgid" ] || continue
		echo "  $pkgid"
	done < "$PKG_IDS_FILE"
fi

log "Found $FILE_COUNT file(s) and $PKG_COUNT receipt(s) ($REPORT_HEADER)"

if [ "$FILE_COUNT" -eq 0 ] && [ "$PKG_COUNT" -eq 0 ]; then
	echo ""
	echo "$EMPTY_MESSAGE"
	exit 0
fi

if [ "$REMOVE" -eq 0 ]; then
	echo ""
	if [ "$SCAN" -eq 1 ]; then
		echo "This was a dry run — nothing was removed. Re-run with --remove to clean these up."
	else
		echo "Nothing was removed (--details). Re-run without --details to remove these."
	fi
	exit 0
fi

# ---- confirmation ----------------------------------------------------------
if [ "$ASSUME_YES" -eq 0 ]; then
	echo ""
	echo "-------------------------------------------------------------"
	echo "DISCLAIMER: this is a heuristic, name-based match — it can be"
	echo "wrong. Review the list above before continuing."
	if [ "$FORCE" -eq 1 ]; then
		echo "--force is set: items will be PERMANENTLY DELETED, with no"
		echo "Trash, no backup, and no way to undo this."
	else
		echo "User-level items will be moved to ~/.Trash; system-level items"
		echo "will be moved to a backup folder under /private/tmp (via"
		echo "sudo). Nothing is permanently deleted."
	fi
	echo "You are responsible for verifying the list is correct before"
	echo "proceeding."
	echo "-------------------------------------------------------------"
	printf "Proceed with removal? [y/n]: "
	read -r confirm
	case "$confirm" in
		y|Y|yes|YES) ;;
		*)
			echo "Aborted, nothing removed."
			exit 0
			;;
	esac
fi

# ---- removal ----------------------------------------------------------------
# User-level items are moved to ~/.Trash (recoverable, no sudo needed).
# System-level items are moved to $SYSTEM_BACKUP_DIR via sudo (recoverable,
# never permanently deleted). With --force, items are permanently deleted
# with rm instead — no Trash, no backup, no way back.
trash_item() {
	item="$1"

	if [ "$FORCE" -eq 1 ]; then
		if [ "${item#$HOME}" != "$item" ]; then
			if rm -rf -- "$item" 2>/dev/null; then
				echo "  Deleted: $item"
				log "Permanently deleted: $item"
			else
				echo "  Failed to delete: $item"
				log "FAILED to permanently delete: $item"
			fi
		else
			if sudo rm -rf -- "$item" 2>/dev/null; then
				echo "  Deleted: $item"
				log "Permanently deleted: $item"
			else
				echo "  Failed to delete (needs sudo): $item"
				log "FAILED to permanently delete: $item"
			fi
		fi
		return
	fi

	if [ "${item#$HOME}" != "$item" ]; then
		mkdir -p "$HOME/.Trash"
		base=$(basename "$item")
		dest="$HOME/.Trash/$base"
		if [ -e "$dest" ]; then
			dest="$HOME/.Trash/${base}.${TIMESTAMP}"
		fi
		if mv "$item" "$dest" 2>/dev/null; then
			echo "  Trashed: $item -> $dest"
			log "Trashed: $item -> $dest"
		else
			echo "  Failed to move: $item"
			log "FAILED to trash: $item"
		fi
	else
		dest="$SYSTEM_BACKUP_DIR$item"
		mkdir -p "$(dirname "$dest")"
		if sudo mv "$item" "$dest" 2>/dev/null; then
			echo "  Backed up: $item -> $dest"
			log "Backed up: $item -> $dest"
		else
			echo "  Failed to move (needs sudo): $item"
			log "FAILED to back up: $item"
		fi
	fi
}

echo ""
echo "Removing files/folders..."
while IFS= read -r path; do
	[ -n "$path" ] || continue
	trash_item "$path"
done < "$MATCHES_FILE"

if [ "$PKG_COUNT" -gt 0 ]; then
	echo ""
	echo "Forgetting package receipts (requires sudo)..."
	while IFS= read -r pkgid; do
		[ -n "$pkgid" ] || continue
		if sudo pkgutil --forget "$pkgid" 2>/dev/null; then
			echo "  Forgot: $pkgid"
			log "Forgot receipt: $pkgid"
		else
			echo "  Failed to forget: $pkgid"
			log "FAILED to forget receipt: $pkgid"
		fi
	done < "$PKG_IDS_FILE"
fi

echo ""
echo "Done."
if [ "$FORCE" -eq 1 ]; then
	echo "Items were permanently deleted (--force) — no Trash, no backup."
else
	echo "User-level items were moved to: $HOME/.Trash"
	echo "System-level items (if any) were moved to: $SYSTEM_BACKUP_DIR"
fi
echo "Log: $LOGFILE"
