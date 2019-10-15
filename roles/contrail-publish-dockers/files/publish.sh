#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"


function log(){
  echo -e "INFO: $(date --utc): $@"
} 

function warn(){
  echo -e "WARNING: $(date --utc): $@" >&2
} 

function err(){
  echo -e "ERROR: $(date --utc): $@" >&2
} 

log "Publish TF container"

[ -e $my_dir/publish.env ] && source $my_dir/publish.env

[ -z "$CONTRAIL_REGISTRY" ] && { err "empty CONTRAIL_REGISTRY" && exit -1; }
[ -z "$CONTAINER_TAG" ] && { err "empty CONTAINER_TAG" && exit -1; }
[ -z "$PUBLISH_TAG" ] && { err "empty PUBLISH_TAG" && exit -1; }

CONTRAIL_REGISTRY_INSECURE=${CONTRAIL_REGISTRY_INSECURE:-"true"}
PUBLISH_REGISTRY=${PUBLISH_REGISTRY:-}
PUBLISH_REGISTRY_USER=${PUBLISH_REGISTRY_USER:-}
PUBLISH_REGISTRY_PASSWORD=${PUBLISH_REGISTRY_PASSWORD:-}
PUBLISH_INCLUDE_REGEXP=${PUBLISH_INCLUDE_REGEXP:-"contrail"}
PUBLISH_EXCLUDE_REGEXP=${PUBLISH_EXCLUDE_REGEXP:-"base"}
PUBLISH_CONTAINERS_LIST=${PUBLISH_CONTAINERS_LIST:-'auto'}

log_msg="\n CONTRAIL_REGISTRY=$CONTRAIL_REGISTRY"
log_msg+="\n CONTRAIL_REGISTRY_INSECURE=$CONTRAIL_REGISTRY_INSECURE"
log_msg+="\n PUBLISH_REGISTRY=${PUBLISH_REGISTRY}"
log_msg+="\n PUBLISH_REGISTRY_USER=${PUBLISH_REGISTRY_USER}"
log_msg+="\n PUBLISH_INCLUDE_REGEXP=${PUBLISH_INCLUDE_REGEXP}"
log_msg+="\n PUBLISH_EXCLUDE_REGEXP=${PUBLISH_EXCLUDE_REGEXP}"
log "Options:$log_msg"

if [[ -n "$PUBLISH_REGISTRY_USER" && "$PUBLISH_REGISTRY_PASSWORD" ]] ; then
  registry_addr=$(echo $PUBLISH_REGISTRY | cut -s -d '/' -f 1)
  log "Login to target docker registry $registry_addr"
  [[ $PUBLISH_REGISTRY =~ / ]] && registry_addr+=
  echo $PUBLISH_REGISTRY_PASSWORD | docker login --username $PUBLISH_REGISTRY_USER --password-stdin $registry_addr
fi

function run_with_retry() {
  local cmd=$@
  local attempt=0
  for attempt in {1..3} ; do
    if $cmd ; then
      return 0
    fi
    sleep 1;
  done
  return 1
}

src_scheme="http"
[[ "$CONTRAIL_REGISTRY_INSECURE" != 'true' ]] && src_scheme="https"
contrail_registry_url="${src_scheme}://${CONTRAIL_REGISTRY}"

if [[ "${PUBLISH_CONTAINERS_LIST}" == 'auto' ]] ; then
  log "Request containers for publishing"
  if ! raw_repos=$(run_with_retry curl -s --show-error ${contrail_registry_url}/v2/_catalog) ; then
    err "Failed to request repo list from docker registry ${CONTRAIL_REGISTRY}"
    exit -1
  fi

  repos=$(echo "$raw_repos" | jq -c -r '.repositories[]' | grep "$PUBLISH_INCLUDE_REGEXP" | grep -v "$PUBLISH_EXCLUDE_REGEXP")
else
  repos=$(echo $PUBLISH_CONTAINERS_LIST | tr ',' '\n')
fi

log "Repos for publishing:\n$repos"
if [[ -z "$repos" ]] ; then
  err "Nothing to publish:\nraw_repos=${raw_repos}\nrepos=$repos"
  exit -1
fi

function get_container_full_name() {
  local container=$1
  local registry=$(echo $container | cut -s -d '/' -f 1)
  local name=$(echo $container | cut -s -d '/' -f 2,3)
  local full_name=$container
  if [ -z "$name" ] ; then
    # just short name, loopup the tag
    local tags=$(run_with_retry curl -s --show-error ${contrail_registry_url}/v2/$container/tags/list | jq -c -r '.tags[]')
    if ! echo "$tags" | grep -q "^$CONTAINER_TAG\$" ; then
      warn "No requested tag $CONTAINER_TAG in available tags for $container:"$tags
      return 1
    fi
    full_name="${CONTRAIL_REGISTRY}/${container}:${CONTAINER_TAG}"
  fi
  echo $full_name
}

function do_publish() {
  local container=$1

  local full_name=$(get_container_full_name $container)
  if [[ $? != 0 ]] ; then
    warn "$container skipped"
    return 0
  fi
  
  log "Pull $full_name"
  if ! run_with_retry docker pull $full_name ; then
    err "Failed to execute docker pull ${CONTRAIL_REGISTRY}/${container}:${CONTAINER_TAG}"
    return 1  
  fi

  local target_tag="$PUBLISH_REGISTRY"
  [ -n "$target_tag" ] && target_tag+="/"
  target_tag+="${container}:${PUBLISH_TAG}"
  log "Publish $target_tag started"
  if ! run_with_retry docker tag ${CONTRAIL_REGISTRY}/${container}:${CONTAINER_TAG} ${target_tag} ; then
    err "Failed to execute docker tag ${CONTRAIL_REGISTRY}/${container}:${CONTAINER_TAG} ${target_tag}"
    return 1  
  fi
  if ! run_with_retry docker push $target_tag ; then
    log "Failed to execute docker push $target_tag"
    return 1
  fi
  log "Publish $container finished succesfully"
}

jobs=""
for r in $repos ; do
  do_publish $r &
  jobs+=" $!"
done

was_errors=0
for j in $jobs ; do
  wait $j || {
    was_errors=1
  }
done

if [[ "$was_errors" != 0 ]] ; then
  err "Faield to publish TF containers"
  exit -1
fi

log "Publish TF container finished succesfully"
