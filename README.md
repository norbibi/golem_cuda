# Golem (0.12.0) Cuda  

Golem Cuda is an overlay for Golem providers to enable GPU computing.

**Security aspect**

Distributed computing through a virtual machine requires device isolation, especially with a PCIe device like GPU.  
That's why provider should use motherboard with IOMMU and ACS support to provide device and host isolation.  
This way, each hardware device will be assigned to a different IOMMU group.  

Many motherboard share IOMMU group for multiple devices,  
so sharing a device of that group forces all devices in the same group to be shared.  
In addition to force sharing of unwanted devices, device compromising can affect all devices of this group.  
Kernel ACS patch can be used to bypass IOMMU and assign one device per vitual IOMMU group,  
 ... please don't use it ... the shared device can access all host RAM, it's a big security hole.  

This V3 release has an automated instaler with a terminal menu for GPU selection to simplify setup.  
The installation will stop if your hardware does not suppport device isolation.  

**Requirements**
- enable IOMMU & ACS in UEFI
- install Golem provider v0.12.0

**Build (optional)**
- ya-runtime-vm
``` 
cd ya-runtime-vm
cargo build --release
``` 
- vmrt
``` 
cd ya-runtime-vm/qemu
make
``` 
- vmlinuz-virt
``` 
cd docker_golem_cuda_base
make
``` 

**Installation**
``` 
./configure.sh
``` 
