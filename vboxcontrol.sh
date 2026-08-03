#!/bin/sh

check_dependencies()
{
	for cmd in VBoxManage VBoxHeadless; do
		if ! command -v "$cmd" >/dev/null 2>&1; then
			echo "Error: required command not found: $cmd"
			exit 1
		fi
	done
}

menu()
{
	clear
	echo "====== VBOXCONTROL ======"
	echo "1. List VMs."
	echo "2. List running VMs."
	echo "3. Start a VM."
	echo "4. Stop a VM."
	echo "5. Start ALL VMs."
	echo "6. Stop ALL VMs."
	echo "0. Exit."
	echo "========================="
	echo -n "Option: "
	read -r option || exit 0
}

start_vms()
{
	echo "Starting VMs..."
	for i in `VBoxManage list vms | sed -n 's/^"\(.*\)" {.*}$/\1/p'`; do
		echo "Running VBoxHeadless -startvm \"$i\"..."
		VBoxHeadless -startvm "$i" &
		sleep 5
	done
	echo -n "ALL VMs have been started! Press Enter to continue..."
        read -r enter
}

stop_vms()
{
	echo "Stopping VMs..."
	for i in `VBoxManage list runningvms | sed -n 's/^"\(.*\)" {.*}$/\1/p'`; do
                VBoxManage controlvm "$i" poweroff &
		sleep 5
        done
        echo -n "ALL VMs have been stopped! Press Enter to continue..."
        read -r enter
}

start_vm()
{
	echo ""
	echo -n "Enter the name of the VM you want to start: "
	read -r vm
	if [ -z "$vm" ]; then
		echo "No VM name entered."
		return
	fi
	VBoxHeadless -startvm "$vm" >/dev/null 2>&1 &
	echo ""
	echo -n "VM $vm started. Press Enter to continue..."
	read -r enter
}

stop_vm()
{
	echo ""
	echo -n "Enter the name of the VM you want to stop: "
	read -r vm
	if [ -z "$vm" ]; then
		echo "No VM name entered."
		return
	fi
	VBoxManage controlvm "$vm" poweroff || echo "Error: could not stop VM $vm."
	echo ""
	echo -n "VM $vm stopped. Press Enter to continue..."
	read -r enter
}

list_vms()
{
	echo ""
	echo "List of virtual machines:"
	echo "----------------------------"
	VBoxManage list vms | sed -n 's/^"\(.*\)" {.*}$/\1/p'
}

check_dependencies

case $1 in
	start)
		start_vms
	;;
	stop)
		stop_vms
	;;
	restart)
		stop_vms
		start_vms
	;;
	control)
		while [ 1 ]; do
			menu
			case $option in
				1)
					echo ""
					VBoxManage list vms || echo "Error: could not query VirtualBox."
					echo ""
					echo -n "Press Enter to continue..."
                                        read -r enter
				;;
				2)
					echo ""
					VBoxManage list runningvms || echo "Error: could not query VirtualBox."
					echo ""
					echo -n "Press Enter to continue..."
					read -r enter
				;;
				3)
					list_vms
					start_vm
				;;
				4)
					list_vms
					stop_vm
				;;
				5)
					start_vms
				;;
				6)
					stop_vms
				;;
				0)
					clear
					exit
				;;
				*)
					echo "Please choose an option!"
					echo ""
					sleep 1
				;;
			esac
		done
	;;
	*)
		echo ""
		echo "Usage: $0 (start|stop|restart|control)"
		echo ""
	;;
esac
