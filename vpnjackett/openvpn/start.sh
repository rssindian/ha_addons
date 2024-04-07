#!/bin/bash
# Forked from binhex's OpenVPN dockers
set -e

#get App name from env
export APP_NAME=$(APP_NAME | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
export APP_FOLDER="/config/${APP_NAME}"
export OPENVPN_FOLDER="${APP_FOLDER}/openvpn"

#PUID and PGID can be passed from config as well
if [[ -z "${PUID}" ]]; then
	bashio::log.info "PUID not defined. Defaulting to root user" | ts '%Y-%m-%d %H:%M:%.S'
	export PUID="root"
fi

if [[ -z "${PGID}" ]]; then
	bashio::log.info "PGID not defined. Defaulting to root group" | ts '%Y-%m-%d %H:%M:%.S'
	export PGID="root"
fi

# Create the app directory 
if [[ ! -e ${APP_FOLDER}]]; then
	mkdir -p ${APP_FOLDER}
fi 

# Set permmissions and owner for files in /config/APP_NAME
set +e
chown -R "${PUID}":"${PGID}" "${APP_FOLDER}" &> /dev/null
exit_code_chown=$?
chmod -R 775 "${APP_FOLDER}" &> /dev/null
exit_code_chmod=$?
set -e

# check for presence of network interface docker0
check_network=$(ifconfig | grep docker0 || true)

# if network interface docker0 is present then we are running in host mode and thus must exit
if [[ ! -z "${check_network}" ]]; then
	bashio::log.error "Network type detected as 'Host', this will cause major issues, please stop the container and switch back to 'Bridge' mode" | ts '%Y-%m-%d %H:%M:%.S'
	# Sleep so it wont 'spam restart'
	sleep 10
	exit 1
fi

export VPN_ENABLED=$(bashio::config 'VPN_ENABLED' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
if [[ ! -z "${VPN_ENABLED}" ]]; then
	bashio::log.info "VPN_ENABLED defined as '${VPN_ENABLED}'" | ts '%Y-%m-%d %H:%M:%.S'
else
	bashio::log.warning "VPN_ENABLED not defined,(via -e VPN_ENABLED), defaulting to 'yes'" | ts '%Y-%m-%d %H:%M:%.S'
	export VPN_ENABLED="yes"
fi

 export LEGACY_IPTABLES=$(bashio::config 'LEGACY_IPTABLES' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
 iptables_version=$(iptables -V)
 bashio::log.info "The container is currently running ${iptables_version}."  | ts '%Y-%m-%d %H:%M:%.S'
 bashio::log.info "LEGACY_IPTABLES is set to '${LEGACY_IPTABLES}'" | ts '%Y-%m-%d %H:%M:%.S'
 if [[ $LEGACY_IPTABLES == "1" || $LEGACY_IPTABLES == "true" || $LEGACY_IPTABLES == "yes" ]]; then
	bashio::log.info "Setting iptables to iptables (legacy)" | ts '%Y-%m-%d %H:%M:%.S'
	update-alternatives --set iptables /usr/sbin/iptables-legacy
	iptables_version=$(iptables -V)
	bashio::log.info "The container is now running ${iptables_version}." | ts '%Y-%m-%d %H:%M:%.S'
 else
	bashio::log.info "Not making any changes to iptables version" | ts '%Y-%m-%d %H:%M:%.S'
 fi

if [[ $VPN_ENABLED == "yes" ]]; then
	export VPN_TYPE="openvpn"

	# Create the directory to store OpenVPN files
	if [[ ! -e ${OPENVPN_FOLDER} ]]; then
		mkdir -p ${OPENVPN_FOLDER}
	fi 

	# Set permmissions and owner for files in /config/APP_NAME/openvpn
	set +e
	chown -R "${PUID}":"${PGID}" "${OPENVPN_FOLDER}" &> /dev/null
	exit_code_chown=$?
	chmod -R 775 "${OPENVPN_FOLDER}" &> /dev/null
	exit_code_chmod=$?
	set -e
	if (( ${exit_code_chown} != 0 || ${exit_code_chmod} != 0 )); then
		bashio::log.warning "Unable to chown/chmod ${OPENVPN_FOLDER}/, assuming SMB mountpoint" | ts '%Y-%m-%d %H:%M:%.S'
	fi

	# Get VPN File Name
	export VPN_FILENAME=$(bashio::config 'VPN_FILENAME' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	export VPN_CONFIG="${OPENVPN_FOLDER}/${VPN_FILENAME}.ovpn"

	# If ovpn file not found in /config/APP_NAME/openvpn then exit
	if [[ -z "${VPN_CONFIG}" ]]; then
		bashio::log.error "No OpenVPN config file found in /config/openvpn/. Please download one from your VPN provider and restart this container. Make sure the file extension is '.ovpn'" | ts '%Y-%m-%d %H:%M:%.S'
		# Sleep so it wont 'spam restart'
		sleep 10
		exit 1
	else
		bashio::log.info "OpenVPN config file is found at ${VPN_CONFIG}" | ts '%Y-%m-%d %H:%M:%.S'
	fi

	# Read username and password env vars and put them in credentials.conf, then add ovpn config for credentials file
	export VPN_USERNAME=$(bashio::config 'VPN_USERNAME' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	export VPN_PASSWORD=$(bashio::config 'VPN_PASSWORD' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

	if [[ ! -z "${VPN_USERNAME}" ]] && [[ ! -z "${VPN_PASSWORD}" ]]; then
		if [[ ! -e ${OPENVPN_FOLDER}/credentials.conf ]]; then
			touch ${OPENVPN_FOLDER}/credentials.conf
		fi

		echo "${VPN_USERNAME}" > ${OPENVPN_FOLDER}/credentials.conf
		echo "${VPN_PASSWORD}" >> ${OPENVPN_FOLDER}/credentials.conf

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
		bashio::log.info "VPN remote line defined as '${vpn_remote_line}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		bashio::log.error "VPN configuration file ${VPN_CONFIG} does not contain 'remote' line, showing contents of file before exit..." | ts '%Y-%m-%d %H:%M:%.S'
		cat "${VPN_CONFIG}"
		# Sleep so it wont 'spam restart'
		sleep 10
		exit 1
	fi

	export VPN_REMOTE=$(echo "${vpn_remote_line}" | grep -P -o -m 1 '^[^\s\r\n]+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

	if [[ ! -z "${VPN_REMOTE}" ]]; then
		bashio::log.info "VPN_REMOTE defined as '${VPN_REMOTE}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		bashio::log.error "VPN_REMOTE not found in ${VPN_CONFIG}, exiting..." | ts '%Y-%m-%d %H:%M:%.S'
		# Sleep so it wont 'spam restart'
		sleep 10
		exit 1
	fi

	export VPN_PORT=$(echo "${vpn_remote_line}" | grep -P -o -m 1 '(?<=\s)\d{2,5}(?=\s)?+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

	if [[ ! -z "${VPN_PORT}" ]]; then
		bashio::log.info "VPN_PORT defined as '${VPN_PORT}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		bashio::log.error "VPN_PORT not found in ${VPN_CONFIG}, exiting..." | ts '%Y-%m-%d %H:%M:%.S'
		# Sleep so it wont 'spam restart'
		sleep 10
		exit 1
	fi

	export VPN_PROTOCOL=$(cat "${VPN_CONFIG}" | grep -P -o -m 1 '(?<=^proto\s)[^\r\n]+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${VPN_PROTOCOL}" ]]; then
		bashio::log.info "VPN_PROTOCOL defined as '${VPN_PROTOCOL}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		export VPN_PROTOCOL=$(echo "${vpn_remote_line}" | grep -P -o -m 1 'udp|tcp-client|tcp$' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
		if [[ ! -z "${VPN_PROTOCOL}" ]]; then
			bashio::log.info "VPN_PROTOCOL defined as '${VPN_PROTOCOL}'" | ts '%Y-%m-%d %H:%M:%.S'
		else
			bashio::log.warning "VPN_PROTOCOL not found in ${VPN_CONFIG}, assuming udp" | ts '%Y-%m-%d %H:%M:%.S'
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
		bashio::log.info "VPN_DEVICE_TYPE defined as '${VPN_DEVICE_TYPE}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		bashio::log.error "VPN_DEVICE_TYPE not found in ${VPN_CONFIG}, exiting..." | ts '%Y-%m-%d %H:%M:%.S'
		# Sleep so it wont 'spam restart'
		sleep 10
		exit 1
	fi

	# get values from env vars as defined by user
	export LAN_NETWORK=$(bashio::config 'LAN_NETWORK' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

	if [[ ! -z "${LAN_NETWORK}" ]]; then
		bashio::log.info "LAN_NETWORK defined as '${LAN_NETWORK}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		bashio::log.error "LAN_NETWORK not defined (via -e LAN_NETWORK), exiting..." | ts '%Y-%m-%d %H:%M:%.S'
		# Sleep so it wont 'spam restart'
		sleep 10
		exit 1
	fi

	export NAME_SERVERS=$(echo "${NAME_SERVERS}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${NAME_SERVERS}" ]]; then
		bashio::log.info "NAME_SERVERS defined as '${NAME_SERVERS}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		bashio::log.warning "NAME_SERVERS not defined (via -e NAME_SERVERS), defaulting to CloudFlare and Google name servers" | ts '%Y-%m-%d %H:%M:%.S'
		export NAME_SERVERS="1.1.1.1,8.8.8.8,1.0.0.1,8.8.4.4"
	fi

	export VPN_OPTIONS=$(echo "${VPN_OPTIONS}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${VPN_OPTIONS}" ]]; then
		bashio::log.info "VPN_OPTIONS defined as '${VPN_OPTIONS}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		bashio::log.info "VPN_OPTIONS not defined (via -e VPN_OPTIONS)" | ts '%Y-%m-%d %H:%M:%.S'
		export VPN_OPTIONS=""
	fi

elif [[ $VPN_ENABLED == "no" ]]; then
	bashio::log.warning "!!IMPORTANT!! You have set the VPN to disabled, your connection will NOT be secure!" | ts '%Y-%m-%d %H:%M:%.S'
fi


# split comma seperated string into list from NAME_SERVERS env variable
IFS=',' read -ra name_server_list <<< "${NAME_SERVERS}"

# process name servers in the list
for name_server_item in "${name_server_list[@]}"; do
	# strip whitespace from start and end of lan_network_item
	name_server_item=$(echo "${name_server_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

	bashio::log.info "Adding ${name_server_item} to resolv.conf" | ts '%Y-%m-%d %H:%M:%.S'
	echo "nameserver ${name_server_item}" >> /etc/resolv.conf
done


if [[ $VPN_ENABLED == "yes" ]]; then
	bashio::log.info "Starting OpenVPN..." | ts '%Y-%m-%d %H:%M:%.S'
	cd ${OPENVPN_FOLDER}
	exec openvpn --pull-filter ignore route-ipv6 --pull-filter ignore ifconfig-ipv6 --config "${VPN_CONFIG}" &
	exec /bin/bash /etc/jackett/iptables.sh
else
	exec /bin/bash /etc/jackett/start.sh
fi
