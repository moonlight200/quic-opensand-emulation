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
#     veth2(ns1), veth5(ns3) and veth7(ns4) are all directly linked via br1(ns2)
#     they form the network that the emulation of the satellite links runs on
#   overlay network (OVERLAY_NET):
#     br0(ns0) and br2(ns4) are connected through the overlay network built
#     with opensand. Each bridge is connected to a tap interface, that is
#     used with the opensand entity running in that namespace.
#   server network (GW_LAN_NET):
#     veth8(ns4) and veth9(ns5) form the network on the gateway that is connected
#     to the application server.
#   client network (ST_LAN_NET):
#     veth0(ns0) and veth1(ns1) form the network on the satellite terminal that is
#     connected to the application client.

EMU_NET="10.0.0.0/24"
EMU_GW_IP="10.0.0.1/24"
EMU_ST_IP="10.0.0.2/24"
EMU_SAT_IP="10.0.0.254/24"

OVERLAY_NET="10.1.0.0/24"
OVERLAY_GW_IP="10.1.0.1/24"
OVERLAY_ST_IP="10.1.0.2/24"

GW_LAN_NET="10.155.8.0/24"
GW_LAN_ROUTER_IP="10.115.8.1/24"
GW_LAN_SERVER_IP="10.115.8.10/24"

ST_LAN_NET="192.168.3.0/24"
ST_LAN_ROUTER_IP="192.168.3.1/24"
ST_LAN_CLIENT_IP="192.168.3.24/24"

BR_ST_MAC="de:ad:be:ef:00:01"
BR_EMU_MAC="de:ad:be:ef:00:ff"
BR_GW_MAC="de:ad:be:ef:00:00"

# Add namespaces
ip netns add ns0
ip netns add ns1
ip netns add ns2
ip netns add ns3
ip netns add ns4
ip netns add ns5

# Add links and bridges
ip netns exec ns0 ip link add veth0 type veth peer name veth1 netns ns1
ip netns exec ns1 ip link add veth2 type veth peer name veth3 netns ns2
ip netns exec ns2 ip link add veth4 type veth peer name veth5 netns ns3
ip netns exec ns2 ip link add veth6 type veth peer name veth7 netns ns4
ip netns exec ns4 ip link add veth8 type veth peer name veth9 netns ns5

ip netns exec ns1 ip link add br0 address ${BR_ST_MAC} type bridge
ip netns exec ns2 ip link add br1 address ${BR_EMU_MAC} type bridge
ip netns exec ns4 ip link add br2 address ${BR_GW_MAC} type bridge

ip netns exec ns1 ip tuntap add mode tap tap0
ip netns exec ns4 ip tuntap add mode tap tap1

for i in $(seq 0 5); do
	# Disable IPv6
	ip netns exec ns${i} sysctl -wq net.ipv6.conf.all.disable_ipv6=1
	ip netns exec ns${i} sysctl -wq net.ipv6.conf.default.disable_ipv6=1
done
ip netns exec ns1 sysctl -wq net.ipv4.ip_forward=1
ip netns exec ns4 sysctl -wq net.ipv4.ip_forward=1

# Connect links via bridges
ip netns exec ns2 ip link set veth3 master br1
ip netns exec ns2 ip link set veth4 master br1
ip netns exec ns2 ip link set veth6 master br1

ip netns exec ns1 ip link set tap0 master br0
ip netns exec ns4 ip link set tap1 master br2

# Configure IP addresses
ip netns exec ns0 ip addr add ${ST_LAN_CLIENT_IP} dev veth0
ip netns exec ns1 ip addr add ${ST_LAN_ROUTER_IP} dev veth1
ip netns exec ns1 ip addr add ${OVERLAY_ST_IP} dev br0
ip netns exec ns1 ip addr add ${EMU_ST_IP} dev veth2
ip netns exec ns3 ip addr add ${EMU_SAT_IP} dev veth5
ip netns exec ns4 ip addr add ${EMU_GW_IP} dev veth7
ip netns exec ns4 ip addr add ${OVERLAY_GW_IP} dev br2
ip netns exec ns4 ip addr add ${GW_LAN_ROUTER_IP} dev veth8
ip netns exec ns5 ip addr add ${GW_LAN_SERVER_IP} dev veth9

# Set ifaces up
ip netns exec ns0 ip link set veth0 up
ip netns exec ns1 ip link set veth1 up
ip netns exec ns1 ip link set veth2 up
ip netns exec ns2 ip link set veth3 up
ip netns exec ns2 ip link set veth4 up
ip netns exec ns2 ip link set veth6 up
ip netns exec ns3 ip link set veth5 up
ip netns exec ns4 ip link set veth7 up
ip netns exec ns4 ip link set veth8 up
ip netns exec ns5 ip link set veth9 up

ip netns exec ns1 ip link set br0 up
ip netns exec ns2 ip link set br1 up
ip netns exec ns4 ip link set br2 up

ip netns exec ns1 ip link set tap0 up
ip netns exec ns4 ip link set tap1 up

# Add routes
ip netns exec ns0 ip route add default via ${ST_LAN_ROUTER_IP%%/*}
ip netns exec ns1 ip route add ${GW_LAN_NET} via ${OVERLAY_GW_IP%%/*}
ip netns exec ns4 ip route add ${ST_LAN_NET} via ${OVERLAY_ST_IP%%/*}
ip netns exec ns5 ip route add default via ${GW_LAN_ROUTER_IP%%/*}

