import json

class ClusterConfig:
    def load_from_file(self, config_file):
        try:
            fobj = file(config_file)
            params = json.loads(fobj.read())
            self.load_from_json(params)
        except:
            raise

    def __str__(self):
        return json.dumps(self.to_dict())

    def load_from_json(self, params):
        self.master_ip = params.get('master_ip', None)
        if self.master_ip is None:
            raise Exception('<master_ip> is not specified')

        self.service_ip_range = params.get('service_ip_range', None)
        if self.service_ip_range is None:
            raise Exception('<service_ip_range> is not specified')

        self.etcd_data_path = params.get('etcd_data_path', None)
        if self.etcd_data_path is None:
            self.etcd_data_path = '/var/lib/ido/etcd_data'

        self.log_dir = '/var/log/ido'

        self.docker_log_level = params.get('docker_log_level', None)
        if self.docker_log_level is None:
            self.docker_log_level = 'info'

        if 'container_network' not in params:
            raise Exception('container_network is not specified')
        self.network_config = NetworkConfig(params['container_network'])

        self.idevopscloud_registry = params.get('idevopscloud_registry', None)
        if self.idevopscloud_registry is None:
            self.idevopscloud_registry = 'index.idevopscloud.com:5000'

        if 'private_registry' not in params:
            raise Exception('private_registry is not specified')
        self.private_registry = params.get('private_registry')

        self.docker_registries = params.get('other_registries', [])
        self.docker_registries.append(self.private_registry)
        self.docker_registries.append(self.idevopscloud_registry)

    def to_dict(self):
        data = {
            'master_ip': self.master_ip,
            'service_ip_range': self.service_ip_range,
            'log_dir': self.log_dir,
            'other_registries': self.docker_registries,
            'container_network': self.network_config.to_dict(),
            'private_registry': self.private_registry,
            'idevopscloud_registry': self.idevopscloud_registry,
        }

        return data

class NetworkConfig:
    def __init__(self, network_params):
        if not self.__check_network_config(network_params):
            raise Exception('network params are not valid')

        self.network = network_params['network']
        self.subnet_len = network_params['subnet_len']
        self.subnet_min = network_params['subnet_min']
        self.subnet_max = network_params['subnet_max']
        self.backend_type = 'udp'
        self.backend_port = 7890

    def __check_network_config(self, params):
        # TODO: check params
        return True

    def to_dict(self):
        return {
            'network': self.network,
            'subnet_len': self.subnet_len,
            'subnet_min': self.subnet_min,
            'subnet_max': self.subnet_max,
            'backend': {
                'type': self.backend_type,
                'port': self.backend_port
            }
        }

    def to_flannel_dict(self):
        return {
            'Network': self.network,
            'SubnetLen': self.subnet_len,
            'SubnetMin': self.subnet_min,
            'SubnetMax': self.subnet_max,
            'Backend': {
                'Type': self.backend_type,
                'Port': self.backend_port
            }
        }

class NodeConfig:
    def __init__(self, params):
        if 'master_ip' not in params:
            raise Exception('master_ip is not set')
        self.master_ip = params.get('master_ip')

        if 'node_ip' not in params:
            raise Exception('node_ip is not set')
        self.node_ip = params.get('node_ip')

