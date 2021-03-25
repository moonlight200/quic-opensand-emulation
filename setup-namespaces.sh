#!/bin/bash

# Setup networking namespaces for OpenSand emulation
#
# Namespaces:
#   osnd-cl  : client
#   osnd-stp : satellite terminal proxy
#   osnd-st  : satellite terminal
#   osnd-emu : emulation network
#   osnd-sat : satelite
#   osnd-gw  : gateway
#   osnd-gwp : gateway proxy
#   osnd-sv  : server
#
# Connection overview:
#   emulation network (EMU_NET):
#     emu2(osnd-st), emu0(osnd-sat) and emu1(osnd-gw) are all directly linked via br-emu(osnd-emu)
#     they form the network that the emulation of the satellite links runs on
#   overlay network (OVERLAY_NET):
#     br-st(osnd-st) and br-gw(osnd-gw) are connected through the overlay network built
#     with opensand. Each bridge is connected to a tap interface, that is
#     used with the opensand entity running in that namespace.
#   gateway network (GW_LAN_NET):
#     br-gw(osnd-gw), gw0(osnd-gw) and gw1(osnd-gwp) form the network on the gateway that
#     is connected to the gateway proxy
#   satellite terminal network (ST_LAN_NET):
#     br-st(osnd-st), st0(osnd-st) and st1(osnd-stp) form the network on the satellite terminal
#     that is connected to the satellite terminal proxy
#   server network (SV_LAN_NET):
#     gw2(osnd-gwp) and gw3(osnd-sv) form the network on the gateway that is connected
#     to the application server.
#   client network (CL_LAN_NET):
#     st3(osnd-cl) and st2(osnd-stp) form the network on the satellite terminal that is
#     connected to the application client.

# _osnd_setup_add_namespaces
# Create the namespaces and all interfaces within them.
function _osnd_setup_add_namespaces() {
	log D "Creating namespaces"

	# Add namespaces
	sudo ip netns add osnd-cl
	sudo ip netns add osnd-stp
	sudo ip netns add osnd-st
	sudo ip netns add osnd-emu
	sudo ip netns add osnd-sat
	sudo ip netns add osnd-gw
	sudo ip netns add osnd-gwp
	sudo ip netns add osnd-sv

	# Add links and bridges
	sudo ip netns exec osnd-cl ip link add st3 type veth peer name st2 netns osnd-stp
	sudo ip netns exec osnd-stp ip link add st1 type veth peer name st0 netns osnd-st
	sudo ip netns exec osnd-emu ip link add emu0l type veth peer name emu0 netns osnd-sat
	sudo ip netns exec osnd-emu ip link add emu1l type veth peer name emu1 netns osnd-gw
	sudo ip netns exec osnd-emu ip link add emu2l type veth peer name emu2 netns osnd-st
	sudo ip netns exec osnd-gwp ip link add gw1 type veth peer name gw0 netns osnd-gw
	sudo ip netns exec osnd-sv ip link add gw3 type veth peer name gw2 netns osnd-gwp

	sudo ip netns exec osnd-st ip link add br-st address ${BR_ST_MAC} type bridge
	sudo ip netns exec osnd-emu ip link add br-emu address ${BR_EMU_MAC} type bridge
	sudo ip netns exec osnd-gw ip link add br-gw address ${BR_GW_MAC} type bridge

	sudo ip netns exec osnd-st ip tuntap add mode tap tap-st
	sudo ip netns exec osnd-st ip link set tap-st address ${BR_ST_MAC}
	sudo ip netns exec osnd-gw ip tuntap add mode tap tap-gw
	sudo ip netns exec osnd-gw ip link set tap-gw address ${BR_GW_MAC}

	# Connect links via bridges
	sudo ip netns exec osnd-emu ip link set emu0l master br-emu
	sudo ip netns exec osnd-emu ip link set emu1l master br-emu
	sudo ip netns exec osnd-emu ip link set emu2l master br-emu

	sudo ip netns exec osnd-st ip link set tap-st master br-st
	sudo ip netns exec osnd-gw ip link set tap-gw master br-gw
}

# _osnd_setup_ip_config()
function _osnd_setup_ip_config() {
	log D "Configuring ip addresses and routes"

	# Enable IP Forwarding
	sudo ip netns exec osnd-st sysctl -wq net.ipv4.ip_forward=1
	sudo ip netns exec osnd-stp sysctl -wq net.ipv4.ip_forward=1
	sudo ip netns exec osnd-gwp sysctl -wq net.ipv4.ip_forward=1
	sudo ip netns exec osnd-gw sysctl -wq net.ipv4.ip_forward=1

	# Configure IP addresses
	sudo ip netns exec osnd-cl ip addr add ${CL_LAN_CLIENT_IP} dev st3
	sudo ip netns exec osnd-stp ip addr add ${CL_LAN_ROUTER_IP} dev st2
	sudo ip netns exec osnd-stp ip addr add ${ST_LAN_PROXY_IP} dev st1
	sudo ip netns exec osnd-st ip addr add ${ST_LAN_ROUTER_IP} dev st0
	sudo ip netns exec osnd-st ip addr add ${OVERLAY_ST_IP} dev br-st
	sudo ip netns exec osnd-st ip addr add ${EMU_ST_IP} dev emu2
	sudo ip netns exec osnd-sat ip addr add ${EMU_SAT_IP} dev emu0
	sudo ip netns exec osnd-gw ip addr add ${EMU_GW_IP} dev emu1
	sudo ip netns exec osnd-gw ip addr add ${OVERLAY_GW_IP} dev br-gw
	sudo ip netns exec osnd-gw ip addr add ${GW_LAN_ROUTER_IP} dev gw0
	sudo ip netns exec osnd-gwp ip addr add ${GW_LAN_PROXY_IP} dev gw1
	sudo ip netns exec osnd-gwp ip addr add ${SV_LAN_ROUTER_IP} dev gw2
	sudo ip netns exec osnd-sv ip addr add ${SV_LAN_SERVER_IP} dev gw3

	# Set ifaces up
	sudo ip netns exec osnd-cl ip link set st3 up
	sudo ip netns exec osnd-stp ip link set st2 up
	sudo ip netns exec osnd-stp ip link set st1 up
	sudo ip netns exec osnd-st ip link set st0 up
	sudo ip netns exec osnd-st ip link set emu2 up
	sudo ip netns exec osnd-emu ip link set emu2l up
	sudo ip netns exec osnd-emu ip link set emu0l up
	sudo ip netns exec osnd-emu ip link set emu1l up
	sudo ip netns exec osnd-sat ip link set emu0 up
	sudo ip netns exec osnd-gw ip link set emu1 up
	sudo ip netns exec osnd-gw ip link set gw0 up
	sudo ip netns exec osnd-gwp ip link set gw1 up
	sudo ip netns exec osnd-gwp ip link set gw2 up
	sudo ip netns exec osnd-sv ip link set gw3 up

	sudo ip netns exec osnd-st ip link set br-st up
	sudo ip netns exec osnd-emu ip link set br-emu up
	sudo ip netns exec osnd-gw ip link set br-gw up

	sudo ip netns exec osnd-st ip link set tap-st up
	sudo ip netns exec osnd-gw ip link set tap-gw up

	# Add routes
	sudo ip netns exec osnd-cl ip route add default via ${CL_LAN_ROUTER_IP%%/*}
	sudo ip netns exec osnd-stp ip route add default via ${ST_LAN_ROUTER_IP%%/*}
	sudo ip netns exec osnd-st ip route add ${CL_LAN_NET} via ${ST_LAN_PROXY_IP%%/*}
	sudo ip netns exec osnd-st ip route add ${GW_LAN_NET} via ${OVERLAY_GW_IP%%/*}
	sudo ip netns exec osnd-st ip route add ${SV_LAN_NET} via ${OVERLAY_GW_IP%%/*}
	sudo ip netns exec osnd-gw ip route add ${CL_LAN_NET} via ${OVERLAY_ST_IP%%/*}
	sudo ip netns exec osnd-gw ip route add ${ST_LAN_NET} via ${OVERLAY_ST_IP%%/*}
	sudo ip netns exec osnd-gw ip route add ${SV_LAN_NET} via ${GW_LAN_PROXY_IP%%/*}
	sudo ip netns exec osnd-gwp ip route add default via ${GW_LAN_ROUTER_IP%%/*}
	sudo ip netns exec osnd-sv ip route add default via ${SV_LAN_ROUTER_IP%%/*}
}

# _osnd_setup_ground_delay(delay_ms)
function _osnd_setup_ground_delay() {
	local delay_ms="$1"

	log D "Configuring ground delay"

	if [ "$delay_ms" -ne "0" ]; then
		sudo ip netns exec osnd-gwp tc qdisc replace dev gw2 handle 1:0 root netem delay ${delay_ms}ms
		sudo ip netns exec osnd-sv tc qdisc replace dev gw3 handle 1:0 root netem delay ${delay_ms}ms
	fi
}

# osnd_setup_namespaces(delay)
# Create the namespaces and all links within them for the emulation setup.
function osnd_setup_namespaces() {
	local delay="${1:-0}"

	_osnd_setup_add_namespaces
	_osnd_setup_ip_config
	_osnd_setup_ground_delay "$delay"
}

# If script is executed directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	declare -F log >/dev/null || function log() {
		local level="$1"
		local msg="$2"

		echo "[$level] $msg"
	}

	osnd_setup_namespaces "$@"
fi
