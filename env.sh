#!/bin/bash
# Environment configuration
# Don't use relative paths as some commands are executed in a rooted sub-shell

# File and directory paths

QPERF_BIN="$HOME/build-qperf/qperf"
QPERF_CRT="$HOME/server.crt"
QPERF_KEY="$HOME/server.key"
PEPSAL_BIN="$HOME/pepsal/src/pepsal"
IPERF_BIN="/usr/bin/iperf3"
OPENSAND_CONFIGS="${SCRIPT_DIR}/config"
NGINX_CONFIG="${SCRIPT_DIR}/config/nginx.conf"
RESULTS_DIR="$HOME/out/$(hostname)"

# Opensand network config

EMU_NET="10.3.3.0/24"
EMU_GW_IP="10.3.3.1/24"
EMU_ST_IP="10.3.3.2/24"
EMU_SAT_IP="10.3.3.254/24"

OVERLAY_NET_IPV6="fd81::/64"
OVERLAY_NET="10.81.81.0/24"
OVERLAY_GW_IP="10.81.81.1/24"
OVERLAY_ST_IP="10.81.81.2/24"

GW_LAN_NET_IPV6="fd00:10:115:8::/64"
GW_LAN_NET="10.115.8.0/24"
GW_LAN_ROUTER_IP="10.115.8.1/24"
GW_LAN_PROXY_IP="10.115.8.10/24"

ST_LAN_NET_IPV6="fd00:192:168:3::/64"
ST_LAN_NET="192.168.3.0/24"
ST_LAN_ROUTER_IP="192.168.3.1/24"
ST_LAN_PROXY_IP="192.168.3.24/24"

SV_LAN_NET="10.30.4.0/24"
SV_LAN_ROUTER_IP="10.30.4.1/24"
SV_LAN_SERVER_IP="10.30.4.18/24"

CL_LAN_NET="192.168.26.0/24"
CL_LAN_ROUTER_IP="192.168.26.1/24"
CL_LAN_CLIENT_IP="192.168.26.34/24"

BR_ST_MAC="de:ad:be:ef:00:02"
BR_EMU_MAC="de:ad:be:ef:00:ff"
BR_GW_MAC="de:ad:be:ef:00:01"

# Timings and advanced config

# How long to run the measurements (in seconds)
MEASURE_TIME=300
# Seconds to wait after the environment has been started and before the measurements are executed
MEASURE_WAIT=3
# Seconds to wait after one measurement run
RUN_WAIT=1
# Seconds to wait after sending a stop signal to a running command
CMD_SHUTDOWN_WAIT=0.1
# Seconds to wait after opening a new tmux session
TMUX_INIT_WAIT=0.1
# Name of the tmux socket to run all the sessions on
TMUX_SOCKET="opensand"
