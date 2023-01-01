#!/bin/bash

GOLEM_CORE=0.12.0

# Architecture ########################################################################################################

get_cpu_vendorid()
{
	cat /proc/cpuinfo | grep vendor_id | awk -F": " '{print $2}'  | head -1
}

# Packages ############################################################################################################

check_package()
{
	if [ "$(command -v $2)" == "" ]; then
		echo " $1"
	fi
}

check_packages_required()
{
	packages_to_install=""
	packages_to_install="$packages_to_install"$(check_package pciutils lspci)
	packages_to_install="$packages_to_install"$(check_package dialog dialog)
	if [ "$packages_to_install" != "" ]; then
		sudo apt-get update
		sudo apt-get install $packages_to_install
	fi
}

# Grub default cmdline ################################################################################################

get_grub_default_cmdline()
{
	cat /etc/default/grub | grep "^[^#]" | grep GRUB_CMDLINE_LINUX_DEFAULT | awk -F "GRUB_CMDLINE_LINUX_DEFAULT=" '{print $2}' | tr -d '"'
}

get_grub_default_cmdline_vfio()
{
	echo $(get_grub_default_cmdline) | awk -F "vfio-pci.ids=" '{print $2}' | awk -F " " '{print $1}'
}

set_grub_default_cmdline()
{
	sudo sed -i "s/^\GRUB_CMDLINE_LINUX_DEFAULT.*/GRUB_CMDLINE_LINUX_DEFAULT=\"$1\"/" /etc/default/grub
}

set_grub_default_cmdline_vfio()
{
	if [ "$(get_grub_default_cmdline_vfio)" == "" ]; then
		grub_default_cmdline=$(get_grub_default_cmdline)
		cmd_vfio="vfio-pci.ids="$1
		if [ "$grub_default_cmdline" == "" ]; then
			new_grub_default_cmdline="$cmd_vfio"
		else
			new_grub_default_cmdline="$grub_default_cmdline $cmd_vfio"
		fi
		set_grub_default_cmdline "$new_grub_default_cmdline"
		echo 1
	else
		grub_default_cmdline_vfio=$(get_grub_default_cmdline_vfio)
		if [ "$(echo $grub_default_cmdline_vfio | grep $1)" == "" ]; then
			new_grub_default_cmdline_vfio="$grub_default_cmdline_vfio,$1"
			sudo sed -i "s/$grub_default_cmdline_vfio/$new_grub_default_cmdline_vfio/" /etc/default/grub
			echo 1
		else
			dialog --stdout --title "Grub VFIO" --msgbox "\nGrub VFIO already configured for this device." 6 50
			clear
			echo 0
		fi
	fi
}

set_grub_pcies_aspm()
{
	if [ "$(cat /etc/default/grub | grep 'pcie_aspm=off')" == "" ]; then
		grub_default_cmdline=$(get_grub_default_cmdline)
		cmd_pcie_aspm="pcie_aspm=off"
		if [ "$grub_default_cmdline" == "" ]; then
			new_grub_default_cmdline="$cmd_pcie_aspm"
		else
			new_grub_default_cmdline="$grub_default_cmdline $cmd_pcie_aspm"
		fi
		set_grub_default_cmdline "$new_grub_default_cmdline"
		echo 1
	else
		echo 0
	fi
}

# IOMMU ###############################################################################################################

cmd_enable_iommu()
{
	cpu_vendorid=$(get_cpu_vendorid)
	if [ "$cpu_vendorid" == "GenuineIntel" ]; then
		echo "intel_iommu=on"
	elif [ "$cpu_vendorid" == "AuthenticAMD" ]; then
		echo "amd_iommu=on"
	fi
}

enable_iommu()
{
	grub_default_cmdline=$(get_grub_default_cmdline)
	if [ "$grub_default_cmdline" == "" ]; then
		new_grub_default_cmdline="$1"
	else
		new_grub_default_cmdline="$grub_default_cmdline $1"
	fi
	set_grub_default_cmdline "$new_grub_default_cmdline"
	sudo update-grub
}

get_iommu_groups()
{
	ls -v /sys/kernel/iommu_groups
}

test_iommu_enabled()
{
	count_iommu_groups=$(get_iommu_groups | wc -l)
	if [ $count_iommu_groups -gt 0 ]; then
		echo enabled
	else
		echo disabled
	fi
}

configure_iommu()
{
	if [ $(test_iommu_enabled) == "disabled" ]; then
		grub_enable_iommu=$(cmd_enable_iommu)
		if [ "$(echo $(get_grub_default_cmdline) | grep $grub_enable_iommu)" != "" ]; then
		    display_error "No IOMMU" "Enable IOMMU in BIOS/UEFI" 7 45
		else
			enable_iommu "$grub_enable_iommu"
			reboot "Reboot needed to enable IOMMU.\nRelaunch script after reboot to finish installation." 7 60
		fi
	fi
}

get_iommu_group_devices()
{
	ls /sys/kernel/iommu_groups/$iommu_group/devices
}

# PCI #################################################################################################################

get_pid_vid_from_slot()
{
	lspci -n -s $1 | awk -F" " '{print $3}'
}

get_pci_full_string_description_from_slot()
{
	lspci -s $1
}

get_pci_short_string_description_from_slot()
{
	get_pci_full_string_description_from_slot $1 | awk -F": " '{print $2}'
}

list_pci_devices_in_iommu_group()
{
	ret="IOMMU Group "$1
	ret="$ret\n##############"
	for device in $2; do
		ret="$ret\n$(get_pci_full_string_description_from_slot $device)"
	done;
	echo $ret
}

test_pci_slot_as_vga()
{
	lspci -d ::0300 -s $1
}

test_pci_slot_as_audio()
{
	lspci -d ::0403 -s $1
}

# vfio ################################################################################################################

enable_vfio_modules()
{
	ret=0
	if [ "$(cat /etc/modules | grep "^[^#]" | grep 'vfio')" == "" ]; then
		sudo sh -c "echo vfio >> /etc/modules"
		((ret+=1))
	fi
	if [ "$(cat /etc/modules | grep "^[^#]" | grep 'vfio_pci')" == "" ]; then
		sudo sh -c "echo vfio_pci >> /etc/modules"
		((ret+=1))
	fi
	if [ $ret -gt 0 ]; then
		sudo update-initramfs -u
	fi
}

get_gpu_list_as_menu()
{
	menu=""
	gpu_list_size=$(expr ${#gpu_list[@]} / 3)
	for ((i=0; i<$gpu_list_size; i++));	do
		if [ "$menu" == "" ]; then
			menu="$i%${gpu_list[$i,0]}"
		else
			menu="$menu%$i%${gpu_list[$i,0]}"
		fi
	done;
	echo $menu
}

select_gpu_compatible()
{
	least_one_gpu_compatible=0
	declare -A gpu_list
	gpu_count=0

	iommu_groups=$(get_iommu_groups);
	for iommu_group in $iommu_groups; do

		devices=$(get_iommu_group_devices)
		devices_count=$(echo $devices | wc -w)

		for device in $devices; do
			gpu_vga=$(test_pci_slot_as_vga $device)

			if [ ! -z "$gpu_vga" ]; then
				gpu_vga_slot=$(echo $gpu_vga | awk -F" " '{print $1}')

				if [ $devices_count -gt 2 ]; then
					display_bad_isolation $iommu_group "$devices"
				elif [ $devices_count -eq 2 ]; then

					second_device=$(echo $devices | awk -F" " '{print $2}')
					gpu_audio=$(test_pci_slot_as_audio $second_device)

					if [ ! -z "$gpu_audio" ]; then

						least_one_gpu_compatible=1

						gpu_audio_slot=$(echo $gpu_audio | awk -F" " '{print $1}')

						gpu_vga_pid_vid=$(get_pid_vid_from_slot $gpu_vga_slot)
						gpu_audio_pid_vid=$(get_pid_vid_from_slot $gpu_audio_slot)
						vfio=$gpu_vga_pid_vid","$gpu_audio_pid_vid

						gpu_list[$gpu_count,0]=$(get_pci_short_string_description_from_slot $gpu_vga)
						gpu_list[$gpu_count,1]=$vfio
						gpu_list[$gpu_count,2]=$gpu_vga_slot
						((gpu_count+=1))

					else
						display_bad_isolation $iommu_group "$devices"
					fi
				else

					least_one_gpu_compatible=1

					gpu_vga_pid_vid=$(get_pid_vid_from_slot $gpu_vga_slot)
					vfio=$gpu_vga_pid_vid

					gpu_list[$gpu_count,0]=$(get_pci_short_string_description_from_slot $device)
					gpu_list[$gpu_count,1]=$vfio
					gpu_list[$gpu_count,2]=$gpu_vga_slot
					((gpu_count+=1))
				fi
			fi
		done;
	done;

	if [ $least_one_gpu_compatible -eq 0 ]; then
		dialog --stdout --title "Error" --msgbox "\nNo compatible GPU available." 6 50
		exit 1
	else
		menu=$(get_gpu_list_as_menu $gpu_list)
		IFS=$'%'
		gpu_index=$(dialog --stdout --menu "Select GPU to share" 0 0 0 $menu)
		unset IFS
		if [ "$gpu_index" == "" ]; then
			dialog --stdout --title "Cancel" --msgbox "\nInstallation canceled." 6 30
			exit 2
		else
			gpu_vfio=${gpu_list[$gpu_index,1]}
			gpu_slot=${gpu_list[$gpu_index,2]}
			echo "$gpu_vfio $gpu_slot"
		fi
	fi
}

configure_grub_vfio()
{
	ret=0
	((ret+="$(set_grub_default_cmdline_vfio $1)"))
	clear
	((ret+="$(set_grub_pcies_aspm)"))
	if [ $ret -gt 0 ]; then
		sudo update-grub
		clear
	fi
}

# golem #############################################################################################################

check_golem_installed()
{
	if [ "$(command -v golemsp)" == "" ]; then
		echo 0
	else
		echo 1
	fi
}

check_golem_valid_vm()
{
	if [ "$(golemsp status | grep VM | grep "no access" | awk -F" " '{print $3}')" != "" ]; then
		echo 0
	else
		echo 1
	fi
}

check_golem_version()
{
	if [ "$(golemsp status | grep Version  | awk -F" " '{print $3}')" != "$GOLEM_CORE" ]; then
		echo 0
	else
		echo 1
	fi
}

check_golem()
{
	if [ $(check_golem_installed) -eq 0 ]; then
		display_error "Golem not installed" "Please install Golem $GOLEM_CORE." 6 35
	else
		if [ $(check_golem_valid_vm) -eq 0 ]; then
			display_error "Invalid Golem installation" "Please check your Golem installation." 7 45
		fi
		if [ $(check_golem_version) -eq 0 ]; then
			display_error "Invalid Golem version" "Please install Golem $GOLEM_CORE" 7 35
		fi
	fi
}

# overlay #############################################################################################################

install_overlay()
{
	cp -f ./ya-runtime-vm /home/$USER/.local/lib/yagna/plugins/ya-runtime-vm/ya-runtime-vm
	cp -f ./vmlinuz-virt /home/$USER/.local/lib/yagna/plugins/ya-runtime-vm/runtime/vmlinuz-virt
	cp -f ./vmrt /home/$USER/.local/lib/yagna/plugins/ya-runtime-vm/runtime/vmrt
	cp -f ./vgabios-stdvga.bin /home/$USER/.local/lib/yagna/plugins/ya-runtime-vm/runtime/vgabios-stdvga.bin
}

install_service()
{
	sudo cp -f ./golem_provider.service /etc/systemd/system/golem_provider.service
	sudo sed -i 's/SED_GPU_PCI/'$1'/' /etc/systemd/system/golem_provider.service
	sudo sed -i 's/SED_USER/'$USER'/' /etc/systemd/system/golem_provider.service
}

# others ##############################################################################################################

set_udev_vfio()
{
	if [ "$(grep -r vfio /etc/udev/rules.d | grep kvm)" == "" ]; then
		sudo sh -c "echo 'SUBSYSTEM==\"vfio\", OWNER=\"$USER\", GROUP=\"kvm\"' > /etc/udev/rules.d/vfio.rules"
	fi
}

display_error()
{
	dialog --title "$1" --msgbox "\n$2" $3 $4
	clear
	exit
}

display_bad_isolation()
{
	msg=$(list_pci_devices_in_iommu_group $1 "$2")
	dialog --stdout --title "GPU bad isolation" --msgbox "\n$msg" 10 130
}

reboot()
{
	dialog --stdout --title "Reboot" --msgbox "\n$1" $2 $3
	clear
	sudo reboot
}

#######################################################################################################################

check_packages_required
configure_iommu

gpu_selected=$(select_gpu_compatible)
ret=$?
clear
if [ $ret -gt 0 ]; then
	exit $ret
else
	check_golem

	gpu_vfio=$(echo $gpu_selected | awk -F" " '{print $1}')
	gpu_slot=$(echo $gpu_selected | awk -F" " '{print $2}')

	configure_grub_vfio $gpu_vfio
	enable_vfio_modules
	set_udev_vfio
	install_overlay
	install_service $gpu_slot
	reboot "Installation finished, reboot needed to complete." 6 55
fi
