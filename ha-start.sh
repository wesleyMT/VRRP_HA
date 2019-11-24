#!/bin/bash
#
# Start VRRP on this node
#

VRRP_NAME=$(vrrpadm show-router -o NAME | grep -i vrrp | awk '{print ($1)}')

vrrpadm enable-router $VRRP_NAME
logger -p local1.info -t HA_START Complete
echo ""
echo -e "\033[0;32m####################################################"
echo "HA service has been initiated .."
echo -e "####################################################\033[m"
echo ""
/usr/local/iprs/ha/ha-show.sh

exit 0
