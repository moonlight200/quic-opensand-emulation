#!/bin/bash
# Environment configuration

export OPENSAND_CONFIGS="${SCRIPT_DIR}/config"
export RESULTS_DIR="/home/beil/out/$( hostname )"

# Opensand network config
export EMU_NET="10.3.3.0/24"
export EMU_GW_IP="10.3.3.1/24"
export EMU_ST_IP="10.3.3.2/24"
export EMU_SAT_IP="10.3.3.254/24"

export OVERLAY_NET_IPV6="fd81::/64"
export OVERLAY_NET="10.81.81.0/24"
export OVERLAY_GW_IP="10.81.81.1/24"
export OVERLAY_ST_IP="10.81.81.2/24"

export GW_LAN_NET_IPV6="fd00:10:115:8::/64"
export GW_LAN_NET="10.115.8.0/24"
export GW_LAN_ROUTER_IP="10.115.8.1/24"
export GW_LAN_SERVER_IP="10.115.8.10/24"

export ST_LAN_NET_IPV6="fd00:192:168:3::/64"
export ST_LAN_NET="192.168.3.0/24"
export ST_LAN_ROUTER_IP="192.168.3.1/24"
export ST_LAN_CLIENT_IP="192.168.3.24/24"

export BR_ST_MAC="de:ad:be:ef:00:02"
export BR_EMU_MAC="de:ad:be:ef:00:ff"
export BR_GW_MAC="de:ad:be:ef:00:01"
