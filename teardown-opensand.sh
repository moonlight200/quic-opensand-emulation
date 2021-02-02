#!/bin/bash

# _osnd_teardown_opensand_entity(namespace, session, binary, config_name)
# Teardown a single entity of the opensand emulation.
function _osnd_teardown_opensand_entity() {
	local namespace="$1"
	local session="$2"
	local binary="$3"
	local config_name="$4"

	tmux -L ${TMUX_SOCKET} send-keys -t ${session} C-c
	sleep $CMD_SHUTDOWN_WAIT
	tmux -L ${TMUX_SOCKET} send-keys -t ${session} "umount /etc/opensand" Enter
	tmux -L ${TMUX_SOCKET} send-keys -t ${session} C-d
	sleep $CMD_SHUTDOWN_WAIT
	sudo ip netns exec ${namespace} killall ${binary} -q
	tmux -L ${TMUX_SOCKET} kill-session -t ${session} >/dev/null 2>&1
	rm -rf "${OSND_TMP}/${config_name}"
}

# osnd_teardown_opensand()
# Teardown all opensand entities of the emulation.
function osnd_teardown_opensand() {
	log D "Disconnecting satellite terminal"
	_osnd_teardown_opensand_entity "osnd-st" "opensand-st" "opensand-st" "config_st"

	log D "Shutting down gateway"
	_osnd_teardown_opensand_entity "osnd-gw" "opensand-gw" "opensand-gw" "config_gw"

	log D "Desintegrating satellite"
	_osnd_teardown_opensand_entity "osnd-sat" "opensand-sat" "opensand-sat" "config_sat"
}

# If script is executed directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	declare -F log >/dev/null || function log() {
		local level="$1"
		local msg="$2"

		echo "[$level] $msg"
	}

	osnd_teardown_opensand "$@"
fi
