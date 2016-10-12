#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $DIR

COMPONENTS="heat paas-api paas-controller paas-agent"

usage()
{
    echo "build.sh [--outdir] [--workdir=/tmp/ido/work] [--registry=172.31.0.11:5000] [-h] {heat, paas-api, paas-controller, paas-agent, python-kubernetes, ido-master-node} VERSION"
    echo "build.sh [--outdir] [--workdir=/tmp/ido/work] [-h] -f version.json ido"
}

outdir=""
workdir=/tmp/ido/work
version=""
component=""
docker_registry="172.31.0.11:5000"
package_url="http://172.31.0.11/idevops"

OPTS=`getopt -o "h" -l outdir: -l workdir: -- "$@"`
if [ $? != 0 ]; then
    echo "Usage error"
    exit 1
fi
eval set -- "$OPTS"

while true ; do
    case "$1" in
        -h) usage; exit 0;; 
        --outdir) outdir=$2; shift 2;; 
        --workdir) workdir=$2; shift 2;; 
        --) shift; break;;
    esac
done

if [ $# != 2 -o "$outdir" == "" ]; then
    usage
    exit 1
fi
component=$1
version=$2

workdir=$workdir/$version

mkdir -p $workdir
mkdir -p $outdir

build_ido_master_node()
{
    #
    # build ido-master and ido-node
    #
    cp -r ido-master $workdir
    cp -r ido-node $workdir
    cp -r lib $workdir

    cd $workdir
    git clone https://github.com/jplana/python-etcd.git
    cd python-etcd && git checkout 0.4.3
    cp -r src/etcd $workdir/lib
    cp -r $workdir/lib $workdir/ido-master
    cp -r $workdir/lib $workdir/ido-node
    cd $workdir
    tar czvf ido-master-${version}.tar.gz ido-master
    tar czvf ido-node-${version}.tar.gz ido-node
    cp ido-master-${version}.tar.gz $outdir
    cp ido-node-${version}.tar.gz $outdir
}

build_paas_api()
{
    # build paas-api docker image
    cd $workdir
    if [ -d $workdir/paas-api ]; then
        rm -r $workdir/paas-api
    fi
    if ! ( git clone git@bitbucket.org:idevops/paas-api.git); then
        echo "Failed to clone paas-api repo"
        exit 2
    fi
    cd paas-api
    if ! ( git checkout $version ); then
        echo "Failed to checkout paas-api code"
        exit 2
    fi
    bash build.sh
    if [ $? != 0 ]; then
        echo "Failed to build paas-api"
        exit 2
    fi
    cp $workdir/paas-api/target/paas-api.tar.gz $outdir/paas-api-${version}.tar.gz

    cd dfile
    bash build.sh --package-url http://172.31.0.11/idevops $version
    if [ $? != 0 ]; then
        echo "Failed to build paas-api"
        exit 2
    fi

    target_image_url=${docker_registry}/idevops/paas-api:{version}
    docker tag paas-api:${version} ${target_image_url}
    docker push ${target_image_url}
}

build_paas_controller()
{
    # build paas-controller docker image
    cd $workdir
    if [ -d $workdir/paas-controller ]; then
        rm -r $workdir/paas-controller
    fi
    if ! ( git clone git@bitbucket.org:idevops/paas-controller); then
        echo "Failed to clone paas-controller repo"
        exit 2
    fi
    cd paas-controller
    if ! ( git checkout $version ); then
        echo "Failed to checkout paas-controller code"
        exit 2
    fi
    bash build.sh
    if [ $? != 0 ]; then
        echo "Failed to build paas-controller"
        exit 2
    fi
    cp $workdir/paas-controller/target/paas-controller.tar.gz $outdir/paas-controller-${version}.tar.gz

    cd dfile
    bash build.sh --package-url ${package_url} $version
    if [ $? != 0 ]; then
        echo "Failed to build paas-controller"
        exit 2
    fi

    target_image_url=${docker_registry}/idevops/paas-controller:${version}
    docker tag paas-controller:$version ${target_image_url}
    docker push ${target_image_url}
}

build_heat()
{
    :
}

build_python_kubernetes()
{
    :
}

if [ "$component" == "heat" ]; then
    build_heat
elif [ "$component" == "paas-api" ]; then
    build_paas_api
elif [ "$component" == "python-kubernetes" ]; then
    build_python_kubernetes
elif [ "$component" == "ido-master-node" ]; then
    build_ido_master_node
fi
