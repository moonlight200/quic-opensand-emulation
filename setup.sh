#!/bin/bash

# _setup()
# Setup the entire emulation environment.
function osnd_setup() {
	log I "Setting up emulation environment"
	osnd_setup_namespaces
	sleep 1
	osnd_setup_opensand
	sleep 1
	log D "Environment set up"
}

# If script is executed directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	declare -F log >/dev/null || function log() {
		local level="$1"
		local msg="$2"

		echo "[$level] $msg"
	}

	export SCRIPT_VERSION="manual"
	export SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
	set -a
	source "${SCRIPT_DIR}/env.sh"
	set +a
	source "${SCRIPT_DIR}/setup-opensand.sh"
	source "${SCRIPT_DIR}/setup-namespaces.sh"

	osnd_setup "$@"
fi
