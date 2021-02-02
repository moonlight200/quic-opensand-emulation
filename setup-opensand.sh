#!/bin/bash

# _osnd_configure_opensand_orbit(orbit)
# Configures a constant delay based on the given orbit.
function _osnd_configure_opensand_orbit() {
	local orbit="$1"

	local delay_ms=-1
	case "$orbit" in
	"GEO")
		delay_ms=130
		;;
	"MEO")
		delay_ms=55
		;;
	"LEO")
		delay_ms=18
		;;
	esac

	if [ $delay_ms -lt 0 ]; then
		return
	fi

	for entity in sat gw st; do
		xmlstarlet ed -L -u "//configuration/common/global_constant_delay" -v "true" "${OSND_TMP}/config_${entity}/core_global.conf"
		xmlstarlet ed -L -u "//configuration/common/delay" -v "$delay_ms" "${OSND_TMP}/config_${entity}/core_global.conf"
	done
}

# _osnd_configure_opensand_attenuation(attenuation)
# Configures the given constant signal attenuation
function _osnd_configure_opensand_attenuation() {
	local attenuation="$1"

	if [ "$attenuation" -lt 0 ]; then
		return
	fi

	# Use "Ideal" model for up- and downlink with 20db clear_sky attenuation
	xmlstarlet ed -L -u "//configuration/uplink_physical_layer/attenuation_model_type" -v "Ideal" "${OSND_TMP}/config_st/core.conf"
	xmlstarlet ed -L -u "//configuration/uplink_physical_layer/clear_sky_condition" -v "20" "${OSND_TMP}/config_st/core.conf"
	xmlstarlet ed -L -u "//configuration/downlink_physical_layer/attenuation_model_type" -v "Ideal" "${OSND_TMP}/config_st/core.conf"
	xmlstarlet ed -L -u "//configuration/downlink_physical_layer/clear_sky_condition" -v "20" "${OSND_TMP}/config_st/core.conf"

	# Configure attenuation
	xmlstarlet ed -L -d "//@attenuation_value" \
		-s "configuration/ideal/ideal_attenuations/ideal_attenuation[@link='up']" -t 'attr' -n 'attenuation_value' -v "$attenuation" \
		-s "configuration/ideal/ideal_attenuations/ideal_attenuation[@link='down']" -t 'attr' -n 'attenuation_value' -v "$attenuation" \
		"${OSND_TMP}/config_st/plugins/ideal.conf"
}

# osnd_setup_opensand(orbit, attenuation)
function osnd_setup_opensand() {
	local orbit="$1"
	local attenuation="${2:--1}"

	# Copy configurations
	for entity in sat gw st; do
		if [ -e "${OSND_TMP}/config_${entity}" ]; then
			rm -rf "${OSND_TMP}/config_${entity}"
		fi
		cp -r "${OPENSAND_CONFIGS}/${entity}" "${OSND_TMP}/config_${entity}"
	done

	# Modify configuration based on parameter
	_osnd_configure_opensand_orbit "$orbit"
	_osnd_configure_opensand_attenuation "$attenuation"

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
