#!/bin/bash

OPENSAND_CONFIGS="/home/beil/opensand/config"

# Start satelite
log D "Launching satellite into (name-)space"
sudo ip netns exec ns3 killall opensand-sat -q
tmux new-session -s opensand-sat -d
tmux send-keys -t opensand-sat "sudo ip netns exec ns3 mount -o bind ${OPENSAND_CONFIGS}/sat /etc/opensand" Enter
tmux send-keys -t opensand-sat "sudo ip netns exec ns3 opensand-sat -a 10.3.3.254 -c /etc/opensand" Enter

# Start gateway
log D "Aligning the gateway's satellite dish"
sudo ip netns exec ns3 killall opensand-gw -q
tmux new-session -s opensand-gw -d
tmux send-keys -t opensand-gw "sudo ip netns exec ns4 mount -o bind ${OPENSAND_CONFIGS}/gw /etc/opensand" Enter
tmux send-keys -t opensand-gw "sudo ip netns exec ns4 opensand-gw -i 0 -a 10.3.3.1 -t tapgw -c /etc/opensand" Enter

# Start statellite terminal
log D "Connecting the satellite terminal"
sudo ip netns exec ns1 killall opensand-st -q
tmux new-session -s opensand-st -d
tmux send-keys -t opensand-st "sudo ip netns exec ns1 mount -o bind ${OPENSAND_CONFIGS}/st /etc/opensand" Enter
tmux send-keys -t opensand-st "sudo ip netns exec ns1 opensand-st -i 1 -a 10.3.3.2 -t tapst -c /etc/opensand" Enter
