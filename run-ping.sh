#!/bin/bash

# _osnd_ping_measure(output_dir, run_id)
# Run a single ping measurement and place the results in output_dir.
function _osnd_ping_measure() {
	local output_dir="$1"
	local run_id=$2
	local max_secs=120

	log I "Running ping"
	sudo timeout --foreground $max_secs ip netns exec osnd-cl ping -n -W 8 -c 10000 -l 100 -i 0.01 ${GW_LAN_SERVER_IP%%/*} >"${output_dir}/ping.txt"
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

# osnd_run_ping(output_dir, run_cnt=1)
# Run all ping measurements and place the results in output_dir.
function osnd_run_ping() {
	declare -F log >/dev/null || function log() {
		local level="$1"
		local msg="$2"

		echo "[$level] $msg"
	}

	local output_dir="$1"
	local run_cnt=${2:-1}

	for i in $( seq $run_cnt ); do
		log I "ping run $i/$run_cnt"
		osnd_setup
		sleep $MEASURE_WAIT
		_osnd_ping_measure "$output_dir" $i
		sleep $MEASURE_WAIT
		osnd_teardown
		sleep $RUN_WAIT
	done

	sleep 3
}

# If script is executed directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	if [[ "$@" ]]; then
		osnd_run_ping "$@"
	else
		osnd_run_ping "."
	fi
fi
