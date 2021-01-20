#!/bin/bash

# _run_ping_single(output_dir)
# Run a single ping measurement and place the results in output_dir.
function _run_ping_single() {
	local output_dir="$1"
	local max_secs=120

	log I "Running ping"
	sudo timeout --foreground $max_secs ip netns exec osnd-cl ping -n -W 8 -c 10000 -l 100 -i 0.01 ${GW_LAN_SERVER_IP%%/*} > "${output_dir}/ping.txt"
	local status=$?

	# Check for error, report if any
	if [ "$status" -ne 0 ]; then
		local emsg="ping exited with status $status"
		if [ "$status" -eq 124 ]; then
			emsg="${emsg} (timeout)"
		fi
		log E "$emsg"
	fi
	log D "ping done"

	return $status
}

# _run_ping(output_dir)
# Run all ping measurements and place the results in output_dir.
function _run_ping() {
	local output_dir="$1"

	declare -F log > /dev/null || function log() {
		local level="$1"
		local msg="$2"

		echo "[$level] $msg"
	}

	log I "ping run 1/1"
	_run_ping_single "$output_dir"

	sleep 3
}

# If script is executed directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	if [[ "$@" ]]; then
		_run_ping "$@"
	else
		_run_ping "."
	fi
fi
