# Running KIND with VM Emulated Baremetal Machine

Bring up testing infrastructure,
```
./setup_vm_infra.sh
```

The above script will set up a libvirt network "bmh", start a sushy emulator pod.

Bring up the KIND cluster,
```
kind create cluster --config kind.yaml
```

Wait after KIND node goes to ready state, install cert-manager,
```
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.3/cert-manager.yaml
```

Wait after cert-manager is running state, start ironic
```
kubectl apply -k ../manifests/ironic
```

Start baremetal operator,
```
kubectl apply -k ../manifests/bmo
```

Add a baremetal host,
```
./vm_bmh.sh start
```

This will create a VM and create a BMH for this VM. This VM will go through BMH inspection phase and end up in an available state.

To add multiple baremetal hosts (maximum 9) in one shot, say 5 BMH,
```
./vm_bmh.sh start 5
```

## Cleanup

Delete the BMH,
```
./vm_bmh.sh stop
```

Optionally, VM can also be removed with the BMH,
```
./vm_bmh.sh stop -r
```

Delete the ironic and baremetal operator,
```
kubectl delete -k ../manifests/bmo
kubectl delete -k ../manifests/ironic
```

Then clean up the test infrastructure,
```
./cleanup_vm_infra.sh
```

The VMs should be removed before the test infrastructure can be removed.

