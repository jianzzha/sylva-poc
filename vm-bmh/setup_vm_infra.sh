#!/bin/bash
set -eu
set -o pipefail

echo "setup baremetal interface"
nmcli con down baremetal 2>/dev/null || true
nmcli con del baremetal 2>/dev/null || true
nmcli con add type bridge ifname baremetal con-name baremetal ipv4.method manual ipv4.addr 192.168.222.1/24 ipv4.dns 192.168.222.1 ipv4.dns-priority 10 autoconnect yes bridge.stp no
nmcli con reload baremetal
nmcli con up baremetal

echo "Add MASQUERADE rules on baremetal"
EXT_IF=$(ip route get 1 | grep -oP 'dev \K\S+')
if [[ -n "${EXT_IF}" ]]; then
    sudo iptables -t nat -A POSTROUTING -s 192.168.222.0/24 ! -d 192.168.222.0/24 -o ${EXT_IF} -j MASQUERADE
fi

echo "starting poseidon-dnsmasq pod"
podman run --name poseidon-dnsmasq --rm -d --net=host --privileged \
           -v $(dirname $0)/dnsmasq.conf:/etc/dnsmasq.conf \
	   quay.io/poseidon/dnsmasq --conf-file=/etc/dnsmasq.conf -d

echo "starting sushy emulator pod"
podman run --name sushy-tools --rm --network host -d \
  -v /var/run/libvirt:/var/run/libvirt \
  -v "$(dirname $0)/sushy-tools.conf:/etc/sushy/sushy-emulator.conf" \
  -e SUSHY_EMULATOR_CONFIG=/etc/sushy/sushy-emulator.conf \
  quay.io/metal3-io/sushy-tools:latest sushy-emulator

echo "Delete VM bmh-vm-01 and set up a new one"
virsh destroy bmh-vm-01 2>/dev/null || true
virsh undefine --domain bmh-vm-01 --remove-all-storage --nvram 2>/dev/null || true
virt-install -n bmh-vm-01 --pxe --os-variant=rhel8.0 --ram=16384 --vcpus=8 --network bridge=baremetal,mac=00:60:2f:31:81:01 --disk size=120,bus=scsi,sparse=yes --check disk_size=off --noautoconsole

