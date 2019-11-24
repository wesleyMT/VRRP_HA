#!/bin/bash
#
# Stop VRRP and IPRSD on this node
#

VRRP_NAME=$(vrrpadm show-router -o NAME | grep -i vrrp | awk '{print ($1)}')

read -p "Are you sure you want to stop this host and remove it from the cluster? <y/n> [N]: " prompt
if [[ $prompt =~ [yY](es)* ]] ; then
	pkill -9 iprsd
	vrrpadm disable-router $VRRP_NAME
	vrrpadm modify-router $VRRP_NAME -p 90
	logger -p local1.info -t HA_STOP Complete
	echo ""
	echo -e "\033[0;33m####################################################"
	echo "HA service and 'iprsd' are stopped .."
	echo -e "####################################################\033[m"
	echo ""
	/usr/local/iprs/ha/ha-show.sh
fi

exit 0
