#!/bin/bash
# Log file for this backup run. Override with: LOGFILE=/path/to/log ./vboxbackup.sh
LOGFILE="${LOGFILE:-/the/path/for/log/file}"

# Base folder for backups; each run creates a dated VMs/ subfolder inside it.
# Override with: BACKUP_BASE=/path/to/backups ./vboxbackup.sh
BACKUP_BASE="${BACKUP_BASE:-/the/path/for/backup/folder}"

# Only back up VMs whose name matches this extended-regex pattern (grep -E).
# Empty (default) means back up every registered VM.
# Override with: VM_FILTER="^prod-" ./vboxbackup.sh
VM_FILTER="${VM_FILTER:-}"

# ACPI shutdown retry settings.
MAX_RETRIES="${MAX_RETRIES:-3}"
SLEEP_TIME="${SLEEP_TIME:-15}"

# Command to run once the backup process finishes, e.g. a monitoring ping.
# Override with: MONITOR_ACTION="/usr/bin/php /your/script/in/php" ./vboxbackup.sh
MONITOR_ACTION="${MONITOR_ACTION:-/usr/bin/php /your/script/in/php}"

vmIsRunning=0
vmRunningBeforeBackup=0
failedCount=0
vmList=""
declare -a vmNamesArray

backupFolder="$BACKUP_BASE/$(date +"%d.%m.%Y")/VMs/"

#Logging method. Writes the given string out into logfile.
#@param the string to log
log(){
	echo $* >>$LOGFILE
}

#Checks that the VirtualBox command-line tools this script depends on are available
checkDependencies(){
	for cmd in VBoxManage VBoxHeadless; do
		if ! command -v "$cmd" >/dev/null 2>&1; then
			log "FATAL: required command not found: $cmd"
			exit 1
		fi
	done
}

#Checks if the given VM is running
#@param the name of the vm
isRunning(){
	if [ `VBoxManage list runningvms|grep \"${1}\"|wc -l` -eq 0 ] ;
		then log "Not Running VM ${1}"
			vmIsRunning=0
		else log "Is running VM ${1}"
			vmIsRunning=1
	fi
}

#Lists all vm to backup them
findVMs(){
	log "Listing VMs"
	vmNames=`VBoxManage list vms | sed -n 's/^"\(.*\)" {.*}$/\1/p'`
	if [ -n "$VM_FILTER" ]; then
		vmNames=`echo "$vmNames" | grep -E "$VM_FILTER"`
	fi
	vmNamesArray=( $vmNames )
	log "VM Count: ${#vmNamesArray[@]}"
	log "VMs found: ${vmNamesArray[@]}"
}

#Method handling the shutdown of the given vm.
#Waiting for shutting down via ACPI. If timeout the vm will be controlled by poweroff.
#@param the name of the vm
shutDownVM(){
	log "Shutting down VM $1"
	VBoxManage controlvm $1 acpipowerbutton
	I=1
	while [ $I -le $MAX_RETRIES ] ;
	do
		log $I
		I=`expr $I + 1`
		log "The vm is still running"
		sleep $SLEEP_TIME
		isRunning $1
		if [ $vmIsRunning -eq 0 ] ;
			then break
		fi
	done
	#@FIXME Temporarly set always true, because the DEV-VM could not be exported somethimes. It is locked yet.
	#if [ $vmIsRunning -eq 1 ] ;
	if [ 1 -eq 1 ]
		then VBoxManage controlvm $1 poweroff
			sleep $SLEEP_TIME
			isRunning $1
			log "Had to poweroff the vm, the vm is runing=$vmIsRunning"
	fi
	#wait one more time for unlocking safe
	sleep $SLEEP_TIME
}

#Exports the halted vm to the backupfolder as ovf file and vmdk file.
#@param the name of the vm
backupVM() {
	log "Begin backuppping the VM $1"
	if VBoxManage export $1 -o $backupFolder$1.ovf >>$LOGFILE 2>&1; then
		log "Backuping of VM $1 finished"
	else
		log "ERROR: backup of VM $1 failed"
		failedCount=$((failedCount + 1))
	fi
}

#Starts the vm by pushing the power button.
#@param the name of the vm
startVM() {
	log "Starting VM $1"
	VBoxHeadless -startvm "$1" &>/dev/null &
	log "VM has been started"
}

#Controls the workflow for backup.
#First if vm is running it will be shutted down.
#Second the vm will be exported (backuped).
#Third the vm will be started again, if it was running before backupping
#@param the name of the vm
vmWorkflow(){
	log "Checking if the VM $1 is running"
	isRunning $1
	log "The VM $1 is running="$vmIsRunning

	if [ $vmIsRunning -eq 1 ] ;
		then shutDownVM $1
			vmRunningBeforeBackup=1
		else log "VM is not running $vmIsRunning"
			vmRunningBeforeBackup=0
	fi

	backupVM $1

	if [ $vmRunningBeforeBackup -eq 1 ] ;
		then log "Starting VM $1, because VM was also running before backup"
			startVM $1
		else log "Starting of VM $1 skipped, because VM was not running before backup"
	fi
}

#The main method.
#Here everything begins.
main(){
	findVMs

	#iterate over all VMs
	vmsCount=${#vmNamesArray[@]}
	for (( i=0;i<$vmsCount;i++)); do
		vmWorkflow ${vmNamesArray[${i}]}
	done
}

checkDependencies

log ""
log "START"
log "Starting Backup Process at `date`"

log "Creating directories for backup $backupFolder"
if ! mkdir -p $backupFolder; then
	log "FATAL: could not create backup folder $backupFolder"
	exit 1
fi
log "Backup Folders created"

main

log "Finished backup process at `date` - $failedCount failed VM(s)"
log "END"
log ""

#put here your script invocation for another action, like send email
if ! $MONITOR_ACTION >>$LOGFILE 2>&1; then
	log "Monitor action failed"
fi
