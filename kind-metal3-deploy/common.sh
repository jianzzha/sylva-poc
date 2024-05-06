# new VM mac will be ${mac_prefix}'x', x: 1, 2, 3, 4, ..., 9
mac_prefix="00:60:2f:31:81:0"

# new VM name will be ${bmh_name_prefix}'x, x: 1, 2, 3, 4, ..., 9
bmh_name_prefix="bmh-vm-0"

function lower_case_mac {
    # convert mac address into lower case
    # input: $1 - mac address
    if [ $# -gt 0 ]; then
        input="$1"
    else
        input=$(cat -)
    fi
    echo $input | awk '{print tolower($0)}'
}

function get_name_from_systemid {
    # input: $1 - systemid, something like /redfish/v1/Systems/<ID>
    curl -s 192.168.222.1:8000$1 | jq -r '.Name'
}

function get_mac_from_systemid {
    # input: $1 - systemid
    # output: lower case mac address
    curl -s 192.168.222.1:8000$1/EthernetInterfaces | jq -r '.Members[]."@odata.id"' | grep -oE '[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}' | lower_case_mac
}

function delete_vms_with_mac_prefix {
    # delete all VMs which contain the mac_prefix
    # use lower case for compare
    prefix=$(lower_case_mac ${mac_prefix})
    for systemid in $(curl -s 192.168.222.1:8000/redfish/v1/Systems | jq -r '.Members[]."@odata.id"'); do
	mac=$(get_mac_from_systemid ${systemid})
	if [[ "${mac}" == "${prefix}"* ]]; then
            name=$(get_name_from_systemid ${systemid})
            virsh destroy ${name} 2>/dev/null || true
	    virsh undefine --domain ${name} --remove-all-storage --nvram 2>/dev/null || true
	fi
    done
}

function list_systemid_with_mac_prefix {
    prefix=$(lower_case_mac ${mac_prefix})
    for systemid in $(curl -s 192.168.222.1:8000/redfish/v1/Systems | jq -r '.Members[]."@odata.id"'); do
        mac=$(get_mac_from_systemid ${systemid})
        if [[ "${mac}" == "${prefix}"* ]]; then
	    echo ${systemid}
	fi
    done
}    

function create_vm {
    # input: $1 - vm name; $2 - vm mac address
    name=$1
    mac=$(lower_case_mac $2)
    if virsh dominfo "${name}" >/dev/null 2>&1; then
        # this domain alreay exists, check its mac address
	systemid="/redfish/v1/Systems/$(virsh domuuid ${name})"
	existing_mac=$(get_mac_from_systemid ${systemid})
        if [[ "${existing_mac}" != "${mac}" ]]; then
	    echo "VM $name} already exists with mac address ${existing_mac}, delete this VM before recreate"
            virsh destroy "${name}" 2>/dev/null || true
            virsh undefine --domain "${name}" --remove-all-storage --nvram 2>/dev/null || true
	else
	    echo "VM $name} already exists with mac address ${mac}, skip"
	    return 0
	fi
    fi
    virt-install -n "${name}" --pxe --os-variant=rhel8.0 --ram=16384 --vcpus=8 --network bridge=baremetal,mac="${mac}" --disk size=120,bus=scsi,sparse=yes --check disk_size=off --noautoconsole --serial pty --graphics none
}


