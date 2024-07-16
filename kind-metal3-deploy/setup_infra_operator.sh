#!/bin/bash
kubectl apply -f  hack/crds/hive.openshift.io_clusterdeployments.yaml
#kubectl apply -f  hack/crds/metal3.io_baremetalhosts.yaml
kubectl apply -f  hack/crds/hive.openshift.io_clusterimagesets.yaml
kustomize build config/default/ | kubectl apply -f -
