#!/usr/bin/env bash

set -eou pipefail

if [ -n "${1+set}" ]; then
    verbosity="$1"
else
    verbosity=""
fi

ansible-playbook -i hosts.yml --ask-become-pass site.yml ${verbosity}
