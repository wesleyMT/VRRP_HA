#!/bin/bash
#
# Show VRRP information on this node
#
# #v1.2 - Changed last VRRP state change date calculation
#
CHGREC="/tmp/vrrp-change.time"

echo ""
vrrpadm show-router -o NAME,STATE,PRV_STAT,PRIMARY_IP,PEER,VIRTUAL_IPS
echo ""
vrrpadm show-router
echo ""

if [ -f $CHGREC ] ; then
	read CHGDATE CHGTIME CHGEPOCH < $CHGREC
	CUREPOCH=$(date '+%s')
	LAST_CHG=$(($CUREPOCH - $CHGEPOCH))
	
	mins=$(( ($LAST_CHG / 60) % 60 ))
	hours=$((( ($LAST_CHG / 60) / 60) % 24 ))
	days=$((( ($LAST_CHG / 60) / 60) / 24 ))
	
	echo ""
	echo -e "Last HA state change: \033[0;32m"$CHGDATE" "$CHGTIME" - "$days"d "$hours"h "$mins"m ago ...\033[m"
	echo ""
	echo ""
fi

exit 0
