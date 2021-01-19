#!/bin/bash

# Setup networking namespaces for OpenSand emulation
# Namespaces:
#   ns0: client
#   ns1: satellite terminal
#   ns2: emulation network
#   ns3: satelite
#   ns4: gateway
#   ns5: server
# Connection overview:
#   emulation network (EMU_NET):
#     emu2(ns1), emu0(ns3) and emu1(ns4) are all directly linked via bremu(ns2)
#     they form the network that the emulation of the satellite links runs on
#   overlay network (OVERLAY_NET):
#     brst(ns0) and brgw(ns4) are connected through the overlay network built
#     with opensand. Each bridge is connected to a tap interface, that is
#     used with the opensand entity running in that namespace.
#   server network (GW_LAN_NET):
#     gw0(ns4) and gw1(ns5) form the network on the gateway that is connected
#     to the application server.
#   client network (ST_LAN_NET):
#     st1(ns0) and st0(ns1) form the network on the satellite terminal that is
#     connected to the application client.

EMU_NET="10.3.3.0/24"
EMU_GW_IP="10.3.3.1/24"
EMU_ST_IP="10.3.3.2/24"
EMU_SAT_IP="10.3.3.254/24"

#OVERLAY_NET_IPV6="fd81::/64"
OVERLAY_NET="10.81.81.0/24"
OVERLAY_GW_IP="10.81.81.1/24"
OVERLAY_ST_IP="10.81.81.2/24"

#GW_LAN_NET_IPV6="fd00:10:115:8::/64"
GW_LAN_NET="10.115.8.0/24"
GW_LAN_ROUTER_IP="10.115.8.1/24"
GW_LAN_SERVER_IP="10.115.8.10/24"

#ST_LAN_NET_IPV6="fd00:192:168:3::/64"
ST_LAN_NET="192.168.3.0/24"
ST_LAN_ROUTER_IP="192.168.3.1/24"
ST_LAN_CLIENT_IP="192.168.3.24/24"

BR_ST_MAC="de:ad:be:ef:00:02"
BR_EMU_MAC="de:ad:be:ef:00:ff"
BR_GW_MAC="de:ad:be:ef:00:01"

# Add namespaces
sudo ip netns add ns0
sudo ip netns add ns1
sudo ip netns add ns2
sudo ip netns add ns3
sudo ip netns add ns4
sudo ip netns add ns5

# Add links and bridges
sudo ip netns exec ns0 ip link add st1 type veth peer name st0 netns ns1
sudo ip netns exec ns1 ip link add emu2 type veth peer name emu2l0 netns ns2
sudo ip netns exec ns2 ip link add emu0l0 type veth peer name emu0 netns ns3
sudo ip netns exec ns2 ip link add emu1l0 type veth peer name emu1 netns ns4
sudo ip netns exec ns4 ip link add gw0 type veth peer name gw1 netns ns5

sudo ip netns exec ns1 ip link add brst address ${BR_ST_MAC} type bridge
sudo ip netns exec ns2 ip link add bremu address ${BR_EMU_MAC} type bridge
sudo ip netns exec ns4 ip link add brgw address ${BR_GW_MAC} type bridge

sudo ip netns exec ns1 ip tuntap add mode tap tapst
sudo ip netns exec ns1 ip link set tapst address ${BR_ST_MAC}
sudo ip netns exec ns4 ip tuntap add mode tap tapgw
sudo ip netns exec ns4 ip link set tapgw address ${BR_GW_MAC}

sudo ip netns exec ns1 sysctl -wq net.ipv4.ip_forward=1
sudo ip netns exec ns4 sysctl -wq net.ipv4.ip_forward=1

# Connect links via bridges
sudo ip netns exec ns2 ip link set emu2l0 master bremu
sudo ip netns exec ns2 ip link set emu0l0 master bremu
sudo ip netns exec ns2 ip link set emu1l0 master bremu

sudo ip netns exec ns1 ip link set tapst master brst
sudo ip netns exec ns4 ip link set tapgw master brgw

# Configure IP addresses
sudo ip netns exec ns0 ip addr add ${ST_LAN_CLIENT_IP} dev st1
sudo ip netns exec ns1 ip addr add ${ST_LAN_ROUTER_IP} dev st0
sudo ip netns exec ns1 ip addr add ${OVERLAY_ST_IP} dev brst
sudo ip netns exec ns1 ip addr add ${EMU_ST_IP} dev emu2
sudo ip netns exec ns3 ip addr add ${EMU_SAT_IP} dev emu0
sudo ip netns exec ns4 ip addr add ${EMU_GW_IP} dev emu1
sudo ip netns exec ns4 ip addr add ${OVERLAY_GW_IP} dev brgw
sudo ip netns exec ns4 ip addr add ${GW_LAN_ROUTER_IP} dev gw0
sudo ip netns exec ns5 ip addr add ${GW_LAN_SERVER_IP} dev gw1

# Set ifaces up
sudo ip netns exec ns0 ip link set st1 up
sudo ip netns exec ns1 ip link set st0 up
sudo ip netns exec ns1 ip link set emu2 up
sudo ip netns exec ns2 ip link set emu2l0 up
sudo ip netns exec ns2 ip link set emu0l0 up
sudo ip netns exec ns2 ip link set emu1l0 up
sudo ip netns exec ns3 ip link set emu0 up
sudo ip netns exec ns4 ip link set emu1 up
sudo ip netns exec ns4 ip link set gw0 up
sudo ip netns exec ns5 ip link set gw1 up

sudo ip netns exec ns1 ip link set brst up
sudo ip netns exec ns2 ip link set bremu up
sudo ip netns exec ns4 ip link set brgw up

sudo ip netns exec ns1 ip link set tapst up
sudo ip netns exec ns4 ip link set tapgw up

# Add routes
sudo ip netns exec ns0 ip route add default via ${ST_LAN_ROUTER_IP%%/*}
sudo ip netns exec ns1 ip route add ${GW_LAN_NET} via ${OVERLAY_GW_IP%%/*}
sudo ip netns exec ns4 ip route add ${ST_LAN_NET} via ${OVERLAY_ST_IP%%/*}
sudo ip netns exec ns5 ip route add default via ${GW_LAN_ROUTER_IP%%/*}

