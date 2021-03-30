#!/bin/bash

# _osnd_quic_measure(output_dir, run_id, cc, tbs, qbs, ubs, measure_secs, timeout, server_ip)
function _osnd_quic_measure() {
	local output_dir="$1"
	local run_id="$2"
	local cc="$3"
	local tbs="$4"
	local qbs="$5"
	local ubs="$6"
	local measure_secs="$7"
	local timeout="$8"
	local server_ip="$9"

	local measure_opt="-t ${measure_secs}"
	if [[ "$measure_secs" -lt 0 ]]; then
		measure_opt="-e"
	fi

	log I "Running qperf client"
	sudo timeout --foreground $timeout ip netns exec osnd-cl ${QPERF_BIN} -c ${server_ip} -p 18080 --cc ${cc} -i ${REPORT_INTERVAL} -b ${tbs} -q ${qbs} -u ${ubs} $measure_opt --print-raw >"${output_dir}/${run_id}_client.txt"
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

# _osnd_quic_server_start(output_dir, run_id, cc, tbs, qbs, ubs)
function _osnd_quic_server_start() {
	local output_dir="$1"
	local run_id="$2"
	local cc="$3"
	local tbs="$4"
	local qbs="$5"
	local ubs="$6"

	log I "Starting qperf server"
	sudo ip netns exec osnd-sv killall qperf -q
	tmux -L ${TMUX_SOCKET} new-session -s qperf-server -d "sudo ip netns exec osnd-sv bash"
	sleep $TMUX_INIT_WAIT
	tmux -L ${TMUX_SOCKET} send-keys -t qperf-server \
		"${QPERF_BIN} -s --tls-cert ${QPERF_CRT} --tls-key ${QPERF_KEY} --cc ${cc} -i ${REPORT_INTERVAL} -b ${tbs} -q ${qbs} -u ${ubs} --listen-addr ${SV_LAN_SERVER_IP%%/*} --listen-port 18080 --print-raw > '${output_dir}/${run_id}_server.txt' 2> >(awk '{print(\"E\", \"qperf-server:\", \$0)}' > ${OSND_TMP}/logging)" \
		Enter
}

# _osnd_quic_server_stop()
function _osnd_quic_server_stop() {
	log I "Stopping qperf server"

	tmux -L ${TMUX_SOCKET} send-keys -t qperf-server C-c
	sleep $CMD_SHUTDOWN_WAIT
	tmux -L ${TMUX_SOCKET} send-keys -t qperf-server C-d
	sleep $CMD_SHUTDOWN_WAIT
	sudo ip netns exec osnd-sv killall $(basename $QPERF_BIN) -q
	tmux -L ${TMUX_SOCKET} kill-session -t qperf-server >/dev/null 2>&1
}

# _osnd_quic_proxies_start(output_dir, run_id, cc_gw, cc_st, tbs_gw, tbs_st, qbs_gw, qbs_st, ubs_gw, ubs_st)
function _osnd_quic_proxies_start() {
	local output_dir="$1"
	local run_id="$2"
	local cc_gw="$3"
	local cc_st="$4"
	local tbs_gw="$5"
	local tbs_st="$6"
	local qbs_gw="$7"
	local qbs_st="$8"
	local ubs_gw="$9"
	local ubs_st="${10}"

	log I "Starting qperf proxies"

	# Gateway proxy
	log D "Starting gateway proxy"
	tmux -L ${TMUX_SOCKET} new-session -s qperf-proxy-gw -d "sudo ip netns exec osnd-gwp bash"
	sleep $TMUX_INIT_WAIT
	tmux -L ${TMUX_SOCKET} send-keys -t qperf-proxy-gw \
		"${QPERF_BIN} -P ${SV_LAN_SERVER_IP%%/*} -p 18080 --tls-cert ${QPERF_CRT} --tls-key ${QPERF_KEY} --cc ${cc_gw} -i ${REPORT_INTERVAL} -b ${tbs_gw} -q ${qbs_gw} -u ${ubs_gw} --listen-addr ${GW_LAN_PROXY_IP%%/*} --listen-port 18080 --print-raw > '${output_dir}/${run_id}_proxy_gw.txt' 2> >(awk '{print(\"E\", \"qperf-gw-proxy:\", \$0)}' > ${OSND_TMP}/logging)" \
		Enter

	# Satellite terminal proxy
	log D "Starting satellite terminal proxy"
	tmux -L ${TMUX_SOCKET} new-session -s qperf-proxy-st -d "sudo ip netns exec osnd-stp bash"
	sleep $TMUX_INIT_WAIT
	tmux -L ${TMUX_SOCKET} send-keys -t qperf-proxy-st \
		"${QPERF_BIN} -P ${GW_LAN_PROXY_IP%%/*} -p 18080 --tls-cert ${QPERF_CRT} --tls-key ${QPERF_KEY} --cc ${cc_st} -i ${REPORT_INTERVAL} -b ${tbs_st} -q ${qbs_st} -u ${ubs_st} --listen-addr ${CL_LAN_ROUTER_IP%%/*} --listen-port 18080 --print-raw > '${output_dir}/${run_id}_proxy_st.txt' 2> >(awk '{print(\"E\", \"qperf-st-proxy:\", \$0)}' > ${OSND_TMP}/logging)" \
		Enter
}

# _osnd_quic_proxies_stop()
function _osnd_quic_proxies_stop() {
	log I "Stopping qperf proxies"

	# Gateway proxy
	log D "Stopping gateway proxy"
	tmux -L ${TMUX_SOCKET} send-keys -t qperf-proxy-gw C-c
	sleep $CMD_SHUTDOWN_WAIT
	tmux -L ${TMUX_SOCKET} send-keys -t qperf-proxy-gw C-d
	sleep $CMD_SHUTDOWN_WAIT
	sudo ip netns exec osnd-gw killall $(basename $QPERF_BIN) -q
	tmux -L ${TMUX_SOCKET} kill-session -t qperf-proxy-gw >/dev/null 2>&1

	# Satellite terminal proxy
	log D "Stopping satellite terminal proxy"
	tmux -L ${TMUX_SOCKET} send-keys -t qperf-proxy-st C-c
	sleep $CMD_SHUTDOWN_WAIT
	tmux -L ${TMUX_SOCKET} send-keys -t qperf-proxy-st C-d
	sleep $CMD_SHUTDOWN_WAIT
	sudo ip netns exec osnd-st killall $(basename $QPERF_BIN) -q
	tmux -L ${TMUX_SOCKET} kill-session -t qperf-proxy-st >/dev/null 2>&1
}

# _osnd_measure_quic(env_config_name, output_dir, pep=false, timing=false, run_cnt=5)
function _osnd_measure_quic() {
	local env_config_name=$1
	local output_dir="$2"
	local pep=${3:-false}
	local timing=${4:-false}
	local run_cnt=${5:-5}

	local -n env_config_ref=$env_config_name
	local base_run_id="quic"
	local name_ext=""
	local measure_secs=$MEASURE_TIME
	local timeout=$(echo "${MEASURE_TIME} * 1.1" | bc -l)
	local server_ip="${SV_LAN_SERVER_IP%%/*}"

	if [[ "$pep" == true ]]; then
		base_run_id="${base_run_id}_pep"
		name_ext="${name_ext} (PEP)"
		server_ip="${CL_LAN_ROUTER_IP%%/*}"
	fi
	if [[ "$timing" == true ]]; then
		base_run_id="${base_run_id}_ttfb"
		name_ext="${name_ext} timing"
		measure_secs=-1
		timeout=4
	fi

	for i in $(seq $run_cnt); do
		log I "QUIC${name_ext} run $i/$run_cnt"
		local run_id="${base_run_id}_$i"

		# Environment
		osnd_setup $env_config_name
		sleep $MEASURE_WAIT

		# Server
		_osnd_quic_server_start "$output_dir" "$run_id" "${env_config_ref['cc_sv']:-reno}" "${env_config_ref['tbs_sv']:-1M}" "${env_config_ref['qbs_sv']:-1M}" "${env_config_ref['ubs_sv']:-1M}"
		sleep $MEASURE_WAIT

		# Proxy
		if [[ "$pep" == true ]]; then
			_osnd_quic_proxies_start "$output_dir" "$run_id" "${env_config_ref['cc_gw']:-reno}" "${env_config_ref['cc_st']:-reno}" "${env_config_ref['tbs_gw']:-1M}" "${env_config_ref['tbs_st']:-1M}" "${env_config_ref['qbs_gw']:-1M}" "${env_config_ref['qbs_st']:-1M}" "${env_config_ref['ubs_gw']:-1M}" "${env_config_ref['ubs_st']:-1M}"
			sleep $MEASURE_WAIT
		fi

		# Client
		_osnd_quic_measure "$output_dir" "$run_id" "${env_config_ref['cc_cl']:-reno}" "${env_config_ref['tbs_cl']:-1M}" "${env_config_ref['qbs_cl']:-1M}" "${env_config_ref['ubs_cl']:-1M}" $measure_secs $timeout "$server_ip"
		sleep $MEASURE_GRACE

		# Cleanup
		if [[ "$pep" == true ]]; then
			_osnd_quic_proxies_stop
		fi
		_osnd_quic_server_stop
		osnd_teardown

		sleep $RUN_WAIT
	done
}

# osnd_run_quic_goodput(env_config_name, output_dir, pep=false, run_cnt=4)
# Run QUIC goodput measurements on the emulation environment
function osnd_measure_quic_goodput() {
	local env_config_name=$1
	local output_dir="$2"
	local pep=${3:-false}
	local run_cnt=${4:-4}

	_osnd_measure_quic $env_config_name "$output_dir" $pep false $run_cnt
}

# osnd_run_quic_ttfb(env_config_name, output_dir, pep=false, run_cnt=12)
# Run QUIC timing measurements on the emulation environment
function osnd_measure_quic_timing() {
	local env_config_name=$1
	local output_dir="$2"
	local pep=${3:-false}
	local run_cnt=${4:-12}

	_osnd_measure_quic $env_config_name "$output_dir" $pep true $run_cnt
}

# If script is executed directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	declare -F log >/dev/null || function log() {
		local level="$1"
		local msg="$2"

		echo "[$level] $msg"
	}
	declare -A env_config

	export SCRIPT_VERSION="manual"
	export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
	set -a
	source "${SCRIPT_DIR}/env.sh"
	set +a

	if [[ "$@" ]]; then
		osnd_measure_quic_goodput env_config "$@"
	else
		osnd_measure_quic_goodput env_config "." 0 1
	fi
fi
