#/bin/bash
set -eu
set -o pipefail

source $(dirname $0)/common.sh

if [[ $# -lt 1 ]]; then
    echo "Need at least 1 argument: stop or start"
    exit 1
fi

if [[ $1 == "start" ]]; then
    # default number of VM to start is 1
    vmnumber=1
    if [ $# -gt 1 ]; then
        if ! [[ "$2" =~ ^[1-9]$ ]]; then
	    echo "Error: VM number must be between 1 and 9"
	    exit 1
	fi
        vmnumber=$2
    fi
    for ((i=1; i<=vmnumber; i++)); do
	name="${bmh_name_prefix}$i"
	mac="${mac_prefix}$i"
	echo "Create VM BMH ${name} with mac ${mac}"
	create_vm ${name} ${mac}
    done
    while IFS= read -r systemid; do
	name=$(curl -s 192.168.222.1:8000${systemid} | jq -r '.Name')
	mac=$(get_mac_from_systemid ${systemid})
        echo "start BMH with systemid: ${systemid} ..."
        sed -r "s%redfish-virtualmedia.*REPLACE_ID%redfish-virtualmedia+http://192.168.222.1:8000${systemid}%" $(dirname $0)/vm.yaml | sed -r "s/REPLACE_NAME/${name}/g" | sed -r "s/REPLACE_MAC/${mac}/g" | kubectl apply -f -
        echo "done"
    done < <(list_systemid_with_mac_prefix)
    exit 0

elif [[ $1 == "stop" ]]; then
    while IFS= read -r systemid; do
	echo "stop VM BMH with systemid: ${systemid} ... "
	name=$(curl -s 192.168.222.1:8000${systemid} | jq -r '.Name')
	mac=$(get_mac_from_systemid ${systemid})
        sed -r "s%redfish-virtualmedia.*REPLACE_ID%redfish-virtualmedia+http://192.168.222.1:8000${systemid}%" $(dirname $0)/vm.yaml | sed -r "s/REPLACE_NAME/${name}/g" | sed -r "s/REPLACE_MAC/${mac}/g" | kubectl delete -f - || true
	if [[ $# -gt 1 && "$2" == '-r' ]]; then
	    echo "delete VM ${name}"
            virsh destroy ${name} 2>/dev/null || true
            virsh undefine --domain ${name} --remove-all-storage --nvram 2>/dev/null || true
        fi
    	echo "done"
    done < <(list_systemid_with_mac_prefix)
    exit 0
fi
