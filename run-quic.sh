#!/bin/bash

# _osnd_quic_measure(output_dir, run_id, cc, measure_secs, timeout, server_ip)
function _osnd_quic_measure() {
    local output_dir="$1"
    local run_id="$2"
    local cc="$3"
    local measure_secs="$4"
    local timeout="$5"
    local server_ip="$6"

    log I "Running qperf client"
    sudo timeout --foreground $timeout ip netns exec osnd-cl ${QPERF_BIN} -c ${server_ip} --cc ${cc} -t ${measure_secs} > "${output_dir}/${run_id}_client.txt"
    local status=$?

	# Check for error, report if any
	if [ "$status" -ne 0 ]; then
		local emsg="qperf exited with status $status"
		if [ "$status" -eq 124 ]; then
			emsg="${emsg} (timeout)"
		fi
		log E "$emsg"
	fi
	log D "qperf done"

	return $status
}

# _osnd_quic_server_start(output_dir, run_id, cc)
function _osnd_quic_server_start() {
    local output_dir="$1"
    local run_id="$2"
    local cc="$3"

	log D "Starting qperf server"
	sudo ip netns exec osnd-sv killall qperf -q
	tmux -L ${TMUX_SOCKET} new-session -s qperf-server -d "sudo ip netns exec osnd-sv bash"
	sleep $TMUX_INIT_WAIT
	tmux -L ${TMUX_SOCKET} send-keys -t qperf-server \
		"${QPERF_BIN} -s --tls-cert ${QPERF_CRT} --tls-key ${QPERF_KEY} --cc ${cc} --listen-addr ${GW_LAN_SERVER_IP%%/*} > '${output_dir}/${run_id}_server.txt'" \
		Enter
}

# _osnd_quic_server_stop()
function _osnd_quic_server_stop() {
	log D "Stopping qperf server"
	tmux -L ${TMUX_SOCKET} send-keys -t qperf-server C-c
	sleep $CMD_SHUTDOWN_WAIT
	tmux -L ${TMUX_SOCKET} send-keys -t qperf-server C-d
	sleep $CMD_SHUTDOWN_WAIT
	sudo ip netns exec osnd-sv killall qperf -q
	tmux -L ${TMUX_SOCKET} kill-session -t qperf > /dev/null 2>&1
}

# _osnd_quic_proxy_start(output_dir, run_id, cc)
function _osnd_quic_proxy_start() {
    local output_dir="$1"
    local run_id="$2"
    local cc="$3"

	# TODO start quic proxy
    log E "Cannot start QUIC proxy, not yet implemented"
}

function _osnd_quic_proxy_stop() {
	# TODO stop quic proxy
    log E "Cannot stop QUIC proxy, not yet implemented"
}

# _osnd_run_quic(output_dir, pep=false, timing=false, run_cnt=5)
function _osnd_run_quic() {
	local output_dir="$1"
	local pep=${2:-false}
	local timing=${3:-false}
	local run_cnt=${4:-5}

	local base_run_id="quic"
	local name_ext=""
	local measure_secs=30
	local timeout=45
	local server_ip="${GW_LAN_SERVER_IP%%/*}"

	if [[ "$pep" == true ]]; then
		base_run_id="${base_run_id}_pep"
		name_ext="${name_ext} (PEP)"
		# TODO update server_ip to proxy ip
	fi
	if [[ "$timing" == true ]]; then
		base_run_id="${base_run_id}_ttfb"
		name_ext="${name_ext} timing"
		measure_secs=1
		timeout=8
	fi

	for i in $( seq $run_cnt ); do
		log I "QUIC${name_ext} run $i/$run_cnt"
		local run_id="${base_run_id}_$i"

		# Environment
		osnd_setup
		sleep $MEASURE_WAIT

		# Server
		_osnd_quic_server_start "$output_dir" "$run_id" "reno"
		sleep $MEASURE_WAIT

		# Proxy
		if [[ "$pep" == true ]]; then
			_osnd_quic_proxy_start "$output_dir" "$run_id" "reno"
			sleep $MEASURE_WAIT
		fi

		# Client
		_osnd_quic_measure "$output_dir" "$run_id" "reno" $measure_secs $timeout "$server_ip"

		# Cleanup
		if [[ "$pep" == true ]]; then
			_osnd_quic_proxy_stop
		fi
		_osnd_quic_server_stop
		osnd_teardown

		sleep $RUN_WAIT
	done
}

# osnd_run_quic_goodput(output_dir, pep=false, run_cnt=4)
# Run QUIC goodput measurements on the emulation environment
function osnd_run_quic_goodput() {
	local output_dir="$1"
	local pep=${2:-false}
	local run_cnt=${3:-4}

	_osnd_run_quic "$output_dir" $pep false $run_cnt
}

# osnd_run_quic_ttfb(output_dir, pep=false, run_cnt=12)
# Run QUIC timing measurements on the emulation environment
function osnd_run_quic_timing() {
	local output_dir="$1"
	local pep=${2:-false}
	local run_cnt=${3:-12}

	_osnd_run_quic "$output_dir" $pep true $run_cnt
}

# If script is executed directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	declare -F log >/dev/null || function log() {
		local level="$1"
		local msg="$2"

		echo "[$level] $msg"
	}

	if [[ "$@" ]]; then
		osnd_run_quic_goodput "$@"
	else
		osnd_run_quic_goodput "." 0 1
	fi
fi
