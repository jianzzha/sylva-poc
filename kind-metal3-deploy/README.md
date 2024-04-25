# Running KIND with VM Emulated Baremetal Machine

Bring up a virtual mchine for testing,
```
./setup_vm_infra.sh
```

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

The above script will set up a baremetal bridge, add a MASQUERADE rules on on the baremetal bridge for VM internet access, start a dnsmasq pod and a sushy emulator pod on the baremetal bridge, and start the virtual machine on the baremetal bridge,
 
Add this virtual machine as a baremetal host,
```
./vm_bmh.sh start
```

At this moment, this script only expect one VM.

This VM will go through BMH inspection phase and end up in an available state.

## Cleanup

First delete the VM emulated BMH,
```
./vm_bmh.sh stop
```

This should should shutdown the VM.

Delete the ironic and baremetal operator,
```
kubectl delete -k ../manifests/bmo
kubectl delete -k ../manifests/ironic
```

Then clean up VM and infrastructure,
```
./cleanup_vm_infra.sh
```

