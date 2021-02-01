#!/bin/bash

function osnd_setup_opensand() {
	# Copy configurations
	for entity in sat gw st; do
		if [ -e "${OSND_TMP}/config_${entity}" ]; then
			rm -rf "${OSND_TMP}/config_${entity}"
		fi
		cp -r "${OPENSAND_CONFIGS}/${entity}" "${OSND_TMP}/config_${entity}"
	done

	# Start satelite
	log D "Launching satellite into (name-)space"
	sudo ip netns exec osnd-sat killall opensand-sat -q
	tmux -L ${TMUX_SOCKET} new-session -s opensand-sat -d "sudo ip netns exec osnd-sat bash"
	sleep $TMUX_INIT_WAIT
	tmux -L ${TMUX_SOCKET} send-keys -t opensand-sat "mount -o bind ${OSND_TMP}/config_sat /etc/opensand" Enter
	tmux -L ${TMUX_SOCKET} send-keys -t opensand-sat "opensand-sat -a ${EMU_SAT_IP%%/*} -c /etc/opensand" Enter

	# Start gateway
	log D "Aligning the gateway's satellite dish"
	sudo ip netns exec osnd-gw killall opensand-gw -q
	tmux -L ${TMUX_SOCKET} new-session -s opensand-gw -d "sudo ip netns exec osnd-gw bash"
	sleep $TMUX_INIT_WAIT
	tmux -L ${TMUX_SOCKET} send-keys -t opensand-gw "mount -o bind ${OSND_TMP}/config_gw /etc/opensand" Enter
	tmux -L ${TMUX_SOCKET} send-keys -t opensand-gw "opensand-gw -i 0 -a ${EMU_GW_IP%%/*} -t tap-gw -c /etc/opensand" Enter

	# Start statellite terminal
	log D "Connecting the satellite terminal"
	sudo ip netns exec osnd-st killall opensand-st -q
	tmux -L ${TMUX_SOCKET} new-session -s opensand-st -d "sudo ip netns exec osnd-st bash"
	sleep $TMUX_INIT_WAIT
	tmux -L ${TMUX_SOCKET} send-keys -t opensand-st "mount -o bind ${OSND_TMP}/config_st /etc/opensand" Enter
	tmux -L ${TMUX_SOCKET} send-keys -t opensand-st "opensand-st -i 1 -a ${EMU_ST_IP%%/*} -t tap-st -c /etc/opensand" Enter
}

# If script is executed directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	declare -F log >/dev/null || function log() {
		local level="$1"
		local msg="$2"

		echo "[$level] $msg"
	}

	osnd_setup_opensand "$@"
fi
