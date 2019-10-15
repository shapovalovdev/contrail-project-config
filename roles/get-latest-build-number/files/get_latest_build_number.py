#!/usr/bin/env python
from __future__ import print_function
import requests
from requests.auth import HTTPBasicAuth
import json
import re
import sys
import os
import itertools
import logging

log = logging.getLogger('get_public_build_number')

def get_tag_list(registry, repository, auth=None):
    url = registry + '/v2/' + repository + '/tags/list'
    if auth:
        auth = HTTPBasicAuth(*auth)
        catalog_req = requests.get('https://' + url, auth=auth)
    else:
        catalog_req = requests.get('http://' + url)
    catalog = catalog_req.json()
    #log.debug(catalog)
    return catalog["tags"] if catalog["tags"] is not None else []


def manifest_request(registry, image, tag, auth=None, method='GET'):
    headers = {'Accept': 'application/vnd.docker.distribution.manifest.v2+json'}
    url = '{}/v2/{}/manifests/{}'.format(registry, image, tag)
    if auth:
        auth = HTTPBasicAuth(*auth)
        manifest_req = requests.request(method, 'https://' + url, auth=auth, headers=headers)
    else:
        manifest_req = requests.request(method, 'http://' + url, headers=headers)
    return manifest_req


def get_image_manifest(registry, image, tag, auth=None):
    manifest = manifest_request(registry, image, tag, auth).json()
    #print(json.dumps(manifest, indent=4))
    return manifest


def get_image_id_from_registry(registry, image, tag, auth=None):
    return get_image_manifest(registry, image, tag, auth).get('config', {}).get('digest', None)


public_registry = sys.argv[1]
branch = sys.argv[2]
tag_regex = re.compile(r'^(\d\.(\d)+|master)-(\d+)$')
container = "contrail-go"
if branch == 'master':
    upstream_tag = 'latest'
else:
    upstream_tag = branch[1:] + '-latest'
try:
    go_latest_id = get_image_id_from_registry(public_registry, container, upstream_tag)
except Exception as e:
    print('Error during looking up the latest public image', container, upstream_tag, e)
    sys.exit(1)
go_tags = get_tag_list(public_registry, container)
for tag in reversed(go_tags):
    go_tag_id = get_image_id_from_registry(public_registry, container, tag)
    match = tag_regex.match(tag)
    if go_tag_id == go_latest_id and match:
        print(match.groups()[2])
        sys.exit(0)
print("Image matching the ID for the latest tag for container " + container + " not found")
sys.exit(1)
