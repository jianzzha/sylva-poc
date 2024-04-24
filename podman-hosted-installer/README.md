# Running self hosted assisted installer via podman

The sno.yaml in this directory contains the OKD image version that was tested to work. Update those image url if necessary.

To run the assisted installer service via podman,

```
export DEFAULT_IP_ADDRESS=192.168.39.54 && envsubst < sno.yaml > /tmp/podman_play.yaml
podman play kube /tmp/podman_play.yaml
```

To stop the service,
```
podman play kube --down /tmp/podman_play.yaml
```
