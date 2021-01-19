#!/bin/bash

log D "Disconnecting satellite terminal"
tmux send-keys -t opensand-st C-c
sudo ip netns exec ns1 killall opensand-st -q
tmux kill-session -t opensand-st > /dev/null 2>&1

log D "Shutting down gateway"
tmux send-keys -t opensand-gw C-c
sudo ip netns exec ns1 killall opensand-gw -q
tmux kill-session -t opensand-gw > /dev/null 2>&1

log D "Desintegrating satellite"
tmux send-keys -t opensand-sat C-c
sudo ip netns exec ns1 killall opensand-sat -q
tmux kill-session -t opensand-sat > /dev/null 2>&1
