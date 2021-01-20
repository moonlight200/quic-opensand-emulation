#!/bin/bash

# _teardown()
# Teardown the entire emulation environment.
function _teardown() {
	declare -F log > /dev/null || function log() {
		local level="$1"
		local msg="$2"

		echo "[$level] $msg"
	}

	log I "Tearing down emulation environment"
	_teardown_opensand
	_teardown_namespaces
	log D "Environment teared down"
}

# If script is executed directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	_teardown "$@"
fi
