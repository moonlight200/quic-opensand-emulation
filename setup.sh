#!/bin/bash

# _osnd_configure_cc(cc_cl, cc_st, cc_emu, cc_gw, cc_sv)
# Configure congestion control algorithms
function _osnd_configure_cc() {
	local cc_cl="$1"
	local cc_st="$2"
	local cc_emu="$3"
	local cc_gw="$4"
	local cc_sv="$5"

	log D "Configuring congestion control algorithms"
	sudo ip netns exec osnd-cl sysctl -wq net.ipv4.tcp_congestion_control="$cc_cl"
	sudo ip netns exec osnd-stp sysctl -wq net.ipv4.tcp_congestion_control="$cc_st"
	sudo ip netns exec osnd-st sysctl -wq net.ipv4.tcp_congestion_control="$cc_emu"
	sudo ip netns exec osnd-emu sysctl -wq net.ipv4.tcp_congestion_control="$cc_emu"
	sudo ip netns exec osnd-sat sysctl -wq net.ipv4.tcp_congestion_control="$cc_emu"
	sudo ip netns exec osnd-gw sysctl -wq net.ipv4.tcp_congestion_control="$cc_emu"
	sudo ip netns exec osnd-gwp sysctl -wq net.ipv4.tcp_congestion_control="$cc_gw"
	sudo ip netns exec osnd-sv sysctl -wq net.ipv4.tcp_congestion_control="$cc_sv"
}

# _osnd_prime_env(seconds)
# Prime the environment with a few pings
function _osnd_prime_env() {
	local seconds=$1

	log D "Priming environment"
	sudo timeout --foreground $((seconds + 1)) ip netns exec osnd-cl \
		ping -n -W 8 -c $((seconds * 100)) -l 100 -i 0.01 ${SV_LAN_SERVER_IP%%/*} >/dev/null
}

# osnd_setup(env_config_ref)
# Setup the entire emulation environment.
function osnd_setup() {
	local -n env_config_ref="$1"
	# Extract associative array with defaults
	local cc_cl="${env_config_ref['cc_cl']:-reno}"
	local cc_st="${env_config_ref['cc_st']:-reno}"
	local cc_emu="${env_config_ref['cc_emu']:-reno}"
	local cc_gw="${env_config_ref['cc_gw']:-reno}"
	local cc_sv="${env_config_ref['cc_sv']:-reno}"
	local prime="${env_config_ref['prime']:-4}"
	local orbit="${env_config_ref['orbit']:-GEO}"
	local attenuation="${env_config_ref['attenuation']:-0}"
	local modulation_id="${env_config_ref['modulation_id']:-1}"

	log I "Setting up emulation environment"

	osnd_setup_namespaces
	_osnd_configure_cc "$cc_cl" "$cc_st" "$cc_emu" "$cc_gw" "$cc_sv"
	sleep 1
	osnd_setup_opensand "$orbit" "$attenuation" "$modulation_id"
	sleep 1
	if [[ "$prime" -gt 0 ]]; then
		_osnd_prime_env $prime
	fi

	log D "Environment set up"
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
	export OSND_TMP="$(mktemp -d --tmpdir opensand.XXXXXX)"
	set -a
	source "${SCRIPT_DIR}/env.sh"
	set +a
	source "${SCRIPT_DIR}/setup-opensand.sh"
	source "${SCRIPT_DIR}/setup-namespaces.sh"

	osnd_setup "$@" env_config
fi
