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

	export VPN_CONFIG=$(find ${OVPN_FLDR} -maxdepth 1 -name "${VPN_FILENAME}.ovpn" -print -quit)

	# If ovpn file not found in /config/openvpn or /config/wireguard then exit
	if [[ -z "${VPN_CONFIG}" ]]; then
		echo "[ERROR] Specified OpenVPN config file ${VPN_FILENAME}.ovpn not found in ${OVPN_FLDR}. Please download one from your VPN provider, make sure the file extension is '.ovpn', set the right file name prefix without .ovpn extension in config and restart this container" | ts '%Y-%m-%d %H:%M:%.S'
		# Sleep so it wont 'spam restart'
		sleep 10
		exit 1
	fi

	echo "[INFO] Specified OpenVPN config file found at ${VPN_CONFIG}" | ts '%Y-%m-%d %H:%M:%.S'

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

	vpn_protocol=$(cat "${VPN_CONFIG}" | grep -P -o -m 1 '(?<=^proto\s)[^\r\n]+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${vpn_protocol}" ]]; then
		echo "[INFO] VPN Level Protocol defined as '${vpn_protocol}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[WARNING] VPN Level Protocol not found in ${VPN_CONFIG}, assuming udp, will verify protocol set for each remote" | ts '%Y-%m-%d %H:%M:%.S'
		vpn_protocol="udp"
	fi

	# Initialize Port and Protocol List
	port_protocol_list=""

	# Read the ovpn config line by line
	while IFS= read -r line; do

		#if a line start with 'remote '
		if [[ $line =~ ^remote\  ]]; then
			# Extract IP, port, and protocol (assuming space separation)
			read -r remote_ip remote_port remote_protocol <<< "${line#*remote }"
			
			echo "[INFO] Remote IP, Port and Protocol found : '${remote_ip} : ${remote_port} : ${remote_protocol}'" | ts '%Y-%m-%d %H:%M:%.S'

			# Handle missing protocol or set it to "tcp" if "tcp-client"
			if [[ -z "$remote_protocol" ]]; then
				echo "[INFO] Protocol not found against remote assuming '${vpn_protocol}' defined at VPN level" | ts '%Y-%m-%d %H:%M:%.S'
				remote_protocol=$vpn_protocol
			elif [[ "$remote_protocol" == "tcp-client" ]]; then
				echo "[INFO] Protocol found against remote as 'tcp-client' coverting to 'tcp" | ts '%Y-%m-%d %H:%M:%.S'
				remote_protocol="tcp"
			fi
			
			# Append port and protocol to output variable
			port_protocol_list+="${remote_port}:${remote_protocol},"
		fi
	done < "${VPN_CONFIG}" 

	# Remove trailing comma (if any)
	port_protocol_list="${port_protocol_list%,}"

	# Check if any remote lines were found
	if [[ -z "$port_protocol_list" ]]; then
		echo "[ERROR] No VPN remote defined in ${VPN_CONFIG}, please check if correct ovpn file is used, Exiting..." | ts '%Y-%m-%d %H:%M:%.S'
		# Sleep so it wont 'spam restart'
		sleep 10
		exit 1
	else
		echo "[INFO] List of Ports and Protocols found in ${VPN_CONFIG} : ${port_protocol_list}" | ts '%Y-%m-%d %H:%M:%.S' 
		export VPN_PORTS_PROTOCOLS=$port_protocol_list;
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

	# split comma seperated string into list from NAME_SERVERS env variable
	IFS=',' read -ra name_server_list <<< "${NAME_SERVERS}"

	# process name servers in the list
	for name_server_item in "${name_server_list[@]}"; do
		# strip whitespace from start and end of lan_network_item
		name_server_item=$(echo "${name_server_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

		echo "[INFO] Adding ${name_server_item} to resolv.conf" | ts '%Y-%m-%d %H:%M:%.S'
		echo "nameserver ${name_server_item}" >> /etc/resolv.conf
	done

else
	echo "[WARNING] !!IMPORTANT!! You have set the VPN to disabled, your connection will NOT be secure!" | ts '%Y-%m-%d %H:%M:%.S'
fi

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
