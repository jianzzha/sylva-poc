#!/usr/bin/bash
# Not completed
set -e
set -o pipefail

script_dir=$(dirname $(realpath $0))
script_name=$(basename $(realpath $0))

show_help() {
   echo "${script_name} is used to delete a terminating namespace"
   echo "-n <namespace>"
   echo "-w <second to wait after all namespaced resourced are deleted before force delete the namespace>"
   echo "-c <kubeconfig file>, otherwise assume $HOME/.kube/config to be used"
   echo "-b <metal3 namespace>, need to use with -d"
   echo "-d delete BMHs from the namespace before delete the namespace"
}

delete_bmh() {
   echo "Deleting BMHs from namespace ${namespace}"
   kubectl delete bmh -n ${namespace} --all --wait=false
}

OPTIND=1
namespace=""
kubeconfig=""
deletebmh="false"
t_wait=10

while getopts "hd?c:w:n:b:" opt; do
  case "$opt" in
    h)
      show_help
      exit 0
      ;;
    c)
      kubeconfig=$OPTARG
      ;;
    n)
      namespace=$OPTARG
      ;;
    w)
      t_wait=$OPTARG
      ;;
    d)
      deletebmh="true"
      ;;
    b)
      metal3ns=$OPTARG
      ;;
    \?)
      show_help
      exit 1
      ;;
  esac
done

# namespace is a must
if [[ -z "${namespace}" ]]; then
    show_help
    exit 1
fi

if [[ -n "${kubeconfig}" ]]; then
    export KUBECONFIG="${kubeconfig}"
fi

if ! kubectl get ns ${namespace} >/dev/null 2>&1; then
    echo "Namespace ${namespace} not exist"
    exit 0
fi

if [[ "${deletebmh}" == "true" ]]; then
    delete_bmh
fi

curr_state=$(kubectl get ns ${namespace} -o jsonpath='{.status.phase}')
if [[ ${curr_state} != "Terminating" ]]; then
    echo "Namespace ${namespace} current state: ${curr_state}. Delete and wait for ${t_wait}"
    kubectl delete ns ${namespace} --wait=false
    sleep ${t_wait}
    if ! kubectl get ns ${namespace} >/dev/null 2>&1; then
	# namespace deleted, no need to continue
	echo "Namespace ${namespace} deleted"
	exit 0
    fi
    curr_state=$(kubectl get ns ${namespace} -o jsonpath='{.status.phase}')
    # if namespace not in Terminating state then something wrong
    if [[ ${curr_state} != "Terminating" ]]; then
	echo "Namespace ${namespace} in state ${curr_state} after deletion, can not continue"
	exit 1
    fi
fi

if [[ "${deletebmh}" == "true" && "${metal3ns}" == "" ]]; then
    echo '-b not given, assuming metal3 namespace is metal3-system'
    metal3ns='metal3-system'
fi

if [[ "${deletebmh}" == "true" ]]; then
    ironic_api_username=`kubectl get secret -n ${metal3ns} ironic-basic-auth -o jsonpath='{.data.username}' | base64 -d`
    ironic_api_password=`kubectl get secret -n ${metal3ns} ironic-basic-auth -o jsonpath='{.data.password}' | base64 -d`
    ironic_db_password=`kubectl get secret -n ${metal3ns} ironic-mariadb -o jsonpath='{.data.password}' | base64 -d`
    ironic_url=`kubectl get cm -n ${metal3ns} ironic-bmo -o jsonpath="{.data.IRONIC_EXTERNAL_HTTP_URL}"`

    bmhs=`kubectl get bmh -n ${namespace} -o custom-columns=:metadata.name --no-headers`
    for bmh in ${bmhs}; do
	uid=`kubectl get bmh -n ${namespace} ${bmh} -o jsonpath="{.metadata.uid}"`
	if [[ -z "${uid}" ]]; then
	    continue
	fi
        ironic_node_uuid=`kubectl exec -it metal3-metal3-mariadb-647cf958c4-l5mbx -n metal3-system -- mysql -u ironic -p${ironic_db_password} -B -N -e "use ironic; select uuid from nodes where instance_uuid=\"${uid}\";" | tr -d '\r'`
	if [[ -z "${ironic_node_uuid}" ]]; then
            continue
	fi
	echo "curl -X PUT -k -u ironic:${ironic_api_password} ${ironic_url}/v1/nodes/${ironic_node_uuid}/maintenance"
        curl -X PUT -k -u ironic:${ironic_api_password} ${ironic_url}/v1/nodes/${ironic_node_uuid}/maintenance
	echo "curl -X DELETE -k -u ironic:${ironic_api_password} ${ironic_url}/v1/nodes/${ironic_node_uuid}"
	curl -X DELETE -k -u ironic:${ironic_api_password} ${ironic_url}/v1/nodes/${ironic_node_uuid}
    done
fi

# namespace should be in Terminating state here
echo "Removing finalizer from api resources in namespace ${namespace}"
resources=$(kubectl api-resources --verbs=list --namespaced -o name)
for resource in ${resources}; do
  kind_slash_resource=$(kubectl get ${resource} --show-kind --ignore-not-found -n ${namespace} --no-headers | awk '{print $1}')
  # make kind_slash_resource contains a '/'
  if [[ ${kind_slash_resource} == *"/"* ]];  then
      echo "Remove finalizers from ${kind_slash_resource}"
      kubectl patch ${kind_slash_resource}  -n ${namespace} -p '{"metadata":{"finalizers":[]}}' --type=merge
  fi
done

echo "Wait for ${t_wait}"
# if namespace gone?
if ! kubectl get ns ${namespace} >/dev/null 2>&1; then
    echo "Namespace ${namespace} deleted"
    exit 0
fi

curr_state=$(kubectl get ns ${namespace} -o jsonpath='{.status.phase}')
echo "After namespaced resource deletion, namespace ${namespace} current state: ${curr_state}"
echo "Force deleting namespace ${namespace}"
kubectl get ns ${namespace} -o json | jq '.spec.finalizers = []' | kubectl replace --raw "/api/v1/namespaces/${namespace}/finalize" -f -

sleep 1
# if namespace gone?
if ! kubectl get ns ${namespace} >/dev/null 2>&1; then
    echo "Namespace ${namespace} is gone after force deletion."
    exit 0
fi

echo "Failed to delete namespace ${namespace}"
exit 1
