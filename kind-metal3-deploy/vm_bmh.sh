#/usr/bin/bash
set -eu
set -o pipefail

systemid=$(curl -s 192.168.222.1:8000/redfish/v1/Systems | jq -r '.Members[0]."@odata.id"')

if [[ -n "${systemid}" ]]; then
    echo "found a VM with redfish systemid: ${systemid}"
else
    echo "failed to find redfish systemid"
    exit 1
fi

if [[ ${BASH_ARGV[0]} == "start" ]]; then
    echo "starting VM BMH..."
    sed -r "s%redfish-virtualmedia.*REPLACE_ID%redfish-virtualmedia+http://192.168.222.1:8000${systemid}%" $(dirname $0)/vm.yaml | kubectl apply -f -
    echo "done"
    exit 0
fi

if [[ ${BASH_ARGV[0]} == "stop" ]]; then
    echo "stop VM BMH..."
    sed -r "s%redfish-virtualmedia.*REPLACE_ID%redfish-virtualmedia+http://192.168.222.1:8000${systemid}%" $(dirname $0)/vm.yaml | kubectl delete -f -
    echo "done"
    exit 0
fi
