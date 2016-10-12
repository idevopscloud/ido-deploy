#!/usr/bin/env python

import sys
import os
import subprocess
import json
import time
import argparse
import urllib2

if 'IDO_HOME' not in os.environ:
    print 'Environment variable <IDO_HOME> is not set'
    sys.exit(1)
else:
    IDO_HOME = os.environ['IDO_HOME']

sys.path.append(IDO_HOME + '/lib')
import ido
import etcd

def cmd_init(args):
    ido.NodeManager.init_local_config(args.master_ip, args.node_ip)
    print 'Node initialize successfully'

def cmd_start(args):
    node_mgr = ido.NodeManager()

    if args.component == 'docker':
        node_mgr.start_docker()
    elif args.component == 'flannel':
        node_mgr.start_flannel()
    elif args.component == 'k8s':
        node_mgr.start_kubernetes_node()
    elif args.component == 'all':
        node_mgr.start()

def help(args):
    print 'help command here'

def main(environ, argv):
    parser = argparse.ArgumentParser(prog='nodectl')
    subparsers = parser.add_subparsers(help='sub-command help')

    parser_init = subparsers.add_parser('init')
    parser_init.add_argument('--master-ip', action="store", dest='master_ip', required=True)
    parser_init.add_argument('--node-ip', action="store", dest='node_ip', required=True)
    parser_init.set_defaults(func=cmd_init)

    parser_start = subparsers.add_parser('start')
    parser_start.add_argument('component', choices=['all', 'docker', 'flannel', 'k8s'])
    parser_start.set_defaults(func=cmd_start)

    args = parser.parse_args(sys.argv[1:])
    return (args.func(args))

if __name__ == '__main__':
    main(os.environ, sys.argv[1:])

