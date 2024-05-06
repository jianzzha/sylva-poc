#!/bin/bash
set -eu
set -o pipefail

for podname in sushy-tools; do
    if [[ -n $(podman  ps --filter "name=${podname}" --format "{{.Names}}") ]]; then
        echo "stop ${podname}"
        podman stop ${podname} 
    fi
done

if virsh net-info bmh >/dev/null 2>&1; then
    echo "delete libvirt network bmh"
    virsh net-destroy bmh >/dev/null 2>&1 || true
    virsh net-undefine bmh
fi

