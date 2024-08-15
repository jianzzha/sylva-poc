#!/usr/bin/env bash

#we can't assume 192.168.222.1 as the address, so not easy to add a host entry
#grep -E -q  "^192.168.222.1\s+assisted.com" /etc/hosts
set -eu
set -o pipefail

INSTALL=""
NAMESPACE=""
VMs=""
while getopts 'n:ovmkh' opt; do
  case "$opt" in
    m)
      INSTALL="HELM"
      ;;

    k)
      INSTALL="KUST"
      ;;

    o)
      INSTALL="OPERATOR"
      ;;

    n)
      NAMESPACE="$OPTARG"
      ;;

    v)
      VMs="1"
      ;;

    ?|h)
      echo "Usage: -m: install assisted installer via helm charm"
      echo "       -k: install assisted installer via kustomization"
      echo "       -o: install assisted installer via infrastructure operator"
      echo "       -n <namespace>: setup bmh in this namespace"
      echo "       -v: bring up 1 virtual machine to emulate the bmh" 
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

if [[ ${INSTALL} == "HELM" ]]; then
    helm install assisted ../charts/assisted-installer --set createNamespace=true
    kubectl wait --for=condition=Available --timeout=300s deployment assisted-image-service -n assisted-installer
    kubectl wait --for=condition=Available deployment assisted-service -n assisted-installer
    kubectl wait --for=condition=Available deployment object-store  -n assisted-installer
    kubectl wait --for=condition=Available deployment postgres -n assisted-installer
elif [[ ${INSTALL} == "KUST" ]]; then 
    kubectl apply -k ../manifests/infra-operator
fi

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

if [[ ${INSTALL} == "OPERATOR" ]]; then
    if [[ -d ~/assisted-service ]]; then
	/bin/rm -rf ~/assisted-service
    fi
    git clone https://github.com/openshift/assisted-service.git ~/assisted-service
    cp setup_infra_operator.sh ~/assisted-service
    chmod u+x ~/assisted-service/setup_infra_operator.sh
    pushd ~/assisted-service
    ./setup_infra_operator.sh
    popd
    kubectl apply -f agentconfig.yaml
fi

