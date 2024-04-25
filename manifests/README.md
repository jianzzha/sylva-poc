# Running Assisted Installer Service in K8S

Assume a k8s cluster is already setup, the following steps will bring up the necessary services for the assisted installer service,
```
kubectl apply -k ironic
kubectl apply -k bmo
kubectl apply -k namespace
kubectl apply -k agentinstalladmission
kubectl apply -k assisted-image-service
kubectl apply -k assisted-service
```

Or all in one step,
```
kubectl apply -k .
```
 
