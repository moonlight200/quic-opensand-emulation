#!/bin/bash
set -o nounset
set -o errtrace
set -o functrace

export SCRIPT_VERSION="0.5-beta"
export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

set -o allexport
source "${SCRIPT_DIR}/env.sh"
set +o allexport

source "${SCRIPT_DIR}/setup.sh"
source "${SCRIPT_DIR}/setup-namespaces.sh"
source "${SCRIPT_DIR}/setup-opensand.sh"
source "${SCRIPT_DIR}/teardown.sh"
source "${SCRIPT_DIR}/teardown-namespaces.sh"
source "${SCRIPT_DIR}/teardown-opensand.sh"
source "${SCRIPT_DIR}/run-ping.sh"
source "${SCRIPT_DIR}/run-quic.sh"
source "${SCRIPT_DIR}/run-tcp.sh"
source "${SCRIPT_DIR}/stats.sh"

# log(level, message...)
# Log a message of the specified level to the output and the log file.
function log() {
	local level="$1"
	shift
	local msg="$@"

	if [[ "$msg" == "-" ]]; then
		# Log each line in stdin as separate log message
		while read -r err_line; do
			log $level "$err_line"
		done < <(cat -)
		return
	fi

	local log_time="$(date --rfc-3339=seconds)"
	local level_name="INFO"
	local level_color="\e[0m"
	local visible=true
	case $level in
	D | d)
		level_name="DEBUG"
		level_color="\e[2m"
		;;
	S | s)
		level_name="STAT"
		level_color="\e[34m"
		visible=$show_stats
		;;
	I | i)
		level_name="INFO"
		level_color="\e[0m"
		;;
	W | w)
		level_name="WARN"
		level_color="\e[33m"
		;;
	E | e)
		level_name="ERROR"
		level_color="\e[31m"
		;;
	*)
		# No level given, assume info
		msg="$level $msg"
		level="I"
		level_name="INFO"
		level_color="\e[0m"
		;;
	esac

	# Build and print log message
	local log_entry="$log_time [$level_name]: $msg"
	if [[ "$visible" == true ]]; then
		echo -e "$level_color$log_entry\e[0m"
	fi

	if [ -d "$EMULATION_DIR" ]; then
		echo "$log_entry" >>"$EMULATION_DIR/opensand.log"
	fi
}

# _osnd_cleanup()
function _osnd_cleanup() {
	# Ensure all tmux sessions are closed
	tmux -L ${TMUX_SOCKET} kill-server &>/dev/null

	# Remove temporary directory
	if [ -e "$OSND_TMP" ]; then
		rm -rf "$OSND_TMP" &>/dev/null
	fi
}

# _osnd_abort_measurements()
# Trap function executed on the EXIT trap during active measurements.
function _osnd_abort_measurements() {
	log E "Aborting measurements"
	kill %1 2>/dev/null
	osnd_teardown 2>/dev/null
	_osnd_cleanup
}

# _osnd_interrupt_measurements()
# Trap function executed when the SIGINT signal is received
function _osnd_interrupt_measurements() {
	# Don't just stop the current command, exit the entire script instead
	exit 1
}

# _osnd_check_running_emulation()
function _osnd_check_running_emulation() {
	# Check for running tmux sessions
	if [ ! tmux -L ${TMUX_SOCKET} list-sessions ] &>/dev/null; then
		echo >&2 "Active tmux sessions found!"
		echo >&2 "Another emulation might already be running, or this is a leftover of a previous run."
		echo >&2 "Execute the ./teardown.sh script to get rid of any leftovers."
		exit 2
	fi

	# Check if namespaces exist
	for ns in $(sudo ip netns list); do
		if [[ "$ns" == "osnd"* ]]; then
			echo >&2 "Existing namespace $ns!"
			echo >&2 "Another emulation might already be running, or this is a leftover of a previous run."
			echo >&2 "Execute the ./teardown.sh script to get rid of any leftovers."
			exit 3
		fi
	done
}

# _osnd_create_emulation_output_dir()
function _osnd_create_emulation_output_dir() {
	log D "Creating output directory"

	if [ -e "$EMULATION_DIR" ]; then
		echo >&2 "Output directory $EMULATION_DIR already exists"
		exit 4
	fi

	mkdir -p "$EMULATION_DIR"
	if [ $? -ne 0 ]; then
		echo >&2 "Failed to create output directory $EMULATION_DIR"
		exit 5
	fi

	# Create 'latest' symlink
	local latest_link="$RESULTS_DIR/latest"
	if [ -h "$latest_link" ]; then
		rm "$latest_link"
	fi
	if [ ! -e "$latest_link" ]; then
		ln -s "$EMULATION_DIR" "$latest_link"
	fi
}

# _osnd_create_emulation_tmp_dir()
function _osnd_create_emulation_tmp_dir() {
	log D "Creating temporary directory"

	local tmp_dir=$(mktemp -d --tmpdir opensand.XXXXXX)
	if [ "$?" -ne 0 ]; then
		echo >&2 "Failed to create temporary directory"
		exit 6
	fi

	export OSND_TMP="$tmp_dir"
}

# _osnd_exec_measurement_on_config(config_name)
function _osnd_exec_measurement_on_config() {
	local config_name="$1"
	local -n config_ref="$1"

	# Create output directory for measurements in this configuration
	local measure_output_dir="${EMULATION_DIR}/${config_ref['orbit']}_a${config_ref['attenuation']}"
	mkdir -p "$measure_output_dir"

	# Save configuration
	echo "script_version=${SCRIPT_VERSION}" >"$measure_output_dir/config.txt"
	for config_key in "${!config_ref[@]}"; do
		echo "${config_key}=${config_ref[$config_key]}" >>"$measure_output_dir/config.txt"
	done

	local run_cnt=${config_ref['runs']:-1}
	local run_timing_cnt=${config_ref['timing_runs']:-2}

	osnd_run_ping "$config_name" "$measure_output_dir"

	osnd_run_quic_goodput "$config_name" "$measure_output_dir" false $run_cnt
	osnd_run_quic_timing "$config_name" "$measure_output_dir" false $run_timing_cnt
	osnd_run_quic_goodput "$config_name" "$measure_output_dir" true $run_cnt
	osnd_run_quic_timing "$config_name" "$measure_output_dir" true $run_timing_cnt

	osnd_run_tcp_goodput "$config_name" "$measure_output_dir" false $run_cnt
	osnd_run_tcp_timing "$config_name" "$measure_output_dir" false $run_timing_cnt
	osnd_run_tcp_goodput "$config_name" "$measure_output_dir" true $run_cnt
	osnd_run_tcp_timing "$config_name" "$measure_output_dir" true $run_timing_cnt
}

# _osnd_run_measurements()
function _osnd_run_measurements() {
	log I "Orbits: ${orbits[@]}"
	log I "Attenuations: ${attenuations[@]}"

	local measure_cnt=$(echo "${#orbits[@]}*${#attenuations[@]}" | bc -l)
	local measure_nr=1

	env | sort >"${EMULATION_DIR}/environment.txt"

	for orbit in "${orbits[@]}"; do
		for attenuation in "${attenuations[@]}"; do
			log I "Starting measurement ${measure_nr}/${measure_cnt}"
			log D "Measurement configuration: orbit=$orbit, attenuation=$attenuation"

			unset env_config
			declare -A env_config

			env_config['orbit']="$orbit"
			env_config['attenuation']="$attenuation"
			env_config['prime']=0
			env_config['runs']=1
			env_config['timing_runs']=4

			_osnd_exec_measurement_on_config env_config

			sleep $MEASURE_WAIT
			((measure_nr++))
		done
	done
}

function _osnd_parse_args() {
	show_stats=false
	# TODO arg parse
}

function _main() {
	declare -a orbits=("GEO")
	declare -a attenuations=(0)

	_osnd_parse_args "$@"

	_osnd_check_running_emulation

	emulation_start="$(date +"%Y-%m-%d-%H-%M")"
	export EMULATION_DIR="${RESULTS_DIR}/${emulation_start}_opensand"
	_osnd_create_emulation_output_dir
	_osnd_create_emulation_tmp_dir

	log I "Starting Opensand satellite emulation measurements"
	trap _osnd_abort_measurements EXIT
	trap _osnd_interrupt_measurements SIGINT
	osnd_stats_every 4 &

	_osnd_run_measurements 2> >(log E -)

	kill %1
	trap - SIGINT
	trap - EXIT

	_osnd_cleanup
	log I "Done with all measurements"
}

# If script is executed directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	_main "$@"
fi
