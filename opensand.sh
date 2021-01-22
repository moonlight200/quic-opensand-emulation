#!/bin/bash
set -o nounset
set -o errtrace
set -o functrace

export SCRIPT_VERSION="0.4-alpha"
export SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

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

	local log_time="$( date --rfc-3339=seconds )"
	local level_name="INFO"
	local level_color="\e[0m"
	case $level in
		D|d)
			level_name="DEBUG"
			level_color="\e[2m"
			;;
		I|i)
			level_name="INFO"
			level_color="\e[0m"
			;;
		W|w)
			level_name="WARN"
			level_color="\e[33m"
			;;
		E|e)
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
	echo -e "$level_color$log_entry\e[0m"
	
	if [ -d "$EMULATION_DIR" ]; then
		echo "$log_entry" >> "$EMULATION_DIR/opensand.log"
	fi
}

function _osnd_create_emulation_dir() {
	if [ -e "$EMULATION_DIR" ]; then
		>&2 echo "Output directory $EMULATION_DIR already exists"
		>&2 echo "aborting emulation"
		exit 4
	fi

	mkdir -p "$EMULATION_DIR"
	if [ $? -ne 0 ]; then
		>&2 echo "Failed to create output directory $EMULATION_DIR"
		>&2 echo "aborting emulation"
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

function main() {
	# TODO arg parse
	emulation_start="$( date +"%Y-%m-%d-%H-%M" )"
	export EMULATION_DIR="${RESULTS_DIR}/${emulation_start}_opensand"
	_osnd_create_emulation_dir

	log I "Starting Opensand satellite emulation measurements"

	osnd_run_ping "${EMULATION_DIR}" 2> >(log E -)
	osnd_run_quic_goodput "${EMULATION_DIR}" false 1 2> >(log E -)
	osnd_run_quic_timing "${EMULATION_DIR}" false 2 2> >(log E -)
	osnd_run_tcp_goodput "${EMULATION_DIR}" false 1 2> >(log E -)
	osnd_run_tcp_timing "${EMULATION_DIR}" false 2 2> >(log E -)

	# TODO cleanup: kill tmux server (also on trap)
	log I "Done with all measurements"
}

main "$@"
