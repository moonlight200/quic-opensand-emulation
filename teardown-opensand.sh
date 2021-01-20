#!/bin/bash

# _teardown_opensand_entity(namespace, session, binary)
# Teardown a single entity of the opensand emulation.
function _teardown_opensand_entity() {
	local namespace="$1"
	local session="$2"
	local binary="$3"
	local shutdown_wait=0.1

	tmux send-keys -t ${session} C-c
	sleep $shutdown_wait
	tmux send-keys -t ${session} "umount /etc/opensand" Enter
	sleep $shutdown_wait
	tmux send-keys -t ${session} C-d
	sleep $shutdown_wait
	sudo ip netns exec ${namespace} killall ${binary} -q
	tmux kill-session -t ${session} > /dev/null 2>&1
}

# _teardown_opensand()
# Teardown all opensand entities of the emulation.
function _teardown_opensand() {
	declare -F log > /dev/null || function log() {
		local level="$1"
		local msg="$2"

		echo "[$level] $msg"
	}


	log D "Disconnecting satellite terminal"
	_teardown_opensand_entity "osnd-st" "opensand-st" "opensand-st"

	log D "Shutting down gateway"
	_teardown_opensand_entity "osnd-gw" "opensand-gw" "opensand-gw"

	log D "Desintegrating satellite"
	_teardown_opensand_entity "osnd-sat" "opensand-sat" "opensand-sat"
}

# If script is executed directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	_teardown_opensand "$@"
fi
