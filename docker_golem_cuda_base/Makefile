all: vmlinuz-virt

vmlinuz-virt: Dockerfile
	docker build -t docker_golem_cuda_base .
	docker tag docker_golem_cuda_base:latest maugnorbert/docker_golem_cuda_base:latest
	$(SHELL) copy_img maugnorbert/docker_golem_cuda_base /boot/vmlinuz-5.10.29 ./vmlinuz-virt

clean:
	rm -f vmlinuz-virt > /dev/null 2>&1
	docker rmi -f maugnorbert/docker_golem_cuda_base > /dev/null 2>&1

.PHONY: all

