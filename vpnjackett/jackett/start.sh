#!/bin/bash

export JKT_FLDR="${APP_FLDR}/Jackett"

# Check if /config/APP_NAME/Jackett exists, if not make the directory
if [[ ! -e ${JKT_FLDR} ]]; then
	mkdir -p ${JKT_FLDR}
fi

# Check if /config/APP_NAME/Jackett/config exists, if not make the directory
if [[ ! -e ${JKT_FLDR} ]]; then
	mkdir -p ${JKT_FLDR}
fi

# Check if /config/APP_NAME/Jackett/magnets exists, if not make the directory
if [[ ! -e ${JKT_FLDR} ]]; then
	mkdir -p ${JKT_FLDR}
fi

# Set the correct rights accordingly to the PUID and PGID on /config/APP_NAME/Jackett
chown -R ${PUID}:${PGID} ${JKT_FLDR}

# Check if ServerConfig.json exists, if not, copy the template over
if [ ! -e ${JKT_FLDR}/ServerConfig.json ]; then
	echo "[INFO] ServerConfig.json is missing, this is normal for the first launch! Copying template" | ts '%Y-%m-%d %H:%M:%.S'
	cp /etc/jackett/ServerConfig.json ${JKT_FLDR}/ServerConfig.json
	chmod 755 ${JKT_FLDR}/ServerConfig.json
	chown ${PUID}:${PGID} ${JKT_FLDR}/ServerConfig.json
fi

# Check if the PGID exists, if not create the group with the name 'jackett'
grep $"${PGID}:" /etc/group > /dev/null 2>&1
if [ $? -eq 0 ]; then
	echo "[INFO] A group with PGID $PGID already exists in /etc/group, nothing to do." | ts '%Y-%m-%d %H:%M:%.S'
else
	echo "[INFO] A group with PGID $PGID does not exist, adding a group called 'jackett' with PGID $PGID" | ts '%Y-%m-%d %H:%M:%.S'
	groupadd -g $PGID jackett
fi

# Check if the PUID exists, if not create the user with the name 'jackett', with the correct group
grep $"${PUID}:" /etc/passwd > /dev/null 2>&1
if [ $? -eq 0 ]; then
	echo "[INFO] An user with PUID $PUID already exists in /etc/passwd, nothing to do." | ts '%Y-%m-%d %H:%M:%.S'
else
	echo "[INFO] An user with PUID $PUID does not exist, adding an user called 'jackett user' with PUID $PUID" | ts '%Y-%m-%d %H:%M:%.S'
	useradd -c "jackett user" -g $PGID -u $PUID jackett
fi

# Set the umask
if [[ ! -z "${UMASK}" ]]; then
	echo "[INFO] UMASK defined as '${UMASK}'" | ts '%Y-%m-%d %H:%M:%.S'
	export UMASK=$(echo "${UMASK}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
else
	echo "[WARNING] UMASK not defined (via -e UMASK), defaulting to '002'" | ts '%Y-%m-%d %H:%M:%.S'
	export UMASK="002"
fi

# Set an API Key
# An API Key is also required for setting a password, that is why this script does it before Jackett initially launces
# Generation of the API Key is obviously the same as how Jackett itself would do it.
APIKey=$(cat ${JKT_FLDR}/ServerConfig.json | jq -r '.APIKey')
if [ -z ${APIKey} ]; then
	echo "[INFO] No APIKey in the ServerConfig.json, this is normal for the first launch" | ts '%Y-%m-%d %H:%M:%.S'
	echo "[INFO] Generating new APIKey" | ts '%Y-%m-%d %H:%M:%.S'
	NewAPIKey=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 32 | head -n 1)
	cat ${JKT_FLDR}/ServerConfig.json | jq --arg NewKey "$NewAPIKey" '.APIKey = "\($NewKey)"' | sponge ${JKT_FLDR}/ServerConfig.json
	echo "[INFO] Generated APIKey: ${NewAPIKey}" | ts '%Y-%m-%d %H:%M:%.S'
fi

# Read the current password hash to compare it later, and to see if it is empty to give a warning
current_hash=$(cat ${JKT_FLDR}/ServerConfig.json | jq -r '.AdminPassword')

if [[ ${current_hash} == 'null' && -z "${WEBUI_PASSWORD}" ]]; then
	echo "[WARNING] There is no password set via Jackett's web interface or as an environment variable!" | ts '%Y-%m-%d %H:%M:%.S'
	echo "[WARNING] Anyone on your network could access Jackett without authentication!" | ts '%Y-%m-%d %H:%M:%.S'
	echo "[WARNING] Or even the whole world if you did port-fortwarding!" | ts '%Y-%m-%d %H:%M:%.S'
	echo "[WARNING] It's adviced to set one via either the web interface or as environment variable" | ts '%Y-%m-%d %H:%M:%.S'
fi

if [ ! -z "${WEBUI_PASSWORD}" ]; then
	# Test to see if the password has valid characters, prinf or iconv exists with code 1 if there are invalid characters
	printf "${WEBUI_PASSWORD}" > /dev/null 2>&1
	printf_status=$?
	printf "${WEBUI_PASSWORD}" | iconv -t utf16le > /dev/null 2>&1
	iconv_status=$?
	if [[ "${printf_status}" -eq 1 || "${iconv_status}" -eq 1 ]]; then
		echo "[ERROR] The WEBUI_PASSWORD environment variable contains unsupported characters." | ts '%Y-%m-%d %H:%M:%.S'
		# Sleep so it wont 'spam restart'
		sleep 5
		exit 1
	fi

	echo "[INFO] Generating password hash" | ts '%Y-%m-%d %H:%M:%.S'
	# Read the API Key of Jackett and append it after the password. The API Key is used as the salt by Jackett.
	# Obviously it is required to generate password the exact same was as Jackett does, else you can not log in.
	APIKey=$(cat ${JKT_FLDR}/ServerConfig.json | jq -r '.APIKey')
	password_apikey=$(printf "${WEBUI_PASSWORD}"${APIKey})
	# Hashing the password
	password_hash=$(printf ${password_apikey} | iconv -t utf16le | sha512sum | cut -c-128)

	# If the password hash matches the current password in the config, there is no need to push it again into the config file
	if [ ! ${current_hash} == ${password_hash} ]; then
		cat ${JKT_FLDR}/ServerConfig.json | jq --arg Password "$password_hash" '.AdminPassword = "\($Password)"' | sponge ${JKT_FLDR}/ServerConfig.json
	else
		echo "[INFO] Password hashes match, nothing to change." | ts '%Y-%m-%d %H:%M:%.S'
	fi
fi

# Start Jackett
echo "[INFO] Starting Jackett daemon..." | ts '%Y-%m-%d %H:%M:%.S'
/bin/bash /etc/jackett/jackett.init start &
chmod -R 755 ${JKT_FLDR}

# Wait a second for it to start up and get the process id
sleep 1
jackettpid=$(pgrep -o -x jackett) 
echo "[INFO] Jackett PID: $jackettpid" | ts '%Y-%m-%d %H:%M:%.S'

# If the process exists, make sure that the log file has the proper rights and start the health check
if [ -e /proc/$jackettpid ]; then
	if [[ -e ${JKT_FLDR}/log.txt ]]; then
		chmod 775 ${JKT_FLDR}/log.txt
	fi
	
	# Set some variables that are used
	HOST=${HEALTH_CHECK_HOST}
	DEFAULT_HOST="one.one.one.one"
	INTERVAL=${HEALTH_CHECK_INTERVAL}
	DEFAULT_INTERVAL=300
	DEFAULT_HEALTH_CHECK_AMOUNT=1
	
	# If host is zero (not set) default it to the DEFAULT_HOST variable
	if [[ -z "${HOST}" ]]; then
		echo "[INFO] HEALTH_CHECK_HOST is not set. For now using default host ${DEFAULT_HOST}" | ts '%Y-%m-%d %H:%M:%.S'
		HOST=${DEFAULT_HOST}
	fi

	# If HEALTH_CHECK_INTERVAL is zero (not set) default it to DEFAULT_INTERVAL
	if [[ -z "${HEALTH_CHECK_INTERVAL}" ]]; then
		echo "[INFO] HEALTH_CHECK_INTERVAL is not set. For now using default interval of ${DEFAULT_INTERVAL}" | ts '%Y-%m-%d %H:%M:%.S'
		INTERVAL=${DEFAULT_INTERVAL}
	fi
	
	# If HEALTH_CHECK_SILENT is zero (not set) default it to supression
	if [[ -z "${HEALTH_CHECK_SILENT}" ]]; then
		echo "[INFO] HEALTH_CHECK_SILENT is not set. Because this variable is not set, it will be supressed by default" | ts '%Y-%m-%d %H:%M:%.S'
		HEALTH_CHECK_SILENT=1
	fi

	if [ ! -z ${RESTART_CONTAINER} ]; then
		echo "[INFO] RESTART_CONTAINER defined as '${RESTART_CONTAINER}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[WARNING] RESTART_CONTAINER not defined,(via -e RESTART_CONTAINER), defaulting to 'yes'" | ts '%Y-%m-%d %H:%M:%.S'
		export RESTART_CONTAINER="yes"
	fi

	# If HEALTH_CHECK_AMOUNT is zero (not set) default it to DEFAULT_HEALTH_CHECK_AMOUNT
	if [[ -z ${HEALTH_CHECK_AMOUNT} ]]; then
		echo "[INFO] HEALTH_CHECK_AMOUNT is not set. For now using default interval of ${DEFAULT_HEALTH_CHECK_AMOUNT}" | ts '%Y-%m-%d %H:%M:%.S'
		HEALTH_CHECK_AMOUNT=${DEFAULT_HEALTH_CHECK_AMOUNT}
	fi
	echo "[INFO] HEALTH_CHECK_AMOUNT is set to ${HEALTH_CHECK_AMOUNT}" | ts '%Y-%m-%d %H:%M:%.S'

	while true; do
		# Ping uses both exit codes 1 and 2. Exit code 2 cannot be used for docker health checks, therefore we use this script to catch error code 2
		ping -c ${HEALTH_CHECK_AMOUNT} $HOST > /dev/null 2>&1
		STATUS=$?
		if [[ "${STATUS}" -ne 0 ]]; then
			echo "[ERROR] Network is possibly down." | ts '%Y-%m-%d %H:%M:%.S'
			sleep 1
			if [[ ${RESTART_CONTAINER,,} == "1" || ${RESTART_CONTAINER,,} == "true" || ${RESTART_CONTAINER,,} == "yes" ]]; then
				echo "[INFO] Restarting container." | ts '%Y-%m-%d %H:%M:%.S'
				exit 1
			fi
		fi
		if [[ ${HEALTH_CHECK_SILENT,,} == "0" || ${HEALTH_CHECK_SILENT,,} == "false" || ${HEALTH_CHECK_SILENT,,} == "no" ]]; then
			echo "[INFO] Network is up" | ts '%Y-%m-%d %H:%M:%.S'
		fi
		sleep ${INTERVAL} &
		# combine sleep background with wait so that the TERM trap above works
		wait $!
	done
else
	echo "[ERROR] Jackett failed to start!" | ts '%Y-%m-%d %H:%M:%.S'
fi
