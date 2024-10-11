#!/usr/bin/env python3
import argparse
import paramiko
import sys
import yaml
import re
import time

def ssh_and_run_command(ip_address, username, password, command):
    # Set up the SSH client
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())

    try:
        # Connect to the server via SSH
        print(f"Connecting to {ip_address}...")
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
    extra = ""
    if provision_mac != "":
        extra += f"--network bridge=provision,mac={provision_mac}"
    if extra_disk:
        extra += f"--disk size=600,bus=scsi,sparse=yes"
    # Sequence of commands to destroy and start the VM
    commands = [
            f"sudo virsh destroy {vm_name} 2>/dev/null || true",
            f"sudo virsh undefine --domain {vm_name} --remove-all-storage --nvram  2>/dev/null || true",
            f"sudo virt-install -n {vm_name} --pxe --os-variant=rhel8.0 --ram=16384 --vcpus=8 --network bridge=baremetal,mac={mac}  --disk size=600,bus=scsi,sparse=yes --check disk_size=off --noautoconsole --serial pty --graphics none {extra}"
            ]
    for command in commands:
        ssh_and_run_command(ip_address, username, password, command)
        time.sleep(0.5)

    # Command to get the VM's UUID
    uuid_command = f"sudo virsh domuuid {vm_name}"
    uuid_output = ssh_and_run_command(ip_address, username, password, uuid_command)

    print(f"VM '{vm_name}' UUID: {uuid_output}")
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

def generate_values_yaml(ip_address, username, password, file_name, extra_disk=False, extra_int=False):
    print(f"Read yaml from {file_name}")
    with open(file_name, 'r') as f:
        data=yaml.safe_load(f)
    for node, v in data['cluster']['baremetal_hosts'].items():
        mac = v['bmh_spec']['bootMACAddress']
        provision_mac = ""
        if extra_int:
            provision_mac = generate_provsion_mac(mac)
        uuid = create_vm_and_get_uuid(ip_address, username, password, node, mac, provision_mac, extra_disk)
        pattern = r'([a-f0-9\-]{36})'
        v['bmh_spec']['bmc']['address'] = re.sub(pattern, uuid, v['bmh_spec']['bmc']['address'])
    with open(file_name, 'w') as f:
        yaml.dump(data, f, default_flow_style=False)

def main():
    parser = argparse.ArgumentParser(description="Start VM on a remote host and update values.yaml under a destination directory")
    parser.add_argument("--ip", help="The IP address of the remote host to SSH into.", default="192.168.222.1")
    parser.add_argument("-u", "--username", help="SSH username", default="root")
    parser.add_argument("-p", "--password", help="SSH password", default="redhat")
    parser.add_argument("-d", "--dir", help="Diretory to update the values.yaml")
    parser.add_argument("--extra-disk", action='store_true', help="Add extra disk to VM")
    parser.add_argument("--extra-int", action='store_true', help="Add extra interface to VM")
    args = parser.parse_args()
    generate_values_yaml(args.ip, args.username, args.password, f"{args.dir}/values.yaml", args.extra_disk, args.extra_int)


if __name__ == "__main__":
    main()
