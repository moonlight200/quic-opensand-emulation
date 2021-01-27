#!/bin/bash

# _osnd_iperf_measure(output_dir, run_id, measure_secs, timeout)
function _osnd_iperf_measure() {
	local output_dir="$1"
	local run_id="$2"
	local measure_secs="$3"
	local timeout="$4"

	log I "Running iperf client"
	sudo timeout --foreground $timeout ip netns exec osnd-cl iperf3 -c ${GW_LAN_SERVER_IP%%/*} -p 5201 -t $measure_secs -R -J --logfile "${output_dir}/${run_id}_client.json"
	status=$?

	# Check for error, report if any
	if [ "$status" -ne 0 ]; then
		emsg="iperf client exited with status $status"
		if [ "$status" -eq 124 ]; then
			emsg="${emsg} (timeout)"
		fi
		log E "$emsg"
	fi
	log D "iperf done"

	return $status
}

# _osnd_curl_measure(output_dir, run_id, timeout)
function _osnd_curl_measure() {
	local output_dir="$1"
	local run_id="$2"
	local timeout="$3"

	log I "Running curl"
	sudo timeout --foreground $timeout ip netns exec osnd-cl curl -o /dev/null --insecure -s -v --write-out "established=%{time_connect}\nttfb=%{time_starttransfer}\n" http://${GW_LAN_SERVER_IP%%/*}/ >"${output_dir}/${run_id}_client.txt" 2>&1
	status=$?

	# Check for error, report if any
	if [ "$status" -ne 0 ]; then
		emsg="curl exited with status $status"
		if [ "$status" -eq 124 ]; then
			emsg="${emsg} (timeout)"
		fi
		log E "$emsg"
	fi
	log D "curl done"

	return $status
}

# _osnd_iperf_server_start(output_dir, run_id)
function _osnd_iperf_server_start() {
	local output_dir="$1"
	local run_id="$2"

	log I "Starting iperf server"
	sudo ip netns exec osnd-sv killall iperf3 -q
	tmux -L ${TMUX_SOCKET} new-session -s iperf -d "sudo ip netns exec osnd-sv bash"
	sleep $TMUX_INIT_WAIT
	tmux -L ${TMUX_SOCKET} send-keys -t iperf "iperf3 -s -p 5201 -J --logfile '${output_dir}/${run_id}_server.json'" Enter
}

# _osnd_iperf_server_stop()
function _osnd_iperf_server_stop() {
	log I "Stopping iperf server"
	tmux -L ${TMUX_SOCKET} send-keys -t iperf C-c
	sleep $CMD_SHUTDOWN_WAIT
	tmux -L ${TMUX_SOCKET} send-keys -t iperf C-d
	sleep $CMD_SHUTDOWN_WAIT
	sudo ip netns exec osnd-sv killall iperf3 -q
	tmux -L ${TMUX_SOCKET} kill-session -t iperf >/dev/null 2>&1
}

# _osnd_nginx_server_start(output_dir, run_id)
function _osnd_nginx_server_start() {
	local output_dir="$1"
	local run_id="$2"

	log I "Starting nginx web server"
	sudo ip netns exec osnd-sv killall nginx -q
	tmux -L ${TMUX_SOCKET} new-session -s nginx -d "sudo ip netns exec osnd-sv bash"
	sleep $TMUX_INIT_WAIT
	tmux -L ${TMUX_SOCKET} send-keys -t nginx "nginx -c '${NGINX_CONFIG}' 2>&1 > '${output_dir}/${run_id}_server.log'" Enter
}

# _osnd_nginx_server_stop()
function _osnd_nginx_server_stop() {
	log I "Stopping nginx web server"
	tmux -L ${TMUX_SOCKET} send-keys -t nginx C-c
	sleep $CMD_SHUTDOWN_WAIT
	tmux -L ${TMUX_SOCKET} send-keys -t nginx C-d
	sleep $CMD_SHUTDOWN_WAIT
	sudo ip netns exec osnd-sv killall nginx -q
	tmux -L ${TMUX_SOCKET} kill-session -t nginx >/dev/null 2>&1
}

# _osnd_pepsal_proxies_start(output_dir, run_id)
function _osnd_pepsal_proxies_start() {
	local output_dir="$1"
	local run_id="$2"

	log I "Starting pepsal proxies"

	# Gateway proxy
	log D "Starting gateway proxy"
	tmux -L ${TMUX_SOCKET} new-session -s pepsal-gw -d "sudo ip netns exec osnd-gw bash"
	sleep $TMUX_INIT_WAIT
	# Route marked traffic to pepsal
	tmux -L ${TMUX_SOCKET} send-keys -t pepsal-gw "ip rule add fwmark 1 lookup 100" Enter
	tmux -L ${TMUX_SOCKET} send-keys -t pepsal-gw "ip route add local 0.0.0.0/0 dev lo table 100" Enter
	# Mark selected traffic for processing by pepsal
	tmux -L ${TMUX_SOCKET} send-keys -t pepsal-gw "iptables -t mangle -A PREROUTING -i br-gw -p tcp -j TPROXY --on-port 5000 --tproxy-mark 1" Enter
	tmux -L ${TMUX_SOCKET} send-keys -t pepsal-gw "iptables -t mangle -A PREROUTING -i gw0 -p tcp -j TPROXY --on-port 5000 --tproxy-mark 1" Enter
	# Start pepsal
	tmux -L ${TMUX_SOCKET} send-keys -t pepsal-gw \
		"${PEPSAL_BIN} -v -p 5000 -l '${output_dir}/${run_id}_proxy_gw.txt'" \
		Enter

	# Satellite terminal proxy
	log D "Starting satellite terminal proxy"
	tmux -L ${TMUX_SOCKET} new-session -s pepsal-st -d "sudo ip netns exec osnd-st bash"
	sleep $TMUX_INIT_WAIT
	# Route marked traffic to pepsal
	tmux -L ${TMUX_SOCKET} send-keys -t pepsal-st "ip rule add fwmark 1 lookup 100" Enter
	tmux -L ${TMUX_SOCKET} send-keys -t pepsal-st "ip route add local 0.0.0.0/0 dev lo table 100" Enter
	# Mark selected traffic for processing by pepsal
	tmux -L ${TMUX_SOCKET} send-keys -t pepsal-st "iptables -t mangle -A PREROUTING -i br-st -p tcp -j TPROXY --on-port 5000 --tproxy-mark 1" Enter
	tmux -L ${TMUX_SOCKET} send-keys -t pepsal-st "iptables -t mangle -A PREROUTING -i st0 -p tcp -j TPROXY --on-port 5000 --tproxy-mark 1" Enter
	# Start pepsal
	tmux -L ${TMUX_SOCKET} send-keys -t pepsal-st \
		"${PEPSAL_BIN} -v -p 5000 -l '${output_dir}/${run_id}_proxy_st.txt'" \
		Enter
}

# _osnd_pepsal_proxies_stop()
function _osnd_pepsal_proxies_stop() {
	log I "Stopping pepsal proxies"

	# Gateway proxy
	log D "Stopping gateway proxy"
	tmux -L ${TMUX_SOCKET} send-keys -t pepsal-gw C-c
	sleep $CMD_SHUTDOWN_WAIT
	tmux -L ${TMUX_SOCKET} send-keys -t pepsal-gw C-d
	sleep $CMD_SHUTDOWN_WAIT
	sudo ip netns exec osnd-gw killall $( basename $PEPSAL_BIN ) -q
	tmux -L ${TMUX_SOCKET} kill-session -t pepsal-gw >/dev/null 2>&1

	# Satellite terminal proxy
	log D "Stopping satellite terminal proxy"
	tmux -L ${TMUX_SOCKET} send-keys -t pepsal-st C-c
	sleep $CMD_SHUTDOWN_WAIT
	tmux -L ${TMUX_SOCKET} send-keys -t pepsal-st C-d
	sleep $CMD_SHUTDOWN_WAIT
	sudo ip netns exec osnd-st killall $( basename $PEPSAL_BIN ) -q
	tmux -L ${TMUX_SOCKET} kill-session -t pepsal-st >/dev/null 2>&1
}

# osnd_run_tcp_goodput(output_dir, pep=false, run_cnt=4)
# Run TCP goodput measurements on the emulation environment
function osnd_run_tcp_goodput() {
	local output_dir="$1"
	local pep=${2:-false}
	local run_cnt=${3:-4}

	local base_run_id="tcp"
	local name_ext=""

	if [[ "$pep" == true ]]; then
		base_run_id="${base_run_id}_pep"
		name_ext="${name_ext} (PEP)"
	fi

	for i in $(seq $run_cnt); do
		log I "TCP${name_ext} run $i/$run_cnt"
		local run_id="${base_run_id}_$i"

		# Environment
		osnd_setup
		sleep $MEASURE_WAIT

		# Server
		_osnd_iperf_server_start "$output_dir" "$run_id"
		sleep $MEASURE_WAIT

		# Proxy
		if [[ "$pep" == true ]]; then
			_osnd_pepsal_proxies_start "$output_dir" "$run_id"
			sleep $MEASURE_WAIT
		fi

		# Client
		_osnd_iperf_measure "$output_dir" "$run_id" 30 45

		# Cleanup
		if [[ "$pep" == true ]]; then
			_osnd_pepsal_proxies_stop
		fi
		_osnd_iperf_server_stop
		osnd_teardown

		sleep $RUN_WAIT
	done
}

# osnd_run_tcp_ttfb(output_dir, pep=false, run_cnt=12)
# Run TCP timing measurements on the emulation environment
function osnd_run_tcp_timing() {
	local output_dir="$1"
	local pep=${2:-false}
	local run_cnt=${3:-12}

	local base_run_id="tcp"
	local name_ext=""

	if [[ "$pep" == true ]]; then
		base_run_id="${base_run_id}_pep"
		name_ext="${name_ext} (PEP)"
	fi
	base_run_id="${base_run_id}_ttfb"

	for i in $(seq $run_cnt); do
		log I "TCP${name_ext} timing run $i/$run_cnt"
		local run_id="${base_run_id}_$i"

		# Environment
		osnd_setup
		sleep $MEASURE_WAIT

		# Server
		_osnd_nginx_server_start "$output_dir" "$run_id"
		sleep $MEASURE_WAIT

		# Proxy
		if [[ "$pep" == true ]]; then
			_osnd_pepsal_proxies_start "$output_dir" "$run_id"
			sleep $MEASURE_WAIT
		fi

		# Client
		_osnd_curl_measure "$output_dir" "$run_id" 3

		# Cleanup
		if [[ "$pep" == true ]]; then
			_osnd_pepsal_proxies_stop
		fi
		_osnd_nginx_server_stop
		osnd_teardown

		sleep $RUN_WAIT
	done
}

# If script is executed directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	declare -F log >/dev/null || function log() {
		local level="$1"
		local msg="$2"

		echo "[$level] $msg"
	}

	if [[ "$@" ]]; then
		osnd_run_tcp_goodput "$@"
	else
		osnd_run_tcp_goodput "." 0 1
	fi
fi
