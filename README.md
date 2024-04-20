# ansible-cluster-playground
Ansible Playbook to install an Raspberry Pi and jetson nano devices cluster used as a playground.

Current setup:
- 4 raspberry pi 4 model B 8g: k3s workers
- 1 jetson nano 2g: pi-hole, nginx, docker registry
- 1 raspberry pi 5 8g: k3s leader, prometheus, grafana

## IoT Devices

### Requirements
- install raspberry pi devices using the script in setup directory
- follow post install instructions

The rest of the devices configuration is done using the playbook.

## Install

### Run

```shell
python3 -m venv venv
source venv/bin/activate
pip3 install -r requirements.txt
./run.sh
```
