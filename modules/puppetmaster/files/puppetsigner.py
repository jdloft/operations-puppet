#!/usr/bin/python

#####################################################################
### THIS FILE IS MANAGED BY PUPPET
### puppet:///modules/ldap/scripts/puppetsigner.py
#####################################################################

import sys
import re
import ldapsupportlib
import socket
import subprocess
import os
import json
import ldap
from optparse import OptionParser  # FIXME: Use argparse


def getPuppetInfo(attr, conffile="/etc/puppet/puppet.conf"):
    f = open(conffile)
    for line in f:
        if line.split('=', 1)[0].strip() == attr:
            return line.split('=', 1)[1].strip()


parser = OptionParser(conflict_handler="resolve")
parser.set_usage("puppetsigner [options]")
ldapSupportLib = ldapsupportlib.LDAPSupportLib()
ldapSupportLib.addParserOptions(parser)
(options, args) = parser.parse_args()

ldapSupportLib.setBindInfoByOptions(options, parser)
ds = ldapSupportLib.connect()
basedn = ldapSupportLib.getLdapInfo('base')

try:
    puppet_output = subprocess.check_output(['/usr/bin/puppet', 'cert', 'list', '--all'])
    hosts = puppet_output.strip().split("\n")
    for host_string in hosts:
        host = host_string.split()
        # check to make sure hostname is actual hostname, to prevent
        # ldap injection attacks
        if host[0] == "(":
            continue  # FIXME: WAT
        if host[0] == '-':
            # Already marked as invalid or revoked
            continue
        if host[0] == '+':
            # Already signed
            signed = True
            hostname = host[1].strip('"')
        else:
            signed = False
            hostname = host[0].strip('"')

        if hostname == socket.getfqdn():
            # Ourselves!
            continue

        # Skip pathological hostnames -- possible attack vector.
        if not re.match(r'^[\.a-zA-Z0-9_-]+\.eqiad\.wmflabs$', hostname):
            sys.stderr.write('Invalid hostname %s\n' % hostname)
            subprocess.check_call(['/usr/bin/puppet', 'cert', 'clean', hostname])
            continue

        # Erase keys that don't correspond to ldap; sign those that do
        query = "(&(objectclass=puppetclient)(|(dc=" + hostname + ")(cnamerecord=" + hostname + ")(associateddomain=" + hostname + ")))"
        host_info = ds.search_s(basedn, ldap.SCOPE_SUBTREE, query)
        if not host_info:
            sys.stderr.write('Removing stale cert %s' % hostname)
            subprocess.check_call(['/usr/bin/puppet', 'cert', 'clean', hostname])
        elif not signed:
            sys.stderr.write('Signing new cert %s' % hostname)
            subprocess.check_call(['/usr/bin/puppet', 'cert', 'sign', hostname])
            subprocess.check_call(['/usr/bin/php',
                                   '/srv/org/wikimedia/controller/wikis/w/extensions/OpenStackManager/maintenance/onInstanceActionCompletion.php',
                                   '--action', 'build',
                                   '--instance', hostname])

    salt_output = subprocess.check_output(['/usr/bin/salt-key',
                                           '--list', 'unaccepted',
                                           '--out', 'json'])
    # Sign or delete unaccepted keys
    hosts = json.loads(salt_output)
    for host in hosts["minions_pre"]:
        if not re.match(r'^[a-zA-Z0-9_-]+\.eqiad\.wmflabs$', host):
            print 'Invalid hostname', host
            sys.exit(-1)
        query = "(&(objectclass=puppetclient)(|(dc=" + host + ")(cnamerecord=" + host + ")(associateddomain=" + host + ")))"
        host_result = ds.search_s(basedn, ldap.SCOPE_SUBTREE, query)
        if not host_result:
            subprocess.check_call(['/usr/bin/salt-key', '-y', '-d', host])
        else:
            subprocess.check_call(['/usr/bin/salt-key', '-y', '-a', host])

    # Purge accepted but unused keys
    salt_output = subprocess.check_output(['/usr/bin/salt-key',
                                           '--list', 'accepted',
                                           '--out', 'json'])
    hosts = json.loads(salt_output)
    for host in hosts["minions"]:
        if not re.match(r'^[a-zA-Z0-9_-]+\.eqiad\.wmflabs$', host):
            print 'Invalid hostname', host
            sys.exit(-1)
        query = "(&(objectclass=puppetclient)(|(dc=" + host + ")(cnamerecord=" + host + ")(associateddomain=" + host + ")))"
        host_result = ds.search_s(basedn, ldap.SCOPE_SUBTREE, query)
        if not host_result:
            sys.stderr.write('Removing stale salt key %s' % host)
            subprocess.check_call(['/usr/bin/salt-key', '-y', '-d', host])
finally:
    ds.unbind()
