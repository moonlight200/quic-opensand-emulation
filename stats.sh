#!/bin/bash

# _osnd_stat_cpu()
function _osnd_stat_cpu() {
	cat /proc/loadavg | cut -d' ' -f 1
}

# _osnd_stat_ram()
function _osnd_stat_ram() {
	free -m | head -n 2 | tail -n 1 | awk -F' ' '{print $3}'
}

# _osnd_log_stats()
function _osnd_log_stats() {
	local cpu=$(_osnd_stat_cpu)
	local ram=$(_osnd_stat_ram)

	log S "CPU load (1m avg): ${cpu}, RAM usage: ${ram}MB"
}

# osnd_stats_every(seconds)
function osnd_stats_every() {
	local seconds=$1

	while true; do
		_osnd_log_stats
		sleep $seconds
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
		osnd_stats_every "$@"
	else
		osnd_stats_every 1
	fi
fi
