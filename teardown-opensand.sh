#!/bin/bash

declare -F log > /dev/null || function log() {
	local level="$1"
	local msg="$2"

	echo "[$level] $msg"
}

log D "Disconnecting satellite terminal"
tmux send-keys -t opensand-st C-c
sleep 0.1
tmux send-keys -t opensand-st C-d
sleep 0.1
sudo ip netns exec ns1 killall opensand-st -q
sleep 0.1
tmux kill-session -t opensand-st > /dev/null 2>&1

log D "Shutting down gateway"
tmux send-keys -t opensand-gw C-c
sleep 0.1
tmux send-keys -t opensand-gw C-d
sleep 0.1
sudo ip netns exec ns1 killall opensand-gw -q
sleep 0.1
tmux kill-session -t opensand-gw > /dev/null 2>&1

log D "Desintegrating satellite"
tmux send-keys -t opensand-sat C-c
sleep 0.1
tmux send-keys -t opensand-sat C-d
sleep 0.1
sudo ip netns exec ns1 killall opensand-sat -q
sleep 0.1
tmux kill-session -t opensand-sat > /dev/null 2>&1
