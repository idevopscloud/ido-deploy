#!/bin/bash
export PATH=/sbin:/usr/sbin:/usr/local/sbin:/usr/local/bin:/usr/bin:/bin
export WORKDIR=$( cd ` dirname $0 ` && pwd )
cd "$WORKDIR" || exit 1

get_my_ip()
{
    my_ip=$(ip route get 1.0.0.0 | head -1 | cut -d' ' -f8)
    if [ ! -n "$my_ip" ]; then  
      my_ip=$(ifconfig eth0 | grep -oP 'inet addr:\K\S+')
      if [ ! -n "$my_ip" ]; then
            my_ip=$(hostname -I|cut -d' ' -f1)
      fi
    fi

    echo $my_ip
}

get_container_ip()
{
    ip=$(docker inspect $1 | grep -w IPAddress | head -1 | cut -d '"' -f 4)
    echo $ip
}

is_container_alive()
{
    container_id=$1
    status=$(docker inspect --format {{.State.Running}} $container_id 2>/dev/null)
    if [ "$status" != "true" ]; then
        return 1
    fi
    return 0
}

is_container_existed()
{
    container_id=$1
    docker inspect --format {{.State.Status}} $container_id 2>&1>/dev/null
    if [ $? == 0 ]; then
        return 0
    fi
    return 1
}

pre_check()
{
    if [[ -z "$my_ip" ]]; then
        echo "FATAL: ElasticIP does not exist! exit."
        exit 1
    fi

    # You MUST write k8s certification into this file
    if [ ! -f "$KUBE_CERT" ]; then
        KUBE_CERT="${PERSIST_DISK}/docker/heat/.kube_cert"
        echo > $KUBE_CERT
    fi

    if [[ "$KUBE_CERT" != "${PERSIST_DISK}/docker/heat/.kube_cert" ]]; then
        cp $KUBE_CERT ${PERSIST_DISK}/docker/heat/.kube_cert
    fi

}

pull_imgs()
{
    imgs="$img_mysql $img_rabbitmq $img_keystone $img_heat"
    for img in $imgs;do
        docker inspect $img 2>&1>/dev/null
        if (( 0 != $? )); then
            echo "pulling $img..."
            docker pull $img
            if (( 0 != $?)); then
                echo "Can not pull image <$img>"
                return 1
            fi
        fi
    done
}

rm_old_contains()
{
    containers="heat keystone rabbitmq mysql"
    status=0
    for ((i=0; i<3; i++ )) do
        status=0
        for c in $containers; do 
            if ( is_container_existed $c ); then
                docker rm -f $c 2>&1> /dev/null
                if [ $? != 0 ]; then
                    status=1
                fi
            fi
        done
        if [ $status == 0 ]; then
            break
        fi
    done
    return $status
}

#
# Returns:
#   1: the container is not alive
#   2: timeout
#
wait_for_service_ready()
{
    local PORT=$2
    local container_id=$1
    local MAX_RETRY=120
    attempt=1

    while true; do
        local ok=1
        if ! (is_container_alive $1); then
            return 1
        fi

        curl -s --connect-timeout 3 http://${my_ip}:$PORT > /dev/null 2>&1
        if [[ $? != 0 ]]; then
            if (( attempt > $MAX_RETRY )); then
                if [ $attempt -gt 1 ]; then
                    echo ""
                fi
                echo "Failed to start $PORT on ${my_ip}." >&2
                return 2
            fi
        else
            if [ $attempt -gt 1 ]; then
                echo ""
            fi
            echo "attempt ${attempt}: [$PORT running]"
            break
        fi
        if [ $attempt -gt 1 ]; then
            for (( i=1; i<10; i++ ));
            do
                echo -en "\b\b\b\b\b\b\b\b"
            done
        fi
        echo -n "attempt ${attempt}: [$PORT not working yet]"
        attempt=$(($attempt+1))
        sleep 2
    done
}

install_mysql()
{
    echo "installing ${img_mysql}"
    mysql_id=$(docker run --name mysql -h mysql \
        -v ${PERSIST_DISK}/docker/mysql:/var/lib/mysql \
        -e MYSQL_ROOT_PASSWORD=Letmein123 \
        -p 3307:3306 \
        -d ${img_mysql} 2>/dev/null)
    if [ $? != 0 -o "$mysql_id" == "" ]; then
        echo "Failed to start mysql server"
        return 1
    fi
    if ! (wait_for_service_ready $mysql_id 3307); then
        echo "Failed to start mysql server"
        return 1
    fi
    echo 'intalled mysql'
}

install_rabbitmq()
{
    echo "installing ${img_rabbitmq}"
    docker run -d \
        --hostname rabbitmq \
        --name rabbitmq \
        -e RABBITMQ_DEFAULT_PASS=Letmein123 \
        ${img_rabbitmq} > /dev/null
    echo 'sleep 5s to ensure rabbitmq is ready..'
    sleep 5 
    echo 'installed rabbitmq'
}

install_keystone()
{
    echo "installing ${img_keystone}"
    container_id=$(docker run -d \
        --link mysql:mysql\
        -e OS_TENANT_NAME=admin \
        -e OS_USERNAME=admin \
        -e OS_PASSWORD=ADMIN_PASS \
        -p 35357:35357\
        -p 5001:5001 \
        --name keystone -h ${my_ip} ${img_keystone})
    wait_for_service_ready $container_id 35357
}

install_heat()
{
    echo "installing ${img_heat}"
    container_id=$(docker run \
      -p 8004:8004 \
      --link mysql:mysql\
      --link rabbitmq:rabbitmq\
      --link keystone:keystone\
      -v /var/log/heat:/var/log/heat \
      -v ${PERSIST_DISK}/docker/heat:/root \
      --hostname heat \
      --name heat \
      -e KEYSTONE_HOST_IP=${keystone} \
      -e HOST_IP=heat \
      -e MYSQL_HOST_IP=mysql \
      -e MYSQL_USER=root \
      -e MYSQL_PASSWORD=Letmein123 \
      -e ADMIN_PASS=ADMIN_PASS \
      -e RABBIT_HOST_IP=rabbitmq \
      -e RABBIT_PASS=Letmein123 \
      -e HEAT_PASS=Letmein123 \
      -e HEAT_DBPASS=Letmein123 \
      -e HEAT_DOMAIN_PASS=Letmein123 \
      -e ETC_HOSTS="${hosts_conf}" \
      -d ${img_heat})
    wait_for_service_ready $container_id 8004
}

install_heatclient()
{
    if ! which heat 2>&1 > /dev/null; then
        echo 'Will install heat client...'
        echo "deb http://ubuntu-cloud.archive.canonical.com/ubuntu trusty-updates/kilo main" > /etc/apt/sources.list.d/cloudarchive-kilo.list
        apt-get update > /dev/null 2>&1
        apt-get install -y --force-yes python-heatclient > /dev/null
    fi

    HEAT_RC=/root/heatrc
    touch ${HEAT_RC}
    sed -i '/^export OS_/d' ${HEAT_RC}
    echo "export OS_PASSWORD=ADMIN_PASS" >> ${HEAT_RC}
    echo "export OS_AUTH_URL=http://${my_ip}:35357/v2.0" >> ${HEAT_RC}
    echo "export OS_USERNAME=admin" >> ${HEAT_RC}
    echo "export OS_TENANT_NAME=admin" >> ${HEAT_RC}
    source ${HEAT_RC}

    sed -i '/heatrc/d' /root/.bashrc
    echo ". ${HEAT_RC}" >> /root/.bashrc
    env | grep "^OS_"

    #heat resource-type-list | grep Google
    #heat stack-list
}

usage()
{
    echo -e "heat_restart.sh OPTIONS\n"
    echo -e "Options:\n"

    echo "  -h                  Show help message"
    echo '  --hosts=""          Additional host entries for /etc/hosts. For example:'
    echo '                      "172.30.10.185 dev.k8s.com\n172.30.10.122 k8s.com"'
    echo '  --kube-cert=""      Kubernetes certification file'
}


hosts_conf=""
KUBE_CERT=""
docker_registry="index.idevopscloud:5000"

OPTS=`getopt -o "h" -l kube-cert: -l hosts: -l registry: -- "$@"`
if [ $? != 0 ]; then
    echo "Usage error"
    exit 1
fi
eval set -- "$OPTS"

while true ; do
    case "$1" in
        -h) usage; exit 0;; 
        --hosts) hosts_conf=$2; shift 2;; 
        --kube-cert) KUBE_CERT=$2; shift 2;; 
        --registry) registry=$2; shift 2;;
        --) shift; break;;
    esac
done

img_mysql=${registry}/idevops/mysql:5.5
img_rabbitmq=${registry}/idevops/rabbitmq:3.6.1
img_keystone=${registry}/idevops/keystone:juno
img_heat=${registry}/idevops/heat:kilo-k8s-1.2.2

my_ip=$(get_my_ip)

PERSIST_DISK=/mnt/master-pd
mkdir -p ${PERSIST_DISK}/docker/heat/ 1>&2 > /dev/null
mkdir -p ${PERSIST_DISK}/docker/mysql 1>&2 > /dev/null

if [[ $# = 2 ]]; then
    echo "usage: $0 hosts_conf kube_cert_file"
    echo "e.g  : $0 \"172.30.10.185 dev.k8s..com\n172.30.10.122 k8s.com\" /srv/kubernetes/ca.cert"
    exit 1
fi


pre_check
if (( $? != 0 )); then
    exit 1
fi

pull_imgs
if (( $? != 0 )); then
    exit 1
fi

rm_old_contains
if (( $? != 0 )); then
    exit 1
fi

install_mysql
if (( $? != 0 )); then
    exit 1
fi

install_rabbitmq
if (( $? != 0 )); then
    exit 1
fi

install_keystone
install_heat
install_heatclient
