#!/bin/bash

# _osnd_orbit_sat_delay(orbit)
function _osnd_orbit_sat_delay() {
	local orbit="$1"

	case "$orbit" in
	"GEO") echo 125 ;;
	"MEO") echo 55 ;;
	"LEO") echo 18 ;;
	*) echo 0 ;;
	esac
}

# _osnd_orbit_ground_delay(orbit)
function _osnd_orbit_ground_delay() {
	local orbit="$1"

	case "$orbit" in
	"GEO") echo 40 ;;
	"MEO") echo 60 ;;
	"LEO") echo 80 ;;
	*) echo 0 ;;
	esac
}

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
	sudo timeout --foreground $(echo "$seconds + 1" | bc -l) ip netns exec osnd-cl \
		ping -n -W 8 -c $(echo "$seconds * 100" | bc -l) -l 100 -i 0.01 ${SV_LAN_SERVER_IP%%/*} >/dev/null
}

# osnd_setup(scenario_config_ref)
# Setup the entire emulation environment.
function osnd_setup() {
	local -n scenario_config_ref="$1"
	# Extract associative array with defaults
	local cc_cl="${scenario_config_ref['cc_cl']:-reno}"
	local cc_st="${scenario_config_ref['cc_st']:-reno}"
	local cc_emu="${scenario_config_ref['cc_emu']:-reno}"
	local cc_gw="${scenario_config_ref['cc_gw']:-reno}"
	local cc_sv="${scenario_config_ref['cc_sv']:-reno}"
	local prime="${scenario_config_ref['prime']:-4}"
	local orbit="${scenario_config_ref['orbit']:-GEO}"
	local attenuation="${scenario_config_ref['attenuation']:-0}"
	local modulation_id="${scenario_config_ref['modulation_id']:-1}"

	local delay_sat="$(_osnd_orbit_sat_delay "$orbit")"
	local delay_ground="$(_osnd_orbit_ground_delay "$orbit")"

	log I "Setting up emulation environment"

	osnd_setup_namespaces "$delay_ground"
	_osnd_configure_cc "$cc_cl" "$cc_st" "$cc_emu" "$cc_gw" "$cc_sv"
	sleep 1
	osnd_setup_opensand "$delay_sat" "$attenuation" "$modulation_id"
	sleep 1
	if (( $(echo "$prime > 0" | bc -l) )); then
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
	declare -A scenario_config

	export SCRIPT_VERSION="manual"
	export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
	export OSND_TMP="$(mktemp -d --tmpdir opensand.XXXXXX)"
	set -a
	source "${SCRIPT_DIR}/env.sh"
	set +a
	source "${SCRIPT_DIR}/setup-opensand.sh"
	source "${SCRIPT_DIR}/setup-namespaces.sh"

	osnd_setup "$@" scenario_config
fi
