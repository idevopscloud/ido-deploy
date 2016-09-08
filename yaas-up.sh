#!/bin/bash

export PATH=/sbin:/usr/sbin:/usr/local/sbin:/usr/local/bin:/usr/bin:/bin
export WORKDIR=$( cd ` dirname $0 ` && pwd )
cd "$WORKDIR" || exit 1

yaas_dir=/idevops
deploy_dir=${yaas_dir}/deploy
mkdir -p ${deploy_dir}

get_bin(){
	# need ssh public-key to allow git clone
	# should download from S3
	cd ${yaas_dir} || exit 1
	git clone git@bitbucket.org:idevops/yaas.git || exit 1
	cd ${yaas_dir}/yaas || exit 1
	git checkout auto_deploy || exit 1
}

install_yaas(){
	source kube-1.2.2/bin/util.sh
	source profile.sh
	
	start-etcd-local.sh
	start-master-local.sh
	start-flanneld-local.sh
	start-docker.sh
	install_crontab.sh
}

config_kube_env(){
    kubectl config set-cluster my-cluster --server=${my_ip}:8080
    kubectl config set-context my-context --cluster=my-cluster
    kubectl config use-context my-context
}


if [[ $# != 1 ]]; then
    echo "usage: $0 yaas_tag"
    echo "e.g  : $0 0.1"
    exit 1
fi

#yaas_tag=$1
#get_bin
#install_yaas
#config_kube_env

touch /tmp/fake-kube.ca
cd ${deploy_dir} && bash heat_restart.sh "" /tmp/fake-kube.ca
