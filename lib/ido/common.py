import os
import subprocess
from config import *
import etcd
import urllib2
import time
import shutil

def restart_container(container_name, volumns, ports, env_vars, image):
    os.system('bash -c \"docker rm -f {} 2>&1\">/dev/null'.format(container_name))
    cmdline = [
        'docker',
        'run',
        '-d',
        '--restart=always',
        '--name={}'.format(container_name)
    ]
    for key, value in env_vars.items():
        cmdline += ['-e', '{}={}'.format(key, value)]
    for item in ports:
        cmdline += ['-p', item]
    cmdline.append(image)

    child = subprocess.Popen(cmdline, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if child.wait() != 0:
        print child.stderr.read()
        return False

    return True

def is_kube_component_ok(ip, port):
    try:
        reply = urllib2.urlopen('http://{}:{}/healthz'.format(ip, port), timeout=5)
        if reply.getcode() != 200 or reply.read() != 'ok':
            return False
        return True
    except Exception as e:
        return False

def is_docker_ok():
    fobj = file('/dev/null')
    child = subprocess.Popen('docker info'.split(), stdout=fobj, stderr=fobj)
    status = child.wait()
    if status == 0:
        return True
    else:
        return False

def kill_process_by_name(name):
    fobj = file('/dev/null')
    child = subprocess.Popen('killall {}'.format(name).split(), stdout=fobj, stderr=fobj)
    status = child.wait()

def load_flannel_subnet():
    try:
        fobj = file('/var/run/flannel/subnet.env')
        lines = fobj.readlines()
        for line in lines:
            k,v = line.split('=')
            os.environ[k] = v
        return True
    except Exception:
        print 'Flannel is not OK'

def start_flannel(cluster_config):
    kill_process_by_name('flanneld')
    logfile = file('/var/log/ido/flannel.log', 'a')
    flanneld_path = os.environ['IDO_HOME'] + '/bin/flanneld'
    cmdline = '{} --etcd-endpoints=http://{}:4001'.format(flanneld_path, cluster_config.master_ip).split()
    child = subprocess.Popen(cmdline, stdout=logfile, stderr=logfile)
    while child.poll() is None:
        if load_flannel_subnet():
            print 'flannel started successfully'
            return True
        else:
            time.sleep(1)
    return False

def start_docker(cluster_config=None):
    print 'starting docker'
    os.system('bash -c \"service docker stop 2>&1\">/dev/null')
    kill_process_by_name('docker')
    if not load_flannel_subnet():
        print 'flanneld is not ok'
        return False
    os.system('bash -c \"ip link del docker0 2>&1\n" >/dev/null')
    cmdline = 'docker -d --bip={subnet} ' \
              '--mtu={mtu} '\
              '--log-level={log_level} ' \
              '--storage-driver=aufs' \
              .format(subnet=os.environ['FLANNEL_SUBNET'],
                      mtu=os.environ['FLANNEL_MTU'],
                      log_level = cluster_config.docker_log_level)
    for registry in cluster_config.docker_registries:
        cmdline += ' --insecure-registry {}'.format(registry)
    docker_log_fobj = file(cluster_config.log_dir + '/docker.log', 'a')
    child = subprocess.Popen(cmdline.split(), stdout=docker_log_fobj, stderr=docker_log_fobj)
    while child.poll() is None:
        if is_docker_ok():
            print 'docker started successfully'
            return True
        else:
            time.sleep(1)
    return False

def is_flannel_config_in_etcd(etcd_client):
    try:
        key = '/coreos.com/network/config'
        result = etcd_client.read(key).value
        return True
    except:
        return False

def get_etcd_client(master_ip):
   return etcd.Client(host=master_ip, port=4001)

def push_flannel_config(etcd_client, cluster_config):
    key = '/coreos.com/network/config'
    value = json.dumps(cluster_config.network_config.to_flannel_dict())
    etcd_client.write(key, value)

def load_config_from_etcd(etcd_client):
    try:
        key = '/ido/config'
        result = etcd_client.read(key).value
        cluster_config = ClusterConfig()
        cluster_config.load_from_json(json.loads(result))
        return cluster_config
    except:
        return None

class MasterManager:
    def __init__(self):
        self.CLUSTER_CONFIG_FILE = '/etc/ido/master.json'
        self.IDO_HOME = os.environ['IDO_HOME']
        self.cluster_config = None
        self.cluster_config_local = ClusterConfig()
        self.cluster_config_local.load_from_file(self.CLUSTER_CONFIG_FILE)
        self.master_ip = self.cluster_config_local.master_ip
        self.etcd_client = get_etcd_client(self.master_ip)

        if not os.path.exists('/var/log/ido'):
            os.makedirs('/var/log/ido')

    def load_config_from_etcd(self):
        if self.cluster_config is not None:
            return self.cluster_config
        else:
            return load_config_from_etcd(self.etcd_client)

    def start_etcd(self):
        print 'Starting etcd'
        cmd_line = [
            self.IDO_HOME + '/bin/etcd',
            '-name=node1',
            '-initial-advertise-peer-urls=http://{}:2380'.format(self.master_ip),
            '-advertise-client-urls=http://{}:2380'.format(self.master_ip),
            '-listen-peer-urls=http://{}:2380'.format(self.master_ip),
            '-listen-client-urls=http://{}:4001,http://127.0.0.1:4001'.format(self.master_ip),
            '-initial-cluster',
            'node1=http://{}:2380'.format(self.master_ip),
            '-data-dir={}'.format(self.cluster_config_local.etcd_data_path),
            '-initial-cluster-token',
            'ido-etcd-cluster',
            '-initial-cluster-state',
            'new'
        ]
        etcd_log_fobj = file('/var/log/ido/etcd.log', 'a')
        child = subprocess.Popen(cmd_line, stdout=etcd_log_fobj, stderr=etcd_log_fobj)
        while child.poll() is None:
            if self.is_etcd_ok():
                print 'etcd started successfully'
                key = '/ido/config'
                value = json.dumps(self.cluster_config_local.to_dict())
                self.etcd_client.write(key, value)

                return True

        return False

    def is_etcd_ok(self):
        try:
            reply = urllib2.urlopen('http://127.0.0.1:4001/version', timeout=5)
            if reply.getcode() != 200:
                return False
            return True
        except Exception as e:
            return False

    def start_docker(self):
        if not self.is_etcd_ok():
            print 'etcd is not OK'
            return False
        cluster_config = self.load_config_from_etcd()
        return start_docker(cluster_config)

    def start_flannel(self):
        cluster_config = self.load_config_from_etcd()
        if not is_flannel_config_in_etcd(self.etcd_client):
            push_flannel_config(self.etcd_client, cluster_config)
        start_flannel(cluster_config)

    def __start_kube_apiserver(self, cluster_config):
        print 'starting kube-apiserver'
        kill_process_by_name('kube-apiserver')
        cmdline = 'kube-apiserver --insecure-bind-address={master_ip} ' \
                  ' --bind-address={master_ip} '\
                  ' --insecure-port=8080 ' \
                  ' --kubelet-port=10250 '\
                  ' --etcd-servers=http://127.0.0.1:4001' \
                  ' --service-cluster-ip-range={service_ip_range} '\
                  .format(master_ip = cluster_config.master_ip,
                          service_ip_range = cluster_config.service_ip_range)
        logfile = file('/var/log/ido/kube-apiserver.log', 'a')
        child = subprocess.Popen(cmdline.split(), stdout=logfile, stderr=logfile)
        while child.poll() is None:
            if is_kube_component_ok(cluster_config.master_ip, 8080):
                print 'kube-apiserver started successfully'
                return True
            else:
                time.sleep(1)
        return False

    def __start_kube_controller(self, cluster_config):
        print 'starting kube-controller'
        kill_process_by_name('kube-controller-manager')
        cmdline = 'kube-controller-manager --master={master_ip}:8080'\
                  ' --address={master_ip}'\
                  .format(master_ip = cluster_config.master_ip)
        logfile = file('/var/log/ido/kube-controller-manager.log', 'a')
        child = subprocess.Popen(cmdline.split(), stdout=logfile, stderr=logfile)
        while child.poll() is None:
            if is_kube_component_ok(cluster_config.master_ip, 10252):
                print 'kube-controller started successfully'
                return True
            else:
                time.sleep(1)
        return False

    def __start_kube_scheduler(self, cluster_config):
        print 'starting kube-scheduler'
        kill_process_by_name('kube-scheduler')
        cmdline = 'kube-scheduler --master={master_ip}:8080'\
                  ' --address={master_ip}'\
                  .format(master_ip = cluster_config.master_ip)
        logfile = file('/var/log/ido/kube-scheduler.log', 'a')
        child = subprocess.Popen(cmdline.split(), stdout=logfile, stderr=logfile)
        while child.poll() is None:
            if is_kube_component_ok(cluster_config.master_ip, 10251):
                print 'kube-scheduler started successfully'
                return True
            else:
                time.sleep(1)
        return False

    def start_kubernetes_master(self):
        cluster_config = self.load_config_from_etcd()
        self.__start_kube_apiserver(cluster_config)
        self.__start_kube_controller(cluster_config)
        self.__start_kube_scheduler(cluster_config)

    def start(self):
        self.start_etcd()
        self.start_flannel()
        self.start_docker()
        self.start_kubernetes_master()
        if not self.create_paas_agent():
            print 'Failed to start paas-agent'
        self.start_heat()

    def start_heat(self):
        script_path = self.IDO_HOME + '/bin/heat-restart.sh'
        cluster_config = self.load_config_from_etcd()
        os.system('bash {} --registry={}'.format(script_path, cluster_config.idevopscloud_registry))

    def reset(self):
        os.system('bash -c \"service stop docker 2>&1\">/dev/null')
        kill_process_by_name('etcd')
        kill_process_by_name('docker')
        kill_process_by_name('flanneld')
        kill_process_by_name('kube-apiserver')
        kill_process_by_name('kube-controller-manager')
        kill_process_by_name('kube-scheduler')

        shutil.rmtree(self.cluster_config_local.etcd_data_path)
        self.start()

    def create_paas_agent(self):
        try:
            data = file('{}/conf/paas-agent.json'.format(self.IDO_HOME)).read()
            request = urllib2.Request('http://{}:8080/apis/extensions/v1beta1/namespaces/default/daemonsets'.format(self.master_ip),
                                      data=data,
                                      headers={'content-type':'application/json'})
            reply = urllib2.urlopen(request, timeout=5)
            if reply.getcode() not in [ 200, 201, 409 ]:
                return False
            return True
        except urllib2.HTTPError as e:
            if e.code in [409]:
                return True
        except Exception as e:
            print e

        return False

    def start_paas_api(self, paas_api_version):
        cluster_config = self.load_config_from_etcd()
        env_vars = {
            'DOCKER_REGISTRY_URL': '{}:5000'.format(cluster_config.master_ip),
            'K8S_IP': cluster_config.master_ip,
            'HEAT_IP': cluster_config.master_ip,
            'ETCD_IP': cluster_config.master_ip,
            'HEAT_USERNAME': 'admin',
            'HEAT_PASSWORD': 'ADMIN_PASS',
            'HEAT_AUTH_URL': 'http://{}:35357/v2.0'.format(cluster_config.master_ip),
        }
        ports = {
            '12306:12306',
        }
        image = '{}/idevops/paas-api:{}'.format(cluster_config.idevopscloud_registry, paas_api_version)
        return restart_container('paas-api', None, ports, env_vars, image)

    def start_paas_controller(self, version):
        cluster_config = self.load_config_from_etcd()
        env_vars = {
            'PAAS_API_SERVER': cluster_config.master_ip,
            'K8S_API_SERVER': 'http://{}:8080/api/v1'.format(cluster_config.master_ip),
            'ETCD_SERVER': cluster_config.master_ip
        }
        image = '{}/idevops/paas-controller:{}'.format(cluster_config.idevopscloud_registry, version)
        return restart_container('paas-controller',
                                 image,
                                 volumns = None,
                                 ports = None,
                                 env_vars = env_vars)

class NodeManager:
    def __init__(self):
        self.IDO_HOME = os.environ['IDO_HOME']
        self.node_config_local = self.__load_node_config_from_file('/etc/ido/node.json')
        self.master_ip = self.node_config_local.master_ip
        self.etcd_client = get_etcd_client(self.master_ip)
        self.cluster_config = load_config_from_etcd(self.etcd_client)

        if not os.path.exists('/var/log/ido'):
            os.makedirs('/var/log/ido')

    @staticmethod
    def init_local_config(master_ip, node_ip):
        params = {
            'master_ip': master_ip,
            'node_ip': node_ip
        }
        json.dump(params, file('/etc/ido/node.json', 'w'), indent=2)

    def __load_node_config_from_file(self, config_file):
        try:
            fobj = file(config_file)
            params = json.loads(fobj.read())
            return NodeConfig(params)
        except:
            raise

    def start_flannel(self):
        start_flannel(self.cluster_config)

    def start_docker(self):
        start_docker(self.cluster_config)

    def start_kubernetes_node(self):
        self.__start_kube_proxy()
        self.__start_kubelet()

    def __start_kube_proxy(self):
        print 'starting kube-proxy'
        kill_process_by_name('kube-proxy')
        cmdline = '{ido_home}/bin/kube-proxy --master={master_ip}:8080'\
                  ' --proxy-mode=userspace' \
                  .format(ido_home=self.IDO_HOME, master_ip=self.cluster_config.master_ip)
        logfile = file('/var/log/ido/kube-proxy.log', 'a')
        child = subprocess.Popen(cmdline.split(), stdout=logfile, stderr=logfile)
        while child.poll() is None:
            if is_kube_component_ok('127.0.0.1', 10249):
                print 'kube-proxy started successfully'
                return True
            else:
                time.sleep(1)
        return False
    
    def __start_kubelet(self):
        print 'starting kubelet'
        kill_process_by_name('kubelet')
        cmdline = '{ido_home}/bin/kubelet --api-servers={master_ip}:8080'\
                  ' --maximum-dead-containers=10'\
                  ' --minimum-image-ttl-duration=2m0s' \
                  ' --hostname_override={node_ip}' \
                  .format(ido_home=self.IDO_HOME,
                          master_ip=self.cluster_config.master_ip,
                          node_ip=self.node_config_local.node_ip)
        logfile = file('/var/log/ido/kubelet.log', 'a')
        child = subprocess.Popen(cmdline.split(), stdout=logfile, stderr=logfile)
        while child.poll() is None:
            if is_kube_component_ok('127.0.0.1', 10248):
                print 'kubelet started successfully'
                return True
            else:
                time.sleep(1)
        return False

    def start_docker(self):
        if self.cluster_config.master_ip != self.node_config_local.node_ip:
            start_docker(self.cluster_config)

    def start(self):
        self.start_flannel()
        self.start_docker()
        self.start_kubernetes_node()

