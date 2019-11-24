#!/bin/bash
#
# Stop VRRP and IPRSD on this node
#

CURR_STATE=$(vrrpadm show-router -p -o STATE)
VRRP_NAME=$(vrrpadm show-router -p -o NAME)
COUNTER=0

read -p "Are you sure you want to perform a hosts switchover? <y/n> [N]: " prompt
if [[ $prompt =~ [yY](es)* ]] ; then
	if [[ $CURR_STATE == "MASTER" ]] ; then
		logger -p local1.info -t HA_SWITCHOVER "Switchover initiated: MASTER -> BACKUP"
		vrrpadm modify-router $VRRP_NAME -p 80
		while ! [[ $CURR_STATE == "BACKUP" || $COUNTER -eq 10 ]] ; do
			CURR_STATE=$(vrrpadm show-router -o NAME,STATE | grep -i vrrp | awk '{print ($2)}')
			echo -e "\033[0;33mIn Progress ..\033[m"
			sleep 1
			((COUNTER++))
		done
		if [ $COUNTER -eq 10 ] ; then
			vrrpadm modify-router $VRRP_NAME -p 110
			echo ""
			echo -e "\033[0;31mSwitchover failed\033[m"
			echo -e "\033[0;33mIt could be that a peer is not available\033[m"
			echo ""
			logger -p local1.info -t HA_SWITCHOVER "Switchover failed for MASTER -> BACKUP operation"
		else
			echo -e "\033[0;32m####################################################"
			echo "Switchover complete"
			echo -e "####################################################\033[m"
			logger -p local1.info -t HA_SWITCHOVER "Switchover Complete: MASTER -> BACKUP"
		fi
	elif [[ $CURR_STATE == "BACKUP" ]] ; then
		logger -p local1.info -t HA_SWITCHOVER "Switchover initiated: BACKUP -> MASTER"
		vrrpadm modify-router $VRRP_NAME -p 150
		while ! [ $CURR_STATE == "MASTER" ] ; do
			CURR_STATE=$(vrrpadm show-router -o NAME,STATE | grep -i vrrp | awk '{print ($2)}')
			echo -e "\033[0;33mIn Progress ..\033[m"
			sleep 1
		done
		echo -e "\033[0;32m####################################################"
		echo "Switchover complete"
		echo -e "####################################################\033[m"
		logger -p local1.info -t HA_SWITCHOVER "Switchover Complete: BACKUP -> MASTER"
	elif [[ $CURR_STATE == "INIT" ]] ; then
		logger -p local1.info -t HA_SWITCHOVER "Switchover initiated: Cannot perform in INIT state"
		echo ""
		echo -e "\033[0;33mVRRP in INIT state, first run 'ha-start'\033[m"
		echo ""
	fi
fi

exit 0
