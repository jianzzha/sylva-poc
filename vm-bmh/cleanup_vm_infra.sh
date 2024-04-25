#!/bin/bash
set -eu
set -o pipefail

echo "delete VM bmh-vm-01"
virsh destroy bmh-vm-01 2>/dev/null || true
virsh undefine --domain bmh-vm-01 --remove-all-storage --nvram 2>/dev/null || true

for podname in sushy-tools poseidon-dnsmasq; do
    if [[ -n $(podman  ps --filter "name=${podname}" --format "{{.Names}}") ]]; then
        echo "stop ${podname}"
        podman stop ${podname} 
    fi
done

echo "delete MASQUERADE rules on baremetal"
iptables -L POSTROUTING -t nat --line-numbers 2>/dev/null | awk '/MASQUERADE.*192.168.222.0.*!192.168.222.0/{print $1}' | tac | xargs -I {} iptables -t nat -D POSTROUTING {}

echo "delete baremetal interface"
nmcli con down baremetal 2>/dev/null || true
nmcli con del baremetal 2>/dev/null || true


