#!/usr/bin/bash
# Not completed

script_dir=$(dirname $(realpath $0))
script_name=$(basename $(realpath $0))

show_help() {
   echo "${script_name} is used to delete a terminating namespace"
   echo "-n <namespace>"
   echo "-w <second to wait after all namespaced resourced are deleted before force delete the namespace>"
   echo "-c <kubeconfig file>, otherwise assume $HOME/.kube/config to be used"
}

OPTIND=1
namespace=""
kubeconfig=""

while getopts "h?c:w:n:" opt; do
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
