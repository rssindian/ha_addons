#!/usr/bin/with-contenv bashio

#Export all config variables to environment variables for use in bash
export DEBUG=$(bashio::config 'DEBUG_ENABLED' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
export CONFIG_FOLDER=$(bashio::config 'CONFIG_FOLDER' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
export VPN_FILENAME=$(bashio::config 'VPN_FILENAME' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
export VPN_USERNAME=$(bashio::config 'VPN_USERNAME' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
export VPN_PASSWORD=$(bashio::config 'VPN_PASSWORD' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
export LAN_NETWORK=$(bashio::config 'LAN_NETWORK' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
export NAME_SERVERS=$(bashio::config 'NAME_SERVERS' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
export HEALTH_CHECK_HOST=$(bashio::config 'HEALTH_CHECK_HOST' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
export HEALTH_CHECK_INTERVAL=$(bashio::config 'HEALTH_CHECK_INTERVAL' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

if $(bashio::config.exists 'WEBUI_PASSWORD'); then
    export WEBUI_PASSWORD=$(bashio::config 'WEBUI_PASSWORD' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
else
    export WEBUI_PASSWORD=""
fi

if $(bashio::config.true 'LEGACY_IPTABLES'); then
    export LEGACY_IPTABLES=true
else
    export LEGACY_IPTABLES=false
fi

if $(bashio::config.true 'DISABLE_VPN'); then
    export VPN_ENABLED=false
else
    export VPN_ENABLED=true
fi

#export ADDITIONAL_PORTS=$(bashio::config 'ADDITIONAL_PORTS' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

#call bash script
exec /bin/bash /etc/openvpn/start.sh 