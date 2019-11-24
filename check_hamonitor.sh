#!/bin/bash
#
# Check HA IPRS monitor script is running
#

HAMON_SCRIPT=`ps -ef | grep ha_iprs_monitor.sh | grep -v grep | grep -v "sh -c" | awk '{print $2}'`

if ! [[ $HAMON_SCRIPT ]] ; then
	/usr/local/iprs/ha/ha_iprs_monitor.sh &
fi

exit 0

