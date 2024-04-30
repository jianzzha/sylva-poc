# Using kubeapi to boot up live iso in K8S

Set up the pull secret and ssh pub key in enviroment vars,
```
export SSH_PUB_KEY='ssh public key'
export PULL_SECRET='pull secret'
```

Apply the CRs in seqeunce,
```
envsubst < namespace.yaml | kubectl apply -f -
envsubst < pull-secret.yaml | kubectl apply -f -
envsubst < clusterimageset.yaml | kubectl apply -f -
envsubst < ClusterDeployment.yaml | kubectl apply -f -
envsubst < AgentClusterInstall.yaml | kubectl apply -f -
envsubst < InfraEnv.yaml | kubectl apply -f -
```

Verify that the infraenv status has the iso url,
```
kubectl -n demo-worker4 get infraenvs.agent-install.openshift.io myinfraenv -o=jsonpath="{'iPXE Script Download URL: '}{.status.bootArtifacts.ipxeScript}{'\n'}{'Initrd Download URL: '}{.status.bootArtifacts.initrd}{'\n'}{'Rootfs Download URL: '}{.status.bootArtifacts.rootfs}{'\n'}{'Kernel Download URL: '}{.status.bootArtifacts.kernel}{'\n'}"
```

Here is an example output,
```
PXE Script Download URL: http://10.89.1.241:8090/api/assisted-install/v2/infra-envs/2757c211-aecc-4dbd-b160-22b2da726031/downloads/files?file_name=ipxe-script
Initrd Download URL: http://10.89.1.240:8080/images/2757c211-aecc-4dbd-b160-22b2da726031/pxe-initrd?arch=x86_64&version=4.11
Rootfs Download URL: http://10.89.1.240:8080/boot-artifacts/rootfs?arch=x86_64&version=4.11
Kernel Download URL: http://10.89.1.240:8080/boot-artifacts/kernel?arch=x86_64&version=4.11
```

Check event list,
```
curl -s -k $(kubectl -n demo-worker4 get agentclusterinstalls.extensions.hive.openshift.io test-agent-cluster-install -o=jsonpath="{.status.debugInfo.eventsURL}")  | jq "."
```

Here is an example output,
```
[
  {
    "cluster_id": "4afb3f44-0f0f-453a-8ba9-067f8ae4bad5",
    "event_time": "2024-04-30T20:27:08.030Z",
    "message": "Successfully registered cluster",
    "name": "cluster_registration_succeeded",
    "severity": "info"
  },
  {
    "cluster_id": "4afb3f44-0f0f-453a-8ba9-067f8ae4bad5",
    "event_time": "2024-04-30T20:27:18.431Z",
    "infra_env_id": "2757c211-aecc-4dbd-b160-22b2da726031",
    "message": "Updated image information (Image type is \"full-iso\", SSH public key is set)",
    "name": "image_info_updated",
    "severity": "info"
  }
]
...
```

Get the live iso download URL,
```
kubectl -n demo-worker4 get infraenvs.agent-install.openshift.io myinfraenv -o=jsonpath="{.status.isoDownloadURL}"
```

Update the BMH to boot from the live iso,
```
...
spec:
  image:
    format: live-iso
    url: http://10.89.1.240:8080/byid/2757c211-aecc-4dbd-b160-22b2da726031/4.11/x86_64/full.iso
...
```

The BMH should reboot and register. To see the registered agent,
```
kubectl -n demo-worker4 get agents
```

To approve the agent for install,
```
kubectl -n demo-worker4 patch agents.agent-install.openshift.io d0148987-b19f-4604-bd4a-7bf93397e9eb -p '{"spec":{"approved":true}}' --type merge
```

The install begins.
```
NAME                                   CLUSTER       APPROVED   ROLE     STAGE
d0148987-b19f-4604-bd4a-7bf93397e9eb   single-node   true       master   Rebooting
```

After the disk is written, the iso should be unmounted, otherwise the progress will be paused, as shown below,
```
    "cluster_id": "4afb3f44-0f0f-453a-8ba9-067f8ae4bad5",
    "event_time": "2024-04-30T20:47:19.695Z",
    "host_id": "d0148987-b19f-4604-bd4a-7bf93397e9eb",
    "infra_env_id": "2757c211-aecc-4dbd-b160-22b2da726031",
    "message": "Host: okd-sno, reached installation stage Rebooting",
    "name": "host_install_progress_updated",
    "severity": "info"
  },
  {
    "cluster_id": "4afb3f44-0f0f-453a-8ba9-067f8ae4bad5",
    "event_time": "2024-04-30T20:47:47.722Z",
    "host_id": "d0148987-b19f-4604-bd4a-7bf93397e9eb",
    "infra_env_id": "2757c211-aecc-4dbd-b160-22b2da726031",
    "message": "Host okd-sno: updated status from installing-in-progress to installing-pending-user-action (Expected the host to boot from disk, but it booted the installation image - please reboot and fix boot order to boot from disk QEMU_HARDDISK drive-scsi0-0-0-0 (sda, /dev/disk/by-path/pci-0000:03:00.0-scsi-0:0:0:0))",
    "name": "host_status_updated",
    "severity": "warning"
  },
  {
    "cluster_id": "4afb3f44-0f0f-453a-8ba9-067f8ae4bad5",
    "event_time": "2024-04-30T20:47:57.256Z",
    "message": "Updated status of the cluster to installing-pending-user-action",
    "name": "cluster_status_updated",
    "severity": "info"
  }
```

Removing the live iso should not be done from BMH, otherwise the BMH deprovision will begin, like here,
```
bmh-vm-01   deprovisioning              true             5d4h
```

Change the boot order via redfish:
```
curl-X PATCH -H "content-type:application/json" --data '{"Boot":{"BootSourceOverideEnabled":"Continuous", "BootSourceOverrideTarget":"Hdd", "BootOrder":["Hdd"]}}' http://192.168.222.1:8000/redfish/v1/Systems/d0148987-b19f-4604-bd4a-7bf93397e9eb
```

Restart via redfish,
```
curl http://192.168.222.1:8000/redfish/v1/Systems/d0148987-b19f-4604-bd4a-7bf93397e9eb/Actions/ComputerSystem.Reset -H "content-type:application/json" --data '{"ResetType":"ForceRestart"}' -X POST
```

