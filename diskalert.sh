#!/bin/bash
# Alert level, in percent used, at which the action below is triggered.
# Override at runtime with: ALERT=75 ./diskalert.sh
ALERT="${ALERT:-25}"

# Filesystem path to monitor. Override with: WATCH_PATH=/var ./diskalert.sh
WATCH_PATH="${WATCH_PATH:-/home}"

# Log file. Override with: LOGFILE=/var/log/diskalert.log ./diskalert.sh
LOGFILE="${LOGFILE:-logdisk.log}"

# Command to run when the alert threshold is reached.
# Override with: ALERT_ACTION="/usr/bin/php /your/script/in/php" ./diskalert.sh
ALERT_ACTION="${ALERT_ACTION:-/usr/bin/php /your/script/in/php}"

if ! df -H "$WATCH_PATH" >/dev/null 2>&1; then
	echo [`date +"%d.%m.%Y:%H.%M"`] Disk space check failed - path not found: $WATCH_PATH >> "$LOGFILE"
	exit 1
fi

df -H "$WATCH_PATH" | grep -vE '^Filesystem|tmpfs|cdrom' | awk '{ print $5 " " $6 }' | while read output;
do
	usep=$(echo $output | awk '{ print $1}' | cut -d'%' -f1 )
	partition=$(echo $output | awk '{ print $2 }' )

	case "$usep" in
		''|*[!0-9]*)
			echo [`date +"%d.%m.%Y:%H.%M"`] Disk space check skipped - could not parse usage from: $output >> "$LOGFILE"
			continue
			;;
	esac

	echo [`date +"%d.%m.%Y:%H.%M"`] Disk space check completed - $partition used $usep% >> "$LOGFILE"

	if [ $usep -ge $ALERT ]; then
		#put here your script invocation for another action, like send email
		if ! $ALERT_ACTION >> "$LOGFILE" 2>&1; then
			echo [`date +"%d.%m.%Y:%H.%M"`] Alert action failed for $partition \(${usep}%\) >> "$LOGFILE"
		fi
	fi
done
