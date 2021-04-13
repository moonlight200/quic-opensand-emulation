#!/bin/bash
set -o nounset
set -o errtrace
set -o functrace

export SCRIPT_VERSION="1.5.1"
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

declare -A pids

# log(level, message...)
# Log a message of the specified level to the output and the log file.
function log() {
	local level="$1"
	shift
	local msg="$@"

	if [[ "$level" == "-" ]] || [[ "$msg" == "-" ]]; then
		if [[ "$level" == "-" ]]; then
			# Level will be read from stdin
			level=""
		fi

		# Log each line in stdin as separate log message
		while read -r err_line; do
			log $level $err_line
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
	rm -rf "$OSND_TMP" &>/dev/null
}

# _osnd_abort_measurements()
# Trap function executed on the EXIT trap during active measurements.
function _osnd_abort_measurements() {
	log E "Aborting measurements"
	osnd_teardown 2>/dev/null
	for pid in "${pids[@]}"; do
		kill $pid &>/dev/null
	done
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

# _osnd_start_logging_pipe()
# Creates a named pipe to be used by processes in tmux sessions to output log messages
function _osnd_start_logging_pipe() {
	log D "Starting log pipe"
	mkfifo "${OSND_TMP}/logging"
	tail -f -n +0 "${OSND_TMP}/logging" > >(log -) &
	pids['logpipe']=$!
}

# _osnd_stop_logging_pipe()
function _osnd_stop_logging_pipe() {
	log D "Stopping log pipe"
	kill ${pids['logpipe']} &>/dev/null
	unset pids['logpipe']
	rm "${OSND_TMP}/logging"
}

# _osnd_generate_scenarios()
function _osnd_generate_scenarios() {
	scenario_file="$OSND_TMP/scenarios"
	echo "# Scenario config generated at $(date)" >"$scenario_file"

	local common_options="-N ${run_cnt} -T ${ttfb_run_cnt} -P ${env_prime_secs}"
	if [[ "$exec_plain" != "true" ]]; then
		common_options="$common_options -V"
	fi
	if [[ "$exec_pep" != "true" ]]; then
		common_options="$common_options -W"
	fi
	if [[ "$exec_ping" != "true" ]]; then
		common_options="$common_options -X"
	fi
	if [[ "$exec_quic" != "true" ]]; then
		common_options="$common_options -Y"
	fi
	if [[ "$exec_tcp" != "true" ]]; then
		common_options="$common_options -Z"
	fi

	for orbit in "${orbits[@]}"; do
		for attenuation in "${attenuations[@]}"; do
			for ccs in "${cc_algorithms[@]}"; do
				for tbs in "${transfer_buffer_sizes[@]}"; do
					for qbs in "${quicly_buffer_sizes[@]}"; do
						for ubs in "${udp_buffer_sizes[@]}"; do
							local scenario_options="-O ${orbit} -A ${attenuation} -C ${ccs} -B ${tbs} -Q ${qbs} -U ${ubs}"
							echo "$common_options $scenario_options" >>"$scenario_file"
						done
					done
				done
			done
		done
	done
}

# _osnd_count_scenarios()
function _osnd_count_scenarios() {
	awk '!/^(#.*)?$/' "$scenario_file" | wc -l
}

# _osnd_read_scenario(config_ref, scenario)
function _osnd_read_scenario() {
	local -n config_ref="$1"
	local scenario="$2"

	local parsed_scenario_args=$(getopt -n "opensand scenario" -o "A:B:C:M:N:O:P:Q:T:U:VWXYZ" -l "attenuation:,transport-buffers:,congestion-control:,modulation:,runs:,orbits:,prime:,quicly-buffers:,timing-runs:,udp-buffers:,disable-plain,disable-pep,disable-ping,disable-quic,disable-tcp" -- $scenario)
	local parsing_status=$?
	if [ "$parsing_status" != "0" ]; then
		return 1
	fi

	set +o nounset
	eval set -- "$parsed_scenario_args"
	while :; do
		case "$1" in
		-A | --attenuation)
			config_ref['attenuation']="$2"
			shift 2
			;;
		-B | --transport-buffers)
			config_ref['tbs']="$2"
			shift 2
			;;
		-C | --congestion-control)
			config_ref['ccs']="$2"
			shift 2
			;;
		-M | --modulation)
			config_ref['modulation_id']="$2"
			shift 2
			;;
		-N | --runs)
			config_ref['runs']="$2"
			shift 2
			;;
		-O | --orbit)
			config_ref['orbit']="$2"
			shift 2
			;;
		-P | --prime)
			config_ref['prime']="$2"
			shift 2
			;;
		-Q | --quicly-buffers)
			config_ref['qbs']="$2"
			shift 2
			;;
		-T | --timing-runs)
			config_ref['timing_runs']="$2"
			shift 2
			;;
		-U | --udp-buffers)
			config_ref['ubs']="$2"
			shift 2
			;;
		-V | --disable-plain)
			config_ref['exec_plain']="false"
			shift 1
			;;
		-W | --disable-pep)
			config_ref['exec_pep']="false"
			shift 1
			;;
		-X | --disable-ping)
			config_ref['exec_ping']="false"
			shift 1
			;;
		-Y | --disable-quic)
			config_ref['exec_quic']="false"
			shift 1
			;;
		-Z | --dsiable-tcp)
			config_ref['exec_tcp']="false"
			shift 1
			;;
		--)
			# Stop parsing args
			shift 1
			break
			;;
		*)
			echo >&2 "Unknown argument while reading scenario: $1"
			return 2
			;;
		esac
	done
	set -o nounset
}

# _osnd_exec_scenario_with_config(config_name)
function _osnd_exec_scenario_with_config() {
	local config_name="$1"
	local -n config_ref="$1"

	# Create output directory for measurements in this configuration
	local measure_output_dir="${EMULATION_DIR}/${config_ref['id']}"
	if [ -d "$measure_output_dir" ]; then
		log W "Output directory $measure_output_dir already exists"
	fi
	mkdir -p "$measure_output_dir"

	# Save configuration
	{
		echo "script_version=${SCRIPT_VERSION}"
		for config_key in "${!config_ref[@]}"; do
			echo "${config_key}=${config_ref[$config_key]}"
		done
	} | sort >"$measure_output_dir/config.txt"

	local run_cnt=${config_ref['runs']:-1}
	local run_timing_cnt=${config_ref['timing_runs']:-2}

	if [[ "${config_ref['exec_ping']:-true}" == true ]]; then
		osnd_measure_ping "$config_name" "$measure_output_dir"
	fi

	if [[ "${config_ref['exec_quic']:-true}" == true ]]; then
		if [[ "${config_ref['exec_plain']:-true}" == true ]]; then
			osnd_measure_quic_goodput "$config_name" "$measure_output_dir" false $run_cnt
			osnd_measure_quic_timing "$config_name" "$measure_output_dir" false $run_timing_cnt
		fi
		if [[ "${config_ref['exec_pep']:-true}" == true ]]; then
			osnd_measure_quic_goodput "$config_name" "$measure_output_dir" true $run_cnt
			osnd_measure_quic_timing "$config_name" "$measure_output_dir" true $run_timing_cnt
		fi
	fi

	if [[ "${config_ref['exec_tcp']:-true}" == true ]]; then
		if [[ "${config_ref['exec_plain']:-true}" == true ]]; then
			osnd_measure_tcp_goodput "$config_name" "$measure_output_dir" false $run_cnt
			osnd_measure_tcp_timing "$config_name" "$measure_output_dir" false $run_timing_cnt
		fi
		if [[ "${config_ref['exec_pep']:-true}" == true ]]; then
			osnd_measure_tcp_goodput "$config_name" "$measure_output_dir" true $run_cnt
			osnd_measure_tcp_timing "$config_name" "$measure_output_dir" true $run_timing_cnt
		fi
	fi
}

#_osnd_get_cc(ccs, index)
function _osnd_get_cc() {
	local ccs="$1"
	local index=$2

	case ${ccs:$index:1} in
	c | C)
		echo "cubic"
		;;
	r | R)
		echo "reno"
		;;
	esac
}

# _osnd_run_scenarios()
function _osnd_run_scenarios() {
	local measure_cnt=$(_osnd_count_scenarios)
	local measure_nr=0

	env | sort >"${EMULATION_DIR}/environment.txt"

	while read scenario; do
		((measure_nr++))
		log I "Starting measurement ${measure_nr}/${measure_cnt}"
		log D "Reading scenario: $scenario"

		unset scenario_config
		declare -A scenario_config

		# Default configuration values
		scenario_config['exec_plain']="true"
		scenario_config['exec_pep']="true"
		scenario_config['exec_ping']="true"
		scenario_config['exec_quic']="true"
		scenario_config['exec_tcp']="true"

		scenario_config['prime']=5
		scenario_config['runs']=1
		scenario_config['timing_runs']=4

		scenario_config['orbit']="GEO"
		scenario_config['attenuation']=0
		scenario_config['modulation_id']=1
		scenario_config['ccs']="rrrr"
		scenario_config['tbs']="1M,1M"
		scenario_config['qbs']="1M,1M,1M,1M"
		scenario_config['ubs']="1M,1M,1M,1M"

		_osnd_read_scenario scenario_config "$scenario"
		local read_status=$?
		if [ "$read_status" != "0" ]; then
			log E "Failed to read scenario($read_status): '$scenario'"
			sleep $MEASURE_WAIT
			continue
		fi
		scenario_config['id']="$(md5sum <<<"$scenario" | cut -d' ' -f 1)"

		# Extract combined values
		scenario_config['cc_sv']="$(_osnd_get_cc "${scenario_config['ccs']}", 0)"
		scenario_config['cc_gw']="$(_osnd_get_cc "${scenario_config['ccs']}", 1)"
		scenario_config['cc_st']="$(_osnd_get_cc "${scenario_config['ccs']}", 2)"
		scenario_config['cc_cl']="$(_osnd_get_cc "${scenario_config['ccs']}", 3)"

		local -a tbuf_sizes=()
		IFS=',' read -ra tbuf_sizes <<<"${scenario_config['tbs']}"
		scenario_config['tbs_gw']="${tbuf_sizes[0]}"
		scenario_config['tbs_st']="${tbuf_sizes[1]}"

		local -a qbuf_sizes=()
		IFS=',' read -ra qbuf_sizes <<<"${scenario_config['qbs']}"
		scenario_config['qbs_sv']="${qbuf_sizes[0]}"
		scenario_config['qbs_gw']="${qbuf_sizes[1]}"
		scenario_config['qbs_st']="${qbuf_sizes[2]}"
		scenario_config['qbs_cl']="${qbuf_sizes[3]}"

		local -a ubuf_sizes=()
		IFS=',' read -ra ubuf_sizes <<<"${scenario_config['ubs']}"
		scenario_config['ubs_sv']="${ubuf_sizes[0]}"
		scenario_config['ubs_gw']="${ubuf_sizes[1]}"
		scenario_config['ubs_st']="${ubuf_sizes[2]}"
		scenario_config['ubs_cl']="${ubuf_sizes[3]}"

		# Execute scenario
		echo "${env_config['id']} $scenario" >>"${EMULATION_DIR}/scenarios.txt"
		_osnd_exec_scenario_with_config env_config

		sleep $MEASURE_WAIT
	done < <(awk '!/^(#.*)?$/' "$scenario_file")
}

# _osnd_print_usage()
function _osnd_print_usage() {
	cat <<USAGE
Usage: $1 [options]

General:
  -f <file>  read the scenarios from this file instead of the command line arguments.
  -h         print this help message
  -s         show statistic logs in stdout
  -t <tag>   optional tag to identify this measurement
  -v         print version and exit

Scenario configuration:
  -A <#,>    csl of attenuations to measure (default: 0db)
  -B <#,>*   csl of two qperf transfer buffer sizes for G and T (default: 1M)
  -C <SGTC,> csl of congestion control algorithms to measure (c = cubic, r = reno) (default: r)
  -N #       number of goodput measurements per config (default: 1)
  -O <#,>    csl of orbits to measure (GEO|MEO|LEO) (default: GEO)
  -P #       seconds to prime a new environment with some pings (default: 5)
  -Q <#,>*   csl of four qperf quicly buffer sizes for SGTC (default: 1M)
  -T #       number of timing measurements per config (default: 4)
  -U <#,>*   csl of four qperf udp buffer sizes for SGTC (default: 1M)
  -V         disable plain (non pep) measurements
  -W         disable pep measurements
  -X         disable ping measurement
  -Y         disable quic measurements
  -Z         disable tcp measurements

Scenario file format:
  Each line in the file describes a single scenario, blank lines and lines
  starting with a # are ignored. A scenario can be configured using the arguments
  in the scenario configuration section above. However all arguments that accept
  a comma separated list of values only accept a single value in the scenario
  file. Same goes for the repeated arguments, only one value is accepted.

<#,> indicates that the argument accepts a comma separated list (csl) of values
...* indicates, that the argument can be repeated multiple times
SGTC specifies one value for each of the emulation components:
     server, gateway, satellite terminal and client
USAGE
}

function _osnd_parse_args() {
	show_stats=false
	osnd_tag=""
	env_prime_secs=5
	ttfb_run_cnt=4
	run_cnt=1
	exec_plain=true
	exec_pep=true
	exec_ping=true
	exec_quic=true
	exec_tcp=true
	scenario_file=""

	local -a new_transfer_buffer_sizes=()
	local -a new_quicly_buffer_sizes=()
	local -a new_udp_buffer_sizes=()
	local measure_cli_args="false"
	while getopts ":f:hst:vA:B:C:N:O:P:Q:T:U:VWXYZ" opt; do
		if [[ "${opt^^}" == "$opt" ]]; then
			measure_cli_args="true"
			if [[ "$scenario_file" != "" ]]; then
				echo >&2 "Cannot configure measurements with cli args when scenario file is given"
				exit 1
			fi
		fi

		case "$opt" in
		f)
			if [[ "$measure_cli_args" == "true" ]]; then
				echo >&2 "Cannot set scenario file and configure measurements with cli args at the same time"
				exit 1
			fi
			scenario_file="$OPTARG"
			;;
		h)
			_osnd_print_usage "$0"
			exit 0
			;;
		s)
			show_stats=true
			;;
		t)
			osnd_tag="_$OPTARG"
			;;
		v)
			echo "opensand-measurement $SCRIPT_VERSION"
			exit 0
			;;
		A)
			IFS=',' read -ra attenuations <<<"$OPTARG"
			;;
		B)
			IFS=',' read -ra buffer_sizes_config <<<"$OPTARG"
			if [[ "${#buffer_sizes_config[@]}" != 2 ]]; then
				echo "Need exactly two transfer buffer size configurations for G and T, ${#buffer_sizes_config[@]} given in '$OPTARG'"
				exit 1
			fi
			new_transfer_buffer_sizes+=("$OPTARG")
			;;
		C)
			IFS=',' read -ra cc_algorithms <<<"$OPTARG"
			for ccs in "${cc_algorithms[@]}"; do
				if [[ "${#ccs}" != 4 ]]; then
					echo "Need exactly four cc algorithms for SGT, ${#ccs} given in '$ccs'"
					exit 1
				fi
				for i in 0 1 2 3; do
					if [[ "$(_osnd_get_cc "$ccs" $i)" == "" ]]; then
						echo "Unknown cc algorithm '${ccs:$i:1}' in '$ccs'"
						exit 1
					fi
				done
			done
			;;
		N)
			if [[ "$OPTARG" =~ ^[0-9]+$ ]]; then
				run_cnt=$OPTARG
			else
				echo "Invalid integer value for -N"
				exit 1
			fi
			;;
		O)
			IFS=',' read -ra orbits <<<"$OPTARG"
			;;
		P)
			if [[ "$OPTARG" =~ ^[0-9]+$ ]]; then
				env_prime_secs=$OPTARG
			else
				echo "Invalid integer value for -P"
				exit 1
			fi
			;;
		Q)
			IFS=',' read -ra buffer_sizes_config <<<"$OPTARG"
			if [[ "${#buffer_sizes_config[@]}" != 4 ]]; then
				echo "Need exactly four quicly buffer size configurations for SGTC, ${#buffer_sizes_config[@]} given in '$OPTARG'"
				exit 1
			fi
			new_quicly_buffer_sizes+=("$OPTARG")
			;;
		T)
			if [[ "$OPTARG" =~ ^[0-9]+$ ]]; then
				ttfb_run_cnt=$OPTARG
			else
				echo "Invalid integer value for -T"
				exit 1
			fi
			;;
		U)
			IFS=',' read -ra buffer_sizes_config <<<"$OPTARG"
			if [[ "${#buffer_sizes_config[@]}" != 4 ]]; then
				echo "Need exactly four udp buffer size configurations for SGTC, ${#buffer_sizes_config[@]} given in '$OPTARG'"
				exit 1
			fi
			new_udp_buffer_sizes+=("$OPTARG")
			;;
		V)
			exec_plain=false
			;;
		W)
			exec_pep=false
			;;
		X)
			exec_ping=false
			;;
		Y)
			exec_quic=false
			;;
		Z)
			exec_tcp=false
			;;
		:)
			echo "Argumet required for -$OPTARG" >&2
			echo "$0 -h for help" >&2
			exit 1
			;;
		?)
			echo "Unknown argument -$OPTARG" >&2
			echo "$0 -h for help" >&2
			exit 2
			;;
		esac
	done

	if [[ "${#new_transfer_buffer_sizes[@]}" > 0 ]]; then
		transfer_buffer_sizes=("${new_transfer_buffer_sizes[@]}")
	fi
	if [[ "${#new_quicly_buffer_sizes[@]}" > 0 ]]; then
		quicly_buffer_sizes=("${new_quicly_buffer_sizes[@]}")
	fi
	if [[ "${#new_udp_buffer_sizes[@]}" > 0 ]]; then
		udp_buffer_sizes=("${new_udp_buffer_sizes[@]}")
	fi
}

function _main() {
	declare -a orbits=("GEO")
	declare -a attenuations=(0)
	declare -a cc_algorithms=("rrrr")
	declare -a transfer_buffer_sizes=("1M,1M")
	declare -a quicly_buffer_sizes=("1M,1M,1M,1M")
	declare -a udp_buffer_sizes=("1M,1M,1M,1M")

	_osnd_parse_args "$@"

	_osnd_check_running_emulation

	emulation_start="$(date +"%Y-%m-%d-%H-%M")"
	export EMULATION_DIR="${RESULTS_DIR}/${emulation_start}_opensand${osnd_tag}"
	_osnd_create_emulation_output_dir
	_osnd_create_emulation_tmp_dir

	if [[ "$scenario_file" == "" ]]; then
		_osnd_generate_scenarios
	fi

	log I "Starting Opensand satellite emulation measurements"
	# Start printing stats
	osnd_stats_every 4 &
	pids['stats']=$!
	_osnd_start_logging_pipe

	trap _osnd_abort_measurements EXIT
	trap _osnd_interrupt_measurements SIGINT

	_osnd_run_scenarios 2> >(log E -)

	trap - SIGINT
	trap - EXIT

	log I "All measurements are done, cleaning up"

	_osnd_stop_logging_pipe
	kill ${pids['stats']} &>/dev/null
	unset pids['stats']

	_osnd_cleanup
	log I "Done with all measurements"
}

# If script is executed directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	_main "$@"
fi
