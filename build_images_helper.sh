#!/bin/sh

build_golem_tmp_fs()
{
	cd ../../../buildroot
	cores=$(($(nproc --all)-1))
	make clean
	make $1
	make -j $cores	
}

build_docker_golem_tmp()
{
	cd $1
	mkdir unsquashfs
	unsquashfs -f -d $1/unsquashfs/ ../../../buildroot/output/images/rootfs.squashfs
	tar -C $1/unsquashfs -c . | docker import - golem_tmp:latest
	rm -rf unsquashfs
}

build_docker_image()
{
	docker rmi $1:latest
	docker build --no-cache -t $1 $1
	gvmkit-build $1:latest
	echo 'Uploading ...'
	image_hash=$(gvmkit-build $1:latest --push | grep 'hash link ' | awk '{ print $6 }')
	echo "image_hash" $image_hash
	sed -i 's/.*image_hash.*/		image_hash="'$image_hash'",/' $2
}

clean()
{
	rm -rf unsquashfs
	rm -rf *.gvmi
	docker rmi golem_tmp:latest
}

