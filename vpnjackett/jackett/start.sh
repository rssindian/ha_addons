#!/bin/bash

export JACKET_FOLDER="${APP_FOLDER}/jackett"
export JACKET_CONFIG_FOLDER="${JACKET_FOLDER}/config"
export JACKET_MAGNETS_FOLDER="${JACKET_FOLDER}/magnets"

# Check if /config/APP_NAME/Jackett exists, if not make the directory
if [[ ! -e ${JACKET_FOLDER}]]; then
	mkdir -p ${JACKET_FOLDER}
fi

#check if jackett sub directories exists
if [[ ! -e ${JACKET_CONFIG_FOLDER}]]; then
	mkdir -p ${JACKET_CONFIG_FOLDER}
fi
if [[ ! -e ${JACKET_MAGNETS_FOLDER}]]; then
	mkdir -p ${JACKET_MAGNETS_FOLDER}
fi

# Set the correct rights accordingly to the PUID and PGID on /config/APP_NAME/Jackett
set +e
chown -R "${PUID}":"${PGID}" "${JACKET_FOLDER}" &> /dev/null
exit_code_chown=$?
chmod -R 775 "${JACKET_FOLDER}" &> /dev/null
exit_code_chmod=$?
set -e

export JACKET_CONFIG_FILE = "${JACKET_CONFIG_FOLDER}/ServerConfig.json"

# Check if ServerConfig.json exists, if not, copy the template over
if [ ! -e ${JACKET_CONFIG_FILE} ]; then
	bashio::log.info "ServerConfig.json is missing, this is normal for the first launch! Copying template" | ts '%Y-%m-%d %H:%M:%.S'
	cp /etc/jackett/ServerConfig.json ${JACKET_CONFIG_FILE}
	chown ${PUID}:${PGID} ${JACKET_CONFIG_FILE}
	chmod 755 ${JACKET_CONFIG_FILE}
fi

# Check if the PGID exists, if not create the group with the name 'jackett'
grep $"${PGID}:" /etc/group > /dev/null 2>&1
if [ $? -eq 0 ]; then
	bashio::log.info "A group with PGID $PGID already exists in /etc/group, nothing to do." | ts '%Y-%m-%d %H:%M:%.S'
else
	bashio::log.info "A group with PGID $PGID does not exist, adding a group called 'jackett' with PGID $PGID" | ts '%Y-%m-%d %H:%M:%.S'
	groupadd -g $PGID jackett
fi

# Check if the PUID exists, if not create the user with the name 'jackett', with the correct group
grep $"${PUID}:" /etc/passwd > /dev/null 2>&1
if [ $? -eq 0 ]; then
	bashio::log.info "An user with PUID $PUID already exists in /etc/passwd, nothing to do." | ts '%Y-%m-%d %H:%M:%.S'
else
	bashio::log.info "An user with PUID $PUID does not exist, adding an user called 'jackett user' with PUID $PUID" | ts '%Y-%m-%d %H:%M:%.S'
	useradd -c "jackett user" -g $PGID -u $PUID jackett
fi

# Set the umask
if [[ ! -z "${UMASK}" ]]; then
	bashio::log.info "UMASK defined as '${UMASK}'" | ts '%Y-%m-%d %H:%M:%.S'
	export UMASK=$(echo "${UMASK}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
else
	bashio::log.warning "UMASK not defined (via -e UMASK), defaulting to '002'" | ts '%Y-%m-%d %H:%M:%.S'
	export UMASK="002"
fi

# Set an API Key
# An API Key is also required for setting a password, that is why this script does it before Jackett initially launces
# Generation of the API Key is obviously the same as how Jackett itself would do it.
APIKey=$(cat ${JACKET_CONFIG_FILE} | jq -r '.APIKey')
if [ -z ${APIKey} ]; then
	bashio::log.info "No APIKey in the ServerConfig.json, this is normal for the first launch" | ts '%Y-%m-%d %H:%M:%.S'
	bashio::log.info "Generating new APIKey" | ts '%Y-%m-%d %H:%M:%.S'
	NewAPIKey=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 32 | head -n 1)
	cat ${JACKET_CONFIG_FILE} | jq --arg NewKey "$NewAPIKey" '.APIKey = "\($NewKey)"' | sponge ${JACKET_CONFIG_FILE}
	bashio::log.info "Generated APIKey: ${NewAPIKey}" | ts '%Y-%m-%d %H:%M:%.S'
fi

# Read the current password hash to compare it later, and to see if it is empty to give a warning
current_hash=$(cat ${JACKET_CONFIG_FILE} | jq -r '.AdminPassword')

#get wbui password from config
export WEBUI_PASSWORD=$(bashio::config 'WEBUI_PASSWORD' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
if [[ ${current_hash} == 'null' && -z "${WEBUI_PASSWORD}" ]]; then
	bashio::log.warning "There is no password set via Jackett's web interface or via configuration!" | ts '%Y-%m-%d %H:%M:%.S'
	bashio::log.warning "Anyone on your network could access Jackett without authentication!" | ts '%Y-%m-%d %H:%M:%.S'
	bashio::log.warning "Or even the whole world if you did port-fortwarding!" | ts '%Y-%m-%d %H:%M:%.S'
	bashio::log.warning "It's adviced to set one via either the web interface or as environment variable" | ts '%Y-%m-%d %H:%M:%.S'
fi

if [ ! -z "${WEBUI_PASSWORD}" ]; then
	# Test to see if the password has valid characters, prinf or iconv exists with code 1 if there are invalid characters
	printf "${WEBUI_PASSWORD}" > /dev/null 2>&1
	printf_status=$?
	printf "${WEBUI_PASSWORD}" | iconv -t utf16le > /dev/null 2>&1
	iconv_status=$?
	if [[ "${printf_status}" -eq 1 || "${iconv_status}" -eq 1 ]]; then
		bashio::log.error "The WEBUI_PASSWORD environment variable contains unsupported characters." | ts '%Y-%m-%d %H:%M:%.S'
		# Sleep so it wont 'spam restart'
		sleep 5
		exit 1
	fi

	bashio::log.info "Generating password hash" | ts '%Y-%m-%d %H:%M:%.S'
	# Read the API Key of Jackett and append it after the password. The API Key is used as the salt by Jackett.
	# Obviously it is required to generate password the exact same was as Jackett does, else you can not log in.
	APIKey=$(cat ${JACKET_CONFIG_FILE} | jq -r '.APIKey')
	password_apikey=$(printf "${WEBUI_PASSWORD}"${APIKey})
	# Hashing the password
	password_hash=$(printf ${password_apikey} | iconv -t utf16le | sha512sum | cut -c-128)

	# If the password hash matches the current password in the config, there is no need to push it again into the config file
	if [ ! ${current_hash} == ${password_hash} ]; then
		cat ${JACKET_CONFIG_FILE} | jq --arg Password "$password_hash" '.AdminPassword = "\($Password)"' | sponge ${JACKET_CONFIG_FILE}
	else
		bashio::log.info "Password hashes match, nothing to change." | ts '%Y-%m-%d %H:%M:%.S'
	fi
fi

# Start Jackett
bashio::log.info "Starting Jackett daemon..." | ts '%Y-%m-%d %H:%M:%.S'
/bin/bash /etc/jackett/jackett.init start &
chmod -R 755 ${JACKET_CONFIG_FOLDER}

# Wait a second for it to start up and get the process id
sleep 1
jackettpid=$(pgrep -o -x jackett) 
bashio::log.info "Jackett PID: $jackettpid" | ts '%Y-%m-%d %H:%M:%.S'

# If the process exists, make sure that the log file has the proper rights and start the health check
if [ -e /proc/$jackettpid ]; then
	if [[ -e ${JACKET_CONFIG_FOLDER}/Logs/log.txt ]]; then
		chmod 775 ${JACKET_CONFIG_FOLDER}/Logs/log.txt
	fi
	
	# Set some variables that are used
	HOST=$(bashio::config 'HEALTH_CHECK_HOST' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	DEFAULT_HOST="one.one.one.one"
	INTERVAL=$(bashio::config 'HEALTH_CHECK_INTERVAL' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	DEFAULT_INTERVAL=300
	DEFAULT_HEALTH_CHECK_AMOUNT=1
	
	# If host is zero (not set) default it to the DEFAULT_HOST variable
	if [[ -z "${HOST}" ]]; then
		bashio::log.info "HEALTH_CHECK_HOST is not set. For now using default host ${DEFAULT_HOST}" | ts '%Y-%m-%d %H:%M:%.S'
		HOST=${DEFAULT_HOST}
	fi

	# If HEALTH_CHECK_INTERVAL is zero (not set) default it to DEFAULT_INTERVAL
	if [[ -z "${HEALTH_CHECK_INTERVAL}" ]]; then
		bashio::log.info "HEALTH_CHECK_INTERVAL is not set. For now using default interval of ${DEFAULT_INTERVAL}" | ts '%Y-%m-%d %H:%M:%.S'
		INTERVAL=${DEFAULT_INTERVAL}
	fi
	
	# If HEALTH_CHECK_SILENT is zero (not set) default it to supression
	if [[ -z "${HEALTH_CHECK_SILENT}" ]]; then
		bashio::log.info "HEALTH_CHECK_SILENT is not set. Because this variable is not set, it will be supressed by default" | ts '%Y-%m-%d %H:%M:%.S'
		HEALTH_CHECK_SILENT=1
	fi

	if [ ! -z ${RESTART_CONTAINER} ]; then
		bashio::log.info "RESTART_CONTAINER defined as '${RESTART_CONTAINER}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		bashio::log.warning "RESTART_CONTAINER not defined,(via -e RESTART_CONTAINER), defaulting to 'yes'" | ts '%Y-%m-%d %H:%M:%.S'
		export RESTART_CONTAINER="yes"
	fi

	# If HEALTH_CHECK_AMOUNT is zero (not set) default it to DEFAULT_HEALTH_CHECK_AMOUNT
	if [[ -z ${HEALTH_CHECK_AMOUNT} ]]; then
		bashio::log.info "HEALTH_CHECK_AMOUNT is not set. For now using default interval of ${DEFAULT_HEALTH_CHECK_AMOUNT}" | ts '%Y-%m-%d %H:%M:%.S'
		HEALTH_CHECK_AMOUNT=${DEFAULT_HEALTH_CHECK_AMOUNT}
	fi
	bashio::log.info "HEALTH_CHECK_AMOUNT is set to ${HEALTH_CHECK_AMOUNT}" | ts '%Y-%m-%d %H:%M:%.S'

	while true; do
		# Ping uses both exit codes 1 and 2. Exit code 2 cannot be used for docker health checks, therefore we use this script to catch error code 2
		ping -c ${HEALTH_CHECK_AMOUNT} $HOST > /dev/null 2>&1
		STATUS=$?
		if [[ "${STATUS}" -ne 0 ]]; then
			bashio::log.error "Network is possibly down." | ts '%Y-%m-%d %H:%M:%.S'
			sleep 1
			if [[ ${RESTART_CONTAINER,,} == "1" || ${RESTART_CONTAINER,,} == "true" || ${RESTART_CONTAINER,,} == "yes" ]]; then
				bashio::log.info "Restarting container." | ts '%Y-%m-%d %H:%M:%.S'
				exit 1
			fi
		fi
		if [[ ${HEALTH_CHECK_SILENT,,} == "0" || ${HEALTH_CHECK_SILENT,,} == "false" || ${HEALTH_CHECK_SILENT,,} == "no" ]]; then
			bashio::log.info "Network is up" | ts '%Y-%m-%d %H:%M:%.S'
		fi
		sleep ${INTERVAL} &
		# combine sleep background with wait so that the TERM trap above works
		wait $!
	done
else
	bashio::log.error "Jackett failed to start!" | ts '%Y-%m-%d %H:%M:%.S'
fi
