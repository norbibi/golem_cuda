FROM ubuntu:focal-20220801

ENV TZ=Europe/Paris

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

COPY config-virt /usr/src/config-virt

RUN apt-get update && apt-get install -y \
	wget \
	kmod \
	gcc \
	make \
	xz-utils \
	flex \
	bison \
	libssl-dev \
	libelf-dev \
	bc \
	pkg-config \
	&& rm -rf /var/lib/apt/lists/*

RUN cd /usr/src \
	&& wget https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.10.29.tar.xz \
	&& tar xavf linux-5.10.29.tar.xz \
	&& cd linux-5.10.29 \
	&& mv /usr/src/config-virt /usr/src/linux-5.10.29/.config \
	&& make olddefconfig \
	&& make -j $(($(nproc --all)-1)) \
	&& make install \
	&& make modules_install \
	&& cd /usr/src \
	&& wget https://download.nvidia.com/XFree86/Linux-x86_64/525.85.05/NVIDIA-Linux-x86_64-525.85.05-no-compat32.run \
	&& chmod +x NVIDIA-Linux-x86_64-525.85.05-no-compat32.run \
	&& ./NVIDIA-Linux-x86_64-525.85.05-no-compat32.run -k 5.10.29 -s --kernel-source-path=/usr/src/linux-5.10.29 \
	&& rm -rf /usr/src/*
