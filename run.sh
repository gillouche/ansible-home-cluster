#!/usr/bin/env bash

playbook=$1
verbosity=$2

if [ -z "${playbook}" ]; then
    echo "playbook name must be provided. Possible values: all, jetsonnano2g, rpi4b8g1, rpi4b8g2, rpi4b8g3"
    echo "Example: ./run.sh all"
    exit -1
fi

ansible-playbook -i hosts.yml --ask-vault-pass -e@vaulted_vars.yml playbook_${playbook}.yml ${verbosity}
