#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd $DIR

usage()
{
    echo "build.sh [--outdir] [-h]"
}

outdir=/tmp/ido/build
workdir=/tmp/ido/work

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
        --) shift; break;;
    esac
done

mkdir -p $outdir
cp -r ido-master $outdir
cp -r ido-node $outdir
cp -r lib $outdir

mkdir -p $workdir
cd $workdir
git clone https://github.com/jplana/python-etcd.git
cd python-etcd && git checkout 0.4.3
cp -r src/etcd $outdir/lib
cp -r $outdir/lib $outdir/ido-master
cp -r $outdir/lib $outdir/ido-node
