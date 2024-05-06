#!/bin/bash
set -eu
set -o pipefail

echo "start libvirt network bmh"
virsh net-define $(dirname $0)/libvirt/net/bmh.xml
virsh net-start bmh

echo "starting sushy emulator pod"
podman run --name sushy-tools --rm --network host --privileged -d \
  -v /var/run/libvirt:/var/run/libvirt:z \
  -v "$(dirname $0)/sushy-tools.conf:/etc/sushy/sushy-emulator.conf:z" \
  -e SUSHY_EMULATOR_CONFIG=/etc/sushy/sushy-emulator.conf \
  quay.io/metal3-io/sushy-tools:latest sushy-emulator

