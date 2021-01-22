#!/bin/bash

# osnd_teardown()
# Teardown the entire emulation environment.
function osnd_teardown() {
	log I "Tearing down emulation environment"
	osnd_teardown_opensand
	osnd_teardown_namespaces
	log D "Environment teared down"
}

# If script is executed directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	declare -F log >/dev/null || function log() {
		local level="$1"
		local msg="$2"

		echo "[$level] $msg"
	}

	osnd_teardown "$@"
fi
