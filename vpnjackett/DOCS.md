# VPN Jackett addon for Home Assistant

Home Assistant Addon for Jackett tunneling via OpenVPN

## Installation

The installation of this add-on is pretty straightforward and not different in
comparison to installing any other Hass.io add-on.

1. Add https://github.com/rssindian/ha_addons to your Hass.io instance as a repository.
2. Install the "Jackett" add-on.
3. Start the "Jackett" add-on.
4. Check the logs of the "Jackett" to see if everything went well.
5. Open the web-ui
6. Additional Jackett logs can be found at homeassistant config/vpnjackett/Jackett/logs.txt


## Configuration

Jackett add-on configuration:

### Option: `DEBUG_ENABLED`

This enables additional debug logs. 
Note: The logging in this addon displays all info and warning by default

### Option: VPN_FILENAME

This is required to specify the <file_name> prefix of the .ovpn file. 
You need to copy the OpenVPN <file_name>.ovpn file from your VPN provider to homeassistant config folder under vpnjackett/openvpn

** Important Note: ovpn file should contain only one remote address/port **

### Option: `VPN_USERNAME`

Your OpenVPN username.

### Option: `VPN_PASSWORD`

Your OpenVPN password.

### Option: `LAN_NETWORK`

This specifies the local LAN IP/Subnet scheme. This is to allow local LAN access when the VPN is enabled. 
Most routers default to 192.168.1.0/24. If you don't know what yours is then leave it default.

### Option: `NAME_SERVERS`

Specify the DNS servers you would like this addons to use

### Option: `HEALTH_CHECK_HOST`

Specify the Web URL to hit and confirm if the connectivity works after VPN is enabled.

### Option: `HEALTH_CHECK_INTERVAL`

Specify how often the addon should try to hit the url specified above to confirm connectivity.


### Optional Configurations:

### Option: `WEBUI_PASSWORD`

You can specify a password to be used for the Jacket Web UI. This will always overwrite the password set within the Jackett UI. 
If you want to use the password set via Web UI, then leave this empty

### Option: `LEGACY_IPTABLES`

Enable this option if you want this addon to use Legacy iptables.

### Option: `DISABLE_VPN`

This is used to disable the OpenVPN and run Jackett directly.



## Changelog & Releases

This addon will be updated whenever there is an update upstream Jackett software. 
