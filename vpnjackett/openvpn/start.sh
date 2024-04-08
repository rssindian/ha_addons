#!/bin/bash

# Forked from binhex's OpenVPN dockers
set -e

export APP_FLDR="/config/${APP_NAME}"
export OVPN_FLDR="${APP_FLDR}/openvpn"

# check for presence of network interface docker0
check_network=$(ifconfig | grep docker0 || true)

# if network interface docker0 is present then we are running in host mode and thus must exit
if [[ ! -z "${check_network}" ]]; then
	echo "[ERROR] Network type detected as 'Host', this will cause major issues, please stop the container and switch back to 'Bridge' mode" | ts '%Y-%m-%d %H:%M:%.S'
	# Sleep so it wont 'spam restart'
	sleep 10
	exit 1
fi

if [[ ! -z "${VPN_ENABLED}" ]]; then
	echo "[INFO] VPN_ENABLED defined as '${VPN_ENABLED}'" | ts '%Y-%m-%d %H:%M:%.S'
else
	echo "[WARNING] VPN_ENABLED not defined,(via -e VPN_ENABLED), defaulting to 'yes'" | ts '%Y-%m-%d %H:%M:%.S'
	export VPN_ENABLED="true"
fi

if [[ $VPN_ENABLED == "true" ]]; then

	#Change iptables version if required
	iptables_version=$(iptables -V)
	echo "[INFO] The container is currently running ${iptables_version}."  | ts '%Y-%m-%d %H:%M:%.S'
	echo "[INFO] LEGACY_IPTABLES is set to '${LEGACY_IPTABLES}'" | ts '%Y-%m-%d %H:%M:%.S'
	if [[ $LEGACY_IPTABLES == "1" || $LEGACY_IPTABLES == "true" || $LEGACY_IPTABLES == "yes" ]]; then
		echo "[INFO] Setting iptables to iptables (legacy)" | ts '%Y-%m-%d %H:%M:%.S'
		update-alternatives --set iptables /usr/sbin/iptables-legacy
		iptables_version=$(iptables -V)
		echo "[INFO] The container is now running ${iptables_version}." | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[INFO] Not making any changes to iptables version" | ts '%Y-%m-%d %H:%M:%.S'
	fi

	# Create the directory to store OpenVPN
	if [[ ! -e ${OVPN_FLDR} ]]; then
		mkdir -p ${OVPN_FLDR}
	fi

	# Set permmissions and owner for files in /config/openvpn or /config/wireguard directory
	set +e
	chown -R "${PUID}":"${PGID}" "${OVPN_FLDR}" &> /dev/null
	exit_code_chown=$?
	chmod -R 775 "${OVPN_FLDR}" &> /dev/null
	exit_code_chmod=$?
	set -e

	if (( ${exit_code_chown} != 0 || ${exit_code_chmod} != 0 )); then
		echo "[WARNING] Unable to chown/chmod ${OVPN_FLDR}, assuming SMB mountpoint" | ts '%Y-%m-%d %H:%M:%.S'
	fi

	export VPN_CONFIG=$(find ${OVPN_FLDR} -maxdepth 1 -name "*.ovpn" -print -quit)

	# If ovpn file not found in /config/openvpn or /config/wireguard then exit
	if [[ -z "${VPN_CONFIG}" ]]; then
		echo "[ERROR] No OpenVPN config file found in ${OVPN_FLDR}. Please download one from your VPN provider and restart this container. Make sure the file extension is '.ovpn'" | ts '%Y-%m-%d %H:%M:%.S'
		# Sleep so it wont 'spam restart'
		sleep 10
		exit 1
	fi

	echo "[INFO] OpenVPN config file is found at ${VPN_CONFIG}" | ts '%Y-%m-%d %H:%M:%.S'

	# Read username and password env vars and put them in credentials.conf, then add ovpn config for credentials file
	if [[ ! -z "${VPN_USERNAME}" ]] && [[ ! -z "${VPN_PASSWORD}" ]]; then
		if [[ ! -e ${OVPN_FLDR}/credentials.conf ]]; then
			touch ${OVPN_FLDR}/credentials.conf
		fi

		echo "${VPN_USERNAME}" > ${OVPN_FLDR}/credentials.conf
		echo "${VPN_PASSWORD}" >> ${OVPN_FLDR}/credentials.conf

		# Replace line with one that points to credentials.conf
		auth_cred_exist=$(cat "${VPN_CONFIG}" | grep -m 1 'auth-user-pass')
		if [[ ! -z "${auth_cred_exist}" ]]; then
			# Get line number of auth-user-pass
			LINE_NUM=$(grep -Fn -m 1 'auth-user-pass' "${VPN_CONFIG}" | cut -d: -f 1)
			sed -i "${LINE_NUM}s/.*/auth-user-pass credentials.conf/" "${VPN_CONFIG}"
		else
			sed -i "1s/.*/auth-user-pass credentials.conf/" "${VPN_CONFIG}"
		fi
	fi
	
	# convert CRLF (windows) to LF (unix) for ovpn
	dos2unix "${VPN_CONFIG}" 1> /dev/null
	
	# parse values from the ovpn or conf file
	export vpn_remote_line=$(cat "${VPN_CONFIG}" | grep -P -o -m 1 '(?<=^remote\s)[^\n\r]+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

	if [[ ! -z "${vpn_remote_line}" ]]; then
		echo "[INFO] VPN remote line defined as '${vpn_remote_line}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[ERROR] VPN configuration file ${VPN_CONFIG} does not contain 'remote' line, showing contents of file before exit..." | ts '%Y-%m-%d %H:%M:%.S'
		cat "${VPN_CONFIG}"
		# Sleep so it wont 'spam restart'
		sleep 10
		exit 1
	fi

	export VPN_REMOTE=$(echo "${vpn_remote_line}" | grep -P -o -m 1 '^[^\s\r\n]+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

	if [[ ! -z "${VPN_REMOTE}" ]]; then
		echo "[INFO] VPN_REMOTE defined as '${VPN_REMOTE}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[ERROR] VPN_REMOTE not found in ${VPN_CONFIG}, exiting..." | ts '%Y-%m-%d %H:%M:%.S'
		# Sleep so it wont 'spam restart'
		sleep 10
		exit 1
	fi

	export VPN_PORT=$(echo "${vpn_remote_line}" | grep -P -o -m 1 '(?<=\s)\d{2,5}(?=\s)?+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

	if [[ ! -z "${VPN_PORT}" ]]; then
		echo "[INFO] VPN_PORT defined as '${VPN_PORT}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[ERROR] VPN_PORT not found in ${VPN_CONFIG}, exiting..." | ts '%Y-%m-%d %H:%M:%.S'
		# Sleep so it wont 'spam restart'
		sleep 10
		exit 1
	fi

	export VPN_PROTOCOL=$(cat "${VPN_CONFIG}" | grep -P -o -m 1 '(?<=^proto\s)[^\r\n]+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${VPN_PROTOCOL}" ]]; then
		echo "[INFO] VPN_PROTOCOL defined as '${VPN_PROTOCOL}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		export VPN_PROTOCOL=$(echo "${vpn_remote_line}" | grep -P -o -m 1 'udp|tcp-client|tcp$' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
		if [[ ! -z "${VPN_PROTOCOL}" ]]; then
			echo "[INFO] VPN_PROTOCOL defined as '${VPN_PROTOCOL}'" | ts '%Y-%m-%d %H:%M:%.S'
		else
			echo "[WARNING] VPN_PROTOCOL not found in ${VPN_CONFIG}, assuming udp" | ts '%Y-%m-%d %H:%M:%.S'
			export VPN_PROTOCOL="udp"
		fi
	fi

	# required for use in iptables
	if [[ "${VPN_PROTOCOL}" == "tcp-client" ]]; then
		export VPN_PROTOCOL="tcp"
	fi


	VPN_DEVICE_TYPE=$(cat "${VPN_CONFIG}" | grep -P -o -m 1 '(?<=^dev\s)[^\r\n\d]+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${VPN_DEVICE_TYPE}" ]]; then
		export VPN_DEVICE_TYPE="${VPN_DEVICE_TYPE}0"
		echo "[INFO] VPN_DEVICE_TYPE defined as '${VPN_DEVICE_TYPE}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[ERROR] VPN_DEVICE_TYPE not found in ${VPN_CONFIG}, exiting..." | ts '%Y-%m-%d %H:%M:%.S'
		# Sleep so it wont 'spam restart'
		sleep 10
		exit 1
	fi

	# get values from env vars as defined by user
	if [[ ! -z "${LAN_NETWORK}" ]]; then
		echo "[INFO] LAN_NETWORK defined as '${LAN_NETWORK}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[ERROR] LAN_NETWORK not defined (via -e LAN_NETWORK), exiting..." | ts '%Y-%m-%d %H:%M:%.S'
		# Sleep so it wont 'spam restart'
		sleep 10
		exit 1
	fi

	if [[ ! -z "${NAME_SERVERS}" ]]; then
		echo "[INFO] NAME_SERVERS defined as '${NAME_SERVERS}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[WARNING] NAME_SERVERS not defined (via -e NAME_SERVERS), defaulting to CloudFlare and Google name servers" | ts '%Y-%m-%d %H:%M:%.S'
		export NAME_SERVERS="1.1.1.1,8.8.8.8,1.0.0.1,8.8.4.4"
	fi

else
	echo "[WARNING] !!IMPORTANT!! You have set the VPN to disabled, your connection will NOT be secure!" | ts '%Y-%m-%d %H:%M:%.S'
fi


# split comma seperated string into list from NAME_SERVERS env variable
IFS=',' read -ra name_server_list <<< "${NAME_SERVERS}"

# process name servers in the list
for name_server_item in "${name_server_list[@]}"; do
	# strip whitespace from start and end of lan_network_item
	name_server_item=$(echo "${name_server_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

	echo "[INFO] Adding ${name_server_item} to resolv.conf" | ts '%Y-%m-%d %H:%M:%.S'
	echo "nameserver ${name_server_item}" >> /etc/resolv.conf
done

if [[ -z "${PUID}" ]]; then
	echo "[INFO] PUID not defined. Defaulting to root user" | ts '%Y-%m-%d %H:%M:%.S'
	export PUID="root"
fi

if [[ -z "${PGID}" ]]; then
	echo "[INFO] PGID not defined. Defaulting to root group" | ts '%Y-%m-%d %H:%M:%.S'
	export PGID="root"
fi

if [[ $VPN_ENABLED == "true" ]]; then
	echo "[INFO] Starting OpenVPN..." | ts '%Y-%m-%d %H:%M:%.S'
	cd ${OVPN_FLDR}
	exec openvpn --pull-filter ignore route-ipv6 --pull-filter ignore ifconfig-ipv6 --config "${VPN_CONFIG}" &
	exec /bin/bash /etc/jackett/iptables.sh
else
	exec /bin/bash /etc/jackett/start.sh
fi
