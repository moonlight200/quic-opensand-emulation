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

	export SCRIPT_VERSION="manual"
	export SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
	set -a
	source "${SCRIPT_DIR}/env.sh"
	set +a
	source "${SCRIPT_DIR}/teardown-opensand.sh"
	source "${SCRIPT_DIR}/teardown-namespaces.sh"

	osnd_teardown "$@"
fi
