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

	osnd_setup "$@"
fi
