#!/bin/bash

dir=$(dirname "$(realpath "$0")")

runtime=$dir/ya-runtime-vm/target/release/ya-runtime-vm
vmrt=$dir/ya-runtime-vm/qemu/vmrt
vmlinuz=$dir/buildroot/output/images/bzImage
initramfs=$dir/ya-runtime-vm/runtime/init-container/initramfs.cpio.gz

save_runtime=$dir/binaries/ya-runtime-vm
save_vmrt=$dir/binaries/vmrt
save_vmlinuz=$dir/binaries/bzImage
save_initramfs=$dir/binaries/initramfs.cpio.gz

enable_modules()
{
	grep -qxF 'vfio' /etc/modules || sudo sh -c "echo vfio >> /etc/modules"
	grep -qxF 'vfio_iommu_type1' /etc/modules || sudo sh -c "echo vfio_iommu_type1 >> /etc/modules"
	grep -qxF 'vfio_pci' /etc/modules || sudo sh -c "echo vfio_pci >> /etc/modules"
	grep -qxF 'kvm' /etc/modules || sudo sh -c "echo kvm >> /etc/modules"
	grep -qxF 'kvm_intel' /etc/modules || sudo sh -c "echo kvm_intel >> /etc/modules"
	grep -qxF 'kvm_amd' /etc/modules || sudo sh -c "echo kvm_amd >> /etc/modules"
	sudo update-initramfs -u
}

update_grub()
{
	lspci -nn
	echo -e '\n'
	read -r -u 2 -p "GPU_PCI_VGA_ID to share (ex: 10de:1c82): " gpu_pci_vga_id
	read -r -u 2 -p "GPU_PCI_SOUND_ID to share (ex: 10de:0fb9): " gpu_pci_sound_id
	read -r -u 2 -p "IB_PCI_ID to share (ex: 1077:7322): " ib_pci_id

	if [ "$ib_pci_id" == "" ]; then
		sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash intel_iommu=on amd_iommu=on iommu=pt kvm_amd.npt=1 kvm_amd.avic=1 vfio-pci.ids='$gpu_pci_vga_id','$gpu_pci_sound_id' pcie_acs_override=downstream"/' /etc/default/grub
	else
		sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash intel_iommu=on amd_iommu=on iommu=pt kvm_amd.npt=1 kvm_amd.avic=1 vfio-pci.ids='$gpu_pci_vga_id','$gpu_pci_sound_id','$ib_pci_id' vfio-pci.disable_idle_d3=1 pcie_acs_override=downstream"/' /etc/default/grub
	fi
	sudo update-grub
}

check_golem_user_exists()
{
	if [ $(id -u golem) ]; then
		echo 1
	else
		echo 0
	fi
}

check_golem_home_exists()
{
	if [ -d "/home/golem" ]; then
		echo 1
	else
		echo 0
	fi
}

create_golem_user()
{
	echo "create_golem_user"
	sudo useradd golem --home /home/golem --groups kvm
	sudo sh -c "echo 'SUBSYSTEM==\"vfio\", OWNER=\"golem\", GROUP=\"kvm\"' > /etc/udev/rules.d/vfio.rules"
}

create_golem_home()
{
	echo "create_golem_home"
	sudo mkdir /home/golem
	sudo chown golem /home/golem
}

get_user_from_type()
{
	if [ $1 == "provider" ]; then
		echo "golem"
	elif [ $1 == "requestor" ]; then
		echo "$USER"
	fi
}

check_yagna()
{
	guser=$(get_user_from_type $1)
	if [ ! -f "/home/$guser/.local/bin/yagna" ]; then
		echo "Please install Yagna"
		exit
	fi
}

install_yagna()
{
	guser=$(get_user_from_type $1)
	if [ $1 == "provider" ]; then
		if [ $(check_golem_user_exists) == 0 ]; then
			create_golem_user
		fi
		if [ $(check_golem_home_exists) == 0 ]; then
			create_golem_home
		fi
		file="https://join.golem.network/as-provider"
	else
		file="https://join.golem.network/as-requestor"
	fi
	sudo su -l $guser -c "curl -sSf $file | bash -"
	if [ $1 == "provider" ]; then
		install_provider_overlay
	fi
}

build_runtime()
{
	cd $dir/ya-runtime-vm
	git submodule update --init --recursive
	cargo clean
	cargo build --release
	cp -f $runtime $save_runtime
	cp -f $initramfs $save_initramfs
}

build_vmrt()
{
	cd $dir/ya-runtime-vm/qemu
	rm -f vmrt
	docker rmi build-qemu:latest
	make
	cp -f $vmrt $save_vmrt
}

build_kernel()
{
	cores=$(($(nproc --all)-1))
	cd $dir/buildroot
	make clean
	make qemu_x86_64_golem_defconfig
	make -j $cores
	cp -f $vmlinuz $save_vmlinuz
}

build_provider_overlay()
{
	build_runtime
	build_vmrt
	build_kernel
}

install_runtime()
{
	sudo cp -f $1 /home/golem/.local/lib/yagna/plugins/ya-runtime-vm/
}

install_initramfs()
{
	sudo cp -f $1 /home/golem/.local/lib/yagna/plugins/ya-runtime-vm/runtime/
}

install_vmrt()
{
	sudo cp -f $dir/adds/vgabios-stdvga.bin /home/golem/.local/lib/yagna/plugins/ya-runtime-vm/runtime/
	sudo cp -f $dir/adds/efi-virtio.rom /home/golem/.local/lib/yagna/plugins/ya-runtime-vm/runtime/
	sudo cp -f $1 /home/golem/.local/lib/yagna/plugins/ya-runtime-vm/runtime/
}

install_kernel()
{
	sudo cp -f $1 /home/golem/.local/lib/yagna/plugins/ya-runtime-vm/runtime/vmlinuz-virt
}

install_provider_overlay()
{
	install_runtime $runtime
	install_vmrt $vmrt
	install_initramfs $initramfs
	install_kernel $vmlinuz
}

install_service_provider()
{
	lspci -nn
	echo -e '\n'

	default_payment_network="testnet"
	default_subnet="devnet-beta"
	default_gpu_pci="no"
	default_internet_outbound="no"
	default_ib_pci="no"
	default_ib_cluster_id="none"

	read -r -u 2 -p "Payment network (ex: mainnet, default testnet): " payment_network
	read -r -u 2 -p "Subnet (ex: public-beta, default devnet-beta): " subnet
	read -r -u 2 -p "GPU_VGA_PCI to share (ex: 04:00.0, default no): " gpu_pci
	read -r -u 2 -p "Internet Outbound (ex: yes, default no): " internet_outbound
	read -r -u 2 -p "IB_PCI to share (ex: 06:00.0, default no): " ib_pci
	read -r -u 2 -p "IB cluster id (ex: myib, default none): " ib_cluster_id

	if [ $payment_network == "" ]; then
		payment_network=$default_payment_network
	fi

	if [ $subnet == "" ]; then
		subnet=$default_subnet
	fi

	if [ $gpu_pci == "" ]; then
		gpu_pci=$default_gpu_pci
	fi

	if [ $internet_outbound == "" ]; then
		internet_outbound=$default_internet_outbound
	fi

	if [ $ib_pci == "" ]; then
		ib_pci=$default_ib_pci
	fi

	if [ $ib_cluster_id == "" ]; then
		ib_cluster_id=$default_ib_cluster_id
	fi

	sudo cp -f $dir/adds/golem_provider.service /etc/systemd/system/

	sudo sed -i 's/SED_PAYMENT_NETWORK/'$payment_network'/' /etc/systemd/system/golem_provider.service
	sudo sed -i 's/SED_SUBNET/'$subnet'/' /etc/systemd/system/golem_provider.service
	sudo sed -i 's/SED_GPU_PCI/'$gpu_pci'/' /etc/systemd/system/golem_provider.service
	sudo sed -i 's/SED_INTERNET_OUTBOUND/'$internet_outbound'/' /etc/systemd/system/golem_provider.service
	sudo sed -i 's/SED_IB_PCI/'$ib_pci'/' /etc/systemd/system/golem_provider.service
	sudo sed -i 's/SED_IB_CLUSTER_ID/'$ib_cluster_id'/' /etc/systemd/system/golem_provider.service
}

install_service_requestor()
{
	sudo cp -f $dir/adds/golem_requestor.service /etc/systemd/system/
	sudo sed -i 's/SED_USER/'$USER'/g' /etc/systemd/system/golem_requestor.service
}

start_requestor()
{
	/home/$USER/.local/bin/yagna service run > /dev/null 2>&1 &
	sleep 5
	/home/$USER/.local/bin/yagna payment init --sender
}

get_app_key()
{
	appkey=$(/home/$USER/.local/bin/yagna app-key list --json | jq '.values[0][1]')
	echo $appkey
}

create_appkey()
{
	appkey=$(get_app_key)
	if [ $appkey == null ]; then
		appkey=$(/home/$USER/.local/bin/yagna app-key create requestor)
	fi
}

create_export_appkey()
{
	appkey=$(get_app_key)
	echo "export YAGNA_APPKEY=$appkey" > $dir/appkey_env.sh
	echo "export key with: source ./appkey_env.sh"
}

request_test_tokens()
{
	echo -e "\nRequest test tokens"
	res_payment=""
	while [[ $res_payment != *"Received funds"* ]]; do
		res_payment=$(/home/$USER/.local/bin/yagna payment fund 2>/dev/null)
	done
	sleep 30
	yagna payment status
}

init_requestor()
{
	check_yagna requestor
	/home/$USER/.local/bin/yagna service run > /dev/null 2>&1 &
	sleep 3
	create_appkey
	request_test_tokens
	create_export_appkey
	killall yagna
}

restore_binaries()
{
	mkdir -p $dir/ya-runtime-vm/target/release
	mkdir -p $dir/ya-runtime-vm/qemu
	mkdir -p $dir/ya-runtime-vm/runtime/init-container
	mkdir -p $dir/buildroot/output/images
	cp -f $save_runtime $runtime
	cp -f $save_initramfs $initramfs
	cp -f $save_vmrt $vmrt
	cp -f $save_vmlinuz $vmlinuz
}

delete_golem_user()
{
	sudo userdel golem
	sudo rm -rf /home/golem
}

usage()
{
	echo "Usage: golem_cuda -COMMMAND [TARGET]"
	echo ""
	echo "Commands:"
	echo ""
	echo "	-b		                    build provider_overlay"
	echo "	-i [provider|requestor]		install target"
	echo ""
	exit
}

while getopts "bi:ds" opts; do
    case "${opts}" in
        b)
           	echo "build provider overlay"
           	build_provider_overlay
            exit
            ;;
        i)
            target=${OPTARG}
            [ $target = "provider" ] || [ $target = "requestor" ] || usage
        	echo "install $option"
        	if [ $target = "provider" ]; then
        		update_grub
        		enable_modules
        		restore_binaries
        	fi
        	install_yagna $target
        	if [ $target = "requestor" ]; then
        		init_requestor
        		install_service_requestor
        	else
        		install_service_provider
        	fi
            exit
            ;;
		s)
			start_requestor
			exit
			;;
		d)
			delete_golem_user
			exit
			;;
        *)
            usage
            ;;
    esac
done


