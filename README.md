# ansible-cluster-playground
Ansible Playbook to install an IoT devices cluster used as a playground.

The following technologies/tools are installed:
* pi-hole
* grafana
* prometheus

Plan for the other tools to be installed:
* k3s

## IoT Devices

### Requirements
- install raspberry pi devices using the script in setup directory
- rename default user (alarm for Archlinux) to user
- setup keyring for Archlinux
- setup SSH on the devices (pub key auth allowed), ssh-copy-id, ...
- install sudo and python3 on the devices

The rest of the devices configuration is done using the playbook.

### Jetson Nano 2g (jetsonnano2g)

* pi-hole
* prometheus
* grafana
* k3s-master

### Raspberry Pi 4 Model B 8 GB (rpi4b8g1)

* k3s-node

### Raspberry Pi 4 Model B 8 GB (rpi4b8g2)

* k3s-node

### Raspberry Pi 4 Model B 8 GB (rpi4b8g3)

* k3s-node

## Install

### Vault
Create vault and add the key-value

user_become_pass: "user password of the devices"

All devices have the same basic user called "user" with the password in the vault.

### Requirements

```shell
python3 -m venv venv
source venv/bin/activate
pip3 install -r requirements.txt
```

### Run

```shell
./run.sh all
```