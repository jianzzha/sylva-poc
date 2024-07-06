#!/usr/bin/env bash

#we can't assume 192.168.222.1 as the address, so not easy to add a host entry
#grep -E -q  "^192.168.222.1\s+assisted.com" /etc/hosts
set -eu
set -o pipefail

VMs=""
NAMESPACE=""
while getopts 'v:n:h' opt; do
  case "$opt" in
    v)
      VMs="$OPTARG"
      ;;

    n)
      NAMESPACE="$OPTARG"
      ;;

    ?|h)
      echo "Usage: $(basename $0) [-v VMs] [-n namespace]"
      exit 1
      ;;
  esac
done
shift "$(($OPTIND -1))"

if ! command -v helm &> /dev/null; then
    echo "helm not found, installing ..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

if ! command -v clusterctl &> /dev/null; then
    echo "clusterctl not found, installing ..."
    curl -L https://github.com/kubernetes-sigs/cluster-api/releases/download/v1.7.3/clusterctl-linux-arm64 -o clusterctl
    install -o root -g root -m 0755 clusterctl /usr/local/bin/clusterctl
    rm -rf clusterctl
fi

kind delete cluster
kind create cluster --config $(dirname $0)/kind.yaml

kubectl wait --for=condition=Ready nodes kind-control-plane

kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.3/cert-manager.yaml

kubectl wait --for=condition=Available --timeout=300s deployment cert-manager -n cert-manager
kubectl wait --for=condition=Available deployment cert-manager-webhook -n cert-manager
kubectl wait --for=condition=Available deployment cert-manager-cainjector -n cert-manager

kubectl apply -k ../manifests/ironic

kubectl apply -k ../manifests/bmo

kubectl wait --for=condition=Available --timeout=600s deployment ironic -n baremetal-operator-system
kubectl wait --for=condition=Available deployment baremetal-operator-controller-manager -n baremetal-operator-system

./install_ingress_lb.sh

helm install assisted ../charts/assisted-installer --set createNamespace=true
kubectl wait --for=condition=Available --timeout=300s deployment assisted-image-service -n assisted-installer
kubectl wait --for=condition=Available deployment assisted-service -n assisted-installer
kubectl wait --for=condition=Available deployment object-store  -n assisted-installer
kubectl wait --for=condition=Available deployment postgres -n assisted-installer

clusterctl init --bootstrap openshift-agent --control-plane openshift-agent -i  metal3:v1.7.0

if [[ -n "$NAMESPACE" ]]; then
    kubectl create namespace ${NAMESPACE}
    kubectl config set-context --current --namespace=${NAMESPACE}
fi

if [[ -n "$VMs" ]]; then 
    ./vm_bmh.sh stop -r
    ./vm_bmh.sh start
    kubectl wait --for=jsonpath='{.status.provisioning.state}'=available bmh bmh-vm-01 --timeout=300s
fi

