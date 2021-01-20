#!/bin/bash

# _setup()
# Setup the entire emulation environment.
function _setup() {
	declare -F log > /dev/null || function log() {
		local level="$1"
		local msg="$2"

		echo "[$level] $msg"
	}

	log I "Setting up emulation environment"
	_setup_namespaces
	sleep 1
	_setup_opensand
	sleep 1
	log D "Environment set up"
}

# If script is executed directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	_setup "$@"
fi
