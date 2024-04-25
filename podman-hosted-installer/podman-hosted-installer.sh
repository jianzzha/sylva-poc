#!/bin/bash
set -eu
set -o pipefail

if [[ "$1" == "start" ]]; then
    export DEFAULT_IP_ADDRESS=$(ip route get 1 | grep -oP 'src \K\S+')
    if [[ -n "${DEFAULT_IP_ADDRESS}" ]]; then
        envsubst < $(dirname $0)/sno.yaml > /tmp/podman_play.yaml
        podman play kube /tmp/podman_play.yaml
    else
	echo "failed to find ip address for the default interface"
        exit 1
    fi	
elif [[ "$1" == "stop" ]]; then
    if [[ -f /tmp/podman_play.yaml ]]; then
        podman play kube --down /tmp/podman_play.yaml
    else
	podman play kube --down $(dirname $0)/sno.yaml
    fi
fi
