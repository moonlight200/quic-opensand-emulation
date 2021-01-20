#!/bin/bash

OPENSAND_CONFIGS="/home/beil/opensand/config"

declare -F log > /dev/null || function log() {
	local level="$1"
	local msg="$2"

	echo "[$level] $msg"
}

# Start satelite
log D "Launching satellite into (name-)space"
sudo ip netns exec ns3 killall opensand-sat -q
tmux new-session -s opensand-sat -d "sudo ip netns exec ns3 bash"
sleep 0.2
tmux send-keys -t opensand-sat "mount -o bind ${OPENSAND_CONFIGS}/sat /etc/opensand" Enter
sleep 0.2
tmux send-keys -t opensand-sat "opensand-sat -a 10.3.3.254 -c /etc/opensand" Enter
sleep 0.2

# Start gateway
log D "Aligning the gateway's satellite dish"
sudo ip netns exec ns3 killall opensand-gw -q
tmux new-session -s opensand-gw -d "sudo ip netns exec ns4 bash"
sleep 0.2
tmux send-keys -t opensand-gw "mount -o bind ${OPENSAND_CONFIGS}/gw /etc/opensand" Enter
sleep 0.2
tmux send-keys -t opensand-gw "opensand-gw -i 0 -a 10.3.3.1 -t tapgw -c /etc/opensand" Enter
sleep 0.2

# Start statellite terminal
log D "Connecting the satellite terminal"
sudo ip netns exec ns1 killall opensand-st -q
tmux new-session -s opensand-st -d "sudo ip netns exec ns1 bash"
sleep 0.2
tmux send-keys -t opensand-st "mount -o bind ${OPENSAND_CONFIGS}/st /etc/opensand" Enter
sleep 0.2
tmux send-keys -t opensand-st "opensand-st -i 1 -a 10.3.3.2 -t tapst -c /etc/opensand" Enter
sleep 0.2
