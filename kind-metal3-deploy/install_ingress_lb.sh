#!/bin/sh

kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml

kubectl wait --for=condition=available deployment/controller --timeout=300s -n metallb-system

helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx --create-namespace

kubectl wait --for=condition=available deployment/ingress-nginx-controller --timeout=300s -n ingress-nginx

kubectl apply -f metallb-config.yaml

kubectl patch configmap/ingress-nginx-controller -n  ingress-nginx --type merge -p '{"data":{"worker-processes":"1"}}'

ingress_ip=$(kubectl get svc  -n ingress-nginx ingress-nginx-controller  --no-headers --output=custom-columns=:.status.loadBalancer.ingress[0].ip)

if virsh net-uuid bmh >/dev/null 2>&1; then
    virsh net-update bmh add dns-host "<host ip='${ingress_ip}'><hostname>assisted.com</hostname></host>" --live --config
fi
