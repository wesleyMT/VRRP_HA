#!/bin/bash
#
# Check HA Trigger Script is running
#

CURR_STATE=$(vrrpadm show-router -o NAME,STATE | grep -i vrrp | awk '{print ($2)}')
TRIGGER_SCRIPT=`ps -ef | grep ha_state_trigger.sh | grep -v grep | grep -v "sh -c" | awk '{print $2}'`

if [[ $CURR_STATE == "MASTER"  && ! $TRIGGER_SCRIPT ]] ; then
	/usr/local/iprs/ha/ha_state_trigger.sh &
fi

exit 0
