#!/usr/bin/env python3
import os
import argparse
import paramiko
import sys
import yaml
import re
import time
import xml.etree.ElementTree as ET
import subprocess
import enum


def run_command(command):
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True, text=True)
    return result.stdout.strip()

def ssh_and_run_command(ip_address, username, password, command):
    # if ip_address not provided, then run command locally
    if not ip_address:
        return run_command(command)

    # Set up the SSH client
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())

    try:
        # Connect to the server via SSH
        ssh.connect(ip_address, username=username, password=password)
        stdin, stdout, stderr = ssh.exec_command(command)

        # Capture output and errors
        output = stdout.read().decode().strip()
        error = stderr.read().decode().strip()

        if error:
            print(f"Error: {error}")
            sys.exit(1)

        return output

    except Exception as e:
        print(f"Failed to connect or run command: {e}")
        sys.exit(1)
    finally:
        ssh.close()

def get_all_vms(ip_address, username, password):
    command = "sudo virsh list --all --name"
    output = ssh_and_run_command(ip_address, username, password, command)
    return output

def delete_vm_with_name(ip_address, username, password, vm_name):
    commands = [
            f"sudo virsh destroy {vm_name} 2>/dev/null || true",
            f"sudo virsh undefine --domain {vm_name} --remove-all-storage --nvram  2>/dev/null || true"
            ]
    print(f"Delete domain '{vm_name}'")
    for command in commands:
        ssh_and_run_command(ip_address, username, password, command)
        time.sleep(0.1)

def mac_exist_on_bridge(xml_content, mac, bridge=None):
    """
    Return true if the named bridge has this mac address
    """
    root = ET.fromstring(xml_content)
    if bridge is not None:
        for interface in root.findall("./devices/interface"):
            interface_type = interface.get("type")
            if interface_type == "bridge":
                mac_elem = interface.find("mac")
                source_elem = interface.find("source")
                if mac_elem is not None and source_elem is not None:
                    if mac == mac_elem.get("address") and bridge == source_elem.get("bridge"):
                        return True
    else:
        for interface in root.findall("./devices/interface/mac"):
            if mac == interface.get("address"):
                return True
    return False


def delete_vm_with_mac(ip_address, username, password, bridge, mac):
    """
    Delete a VM with a mac address on specified bridge

    :param bridge: bridge name
    :mac: mac address that belongs to the VM
    """
    print(f"Search for VM with mac {mac} on bridge {bridge}")
    domains = get_all_vms(ip_address, username, password)
    for domain in domains.split("\n"):
        command = f"sudo virsh dumpxml {domain}"
        xml_output = ssh_and_run_command(ip_address, username, password, command)
        if mac_exist_on_bridge(xml_output, mac, bridge):
            print(f"found {domain} with mac {mac} on bridge {bridge}")
            delete_vm_with_name(ip_address, username, password, domain)
            break

def create_vm_and_get_uuid(ip_address, username, password, vm_name, mac, provision_mac="", extra_disk=False):
    """
    A function that uses ssh_and_run_command to start a VM and get its UUID.

    :param ip_address: IP address of the remote server.
    :param username: Username for SSH login.
    :param password: Password for SSH login.
    :param vm_name: The name of the virtual machine to start.
    :param mac: primary mac address
    :provision_mac: provision network mac
    :extra_disk: boolean, use extra disk
    :return: The UUID of the virtual machine.
    """
    delete_vm_with_mac(ip_address, username, password, "baremetal", mac)
    if provision_mac:
        delete_vm_with_mac(ip_address, username, password, "provision", provision_mac)
    extra = ""
    if provision_mac != "":
        extra += f"--network bridge=provision,mac={provision_mac}"
    if extra_disk:
        extra += f"--disk size=600,bus=scsi,sparse=yes"
    # Sequence of commands to destroy and start the VM
    commands = [
            f"sudo virt-install -n {vm_name} --pxe --os-variant=rhel8.0 --ram=16384 --vcpus=8 --network bridge=baremetal,mac={mac}  --disk size=600,bus=scsi,sparse=yes --check disk_size=off --noautoconsole --serial pty --graphics none {extra}"
            ]
    for command in commands:
        ssh_and_run_command(ip_address, username, password, command)
        time.sleep(0.1)

    # Command to get the VM's UUID
    uuid_command = f"sudo virsh domuuid {vm_name}"
    uuid_output = ssh_and_run_command(ip_address, username, password, uuid_command)

    print(f"Created VM '{vm_name}' with UUID: {uuid_output}")
    return uuid_output

def generate_provsion_mac(mac):
    """revert the last octect of a mac address"""
    octets = mac(":")
    last_octet_int = int(octets[5], 16)
    inverted_octet_int = ~last_octet_int & 0xFF
    inverted_octet_hex = format(inverted_octet_int, "02x")
    octets[5] = inverted_octet_hex
    inverted_mac = ":".join(octets)
    return inverted_mac

def replace_bmc_uuid(bmc_url, uuid):
    pattern = r'(redfish/v1/Systems).*'
    return re.sub(pattern, r'\1/' + uuid, bmc_url)

def update_sylva_values_yaml(ip_address, username, password, file_name, extra_disk=False, extra_int=False):
    print(f"Read yaml from {file_name}")
    with open(file_name, 'r') as f:
        data=yaml.safe_load(f)
    for node, v in data['cluster']['baremetal_hosts'].items():
        mac = v['bmh_spec']['bootMACAddress']
        provision_mac = ""
        if extra_int:
            provision_mac = generate_provsion_mac(mac)
        uuid = create_vm_and_get_uuid(ip_address, username, password, node, mac, provision_mac, extra_disk)
        pattern = r'(redfish/v1/Systems).*'
        v['bmh_spec']['bmc']['address'] = re.sub(pattern, r'\1/' + uuid, v['bmh_spec']['bmc']['address'])
    with open(file_name, 'w') as f:
        yaml.dump(data, f, default_flow_style=False)

def update_bmh_yaml(ip_address, username, password, file_name):
    print(f"Read yaml from {file_name}")
    try:
        with open(file_name, 'r') as f:
            data = list(yaml.safe_load_all(f))
        for entry in data:
            if entry['kind'] == 'BareMetalHost':
                mac_address = entry['spec']['bootMACAddress']
                name = entry['metadata']['name']
                uuid = create_vm_and_get_uuid(ip_address, username, password, name, mac_address)
                entry['spec']['bmc']['address'] = replace_bmc_uuid(entry['spec']['bmc']['address'], uuid)
        with open(file_name, 'w') as f:
             yaml.dump(data, f, default_flow_style=False)       
    except Exception as e:
       print(f"Failed to handle {file_name}: {e}") 

class InputType(enum.Enum):
    SYLVA = "SYLVA"
    BMH = "BMH"

def yaml_type(value):
    try:
        return InputType(value.upper())
    except ValueError:
        raise argparse.ArgumentTypeError(f"Invalid yaml type: {value}")

def main():
    parser = argparse.ArgumentParser(description="Start VM on a remote host and update yaml file under a destination directory")
    parser.add_argument("--ip", help="The IP address of the remote host to SSH into.", default="192.168.222.1")
    parser.add_argument("-u", "--username", help="SSH username", default="root")
    parser.add_argument("-p", "--password", help="SSH password", default="redhat")
    parser.add_argument("-d", "--dir", help="Diretory to update the values.yaml")
    parser.add_argument("--extra-disk", action='store_true', help="Add extra disk to VM")
    parser.add_argument("--extra-int", action='store_true', help="Add extra interface to VM")
    parser.add_argument("--type", help="yaml file type (SYLVA, BMH)", type=yaml_type, default=InputType.SYLVA)
    args = parser.parse_args()
    if args.type == InputType.SYLVA:
        update_sylva_values_yaml(args.ip, args.username, args.password, f"{args.dir}/values.yaml", args.extra_disk, args.extra_int)
    elif args.type == InputType.BMH:
        for filename in os.listdir(args.dir):
            if filename.endswith(".yaml"):
                update_bmh_yaml(args.ip, args.username, args.password, os.path.join(args.dir, filename))

if __name__ == "__main__":
    main()
