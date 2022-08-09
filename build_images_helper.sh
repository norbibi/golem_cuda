#!/bin/sh

build_docker_image()
{
	docker rmi $1:latest
	docker build --no-cache -t $1 $1
	gvmkit-build $1:latest
	echo 'Uploading ...'
	image_hash=$(gvmkit-build $1:latest --push | grep 'hash link ' | awk '{ print $6 }')
	echo "image_hash" $image_hash
	sed -i 's/.*image_hash.*/		image_hash="'$image_hash'",/' $2
	rm -rf *.gvmi
}
