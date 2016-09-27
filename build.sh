#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd $DIR

usage()
{
    echo "build.sh [--outdir] [--workdir] [-h] VERSION"
}

outdir=""
workdir=/tmp/ido/work
version=""

OPTS=`getopt -o "h" -l outdir: -- "$@"`
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

if [ $# != 1 -o "$workdir" == "" ]; then
    usage
    exit 1
fi
version=$1

workdir=$workdir/$version
outdir=$outdir/$version

mkdir -p $workdir
mkdir -p $outdir

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
bash build.sh --outdir $outdir $version
if [ $? != 0 ]; then
    echo "Failed to build paas-api"
    exit 2
fi

cd dfile
bash build.sh --package-url http://172.31.0.11/idevops $version
if [ $? != 0 ]; then
    echo "Failed to build paas-api"
    exit 2
fi

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
bash build.sh --outdir $outdir $version
if [ $? != 0 ]; then
    echo "Failed to build paas-controller"
    exit 2
fi

cd dfile
bash build.sh --package-url http://172.31.0.11/idevops $version
if [ $? != 0 ]; then
    echo "Failed to build paas-controller"
    exit 2
fi
