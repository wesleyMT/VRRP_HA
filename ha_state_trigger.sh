#!/bin/bash
#
# VRRP Status Change Script for Solaris
#
# v1.2 - Added state change time record
#

## Part 1: Variable definition
##

VRRP_NAME=$(vrrpadm show-router -p -o NAME)
CURR_STATE=$(vrrpadm show-router -p -o STATE)
PREV_STATE=$(vrrpadm show-router -p -o PRV_STAT)
IPRSlog="/var/iprs/log/iprsd/applog_current.log"
UTILSDIR="/usr/local/iprs/bin"
IPRS_REQ_STAT_ACTIVE=0
IPRS_REQ_PIPE="/usr/local/iprs/pipes/veritas_to_iprs.pipe"
IPRS_REQ_ACK_PIPE="/usr/local/iprs/pipes/veritas_to_iprs_ack.pipe"
IPRS_RESPOSE_PIPE="/usr/local/iprs/pipes/iprs_to_veritas.pipe"
IPRS_REQ_SERVER_STATE=2
TMP_IPRS_RESPONSE_FILE="/tmp/iprs.tmp"
STATUS_FILE="/usr/local/iprs/ha/STATUS"
UPTIME=`/usr/bin/uptime | /usr/bin/awk '{print ($3)}'`
UPTIME_UNIT=`/usr/bin/uptime | /usr/bin/awk '{print ($4)}'`
CHGREC="/tmp/vrrp-change.time"

## Part 2: Functions
##
iprsStart ()
{
	logger -p local1.info -t HA_TRIGGER_SCRIPT "Starting IPRS process in standby mode"
	su - iprs -c "bin/iprsd.sh standby &"
	
	# Wait until IPRS becomes standby
	while true ; do
		TechoRequest="\\\"$IPRS_REQ_SERVER_STATE $$\\\""
		TechoResult=$(su - iprs -c "bash --login -c \"$UTILSDIR/techo $IPRS_REQ_PIPE $IPRS_REQ_ACK_PIPE $TechoRequest 1000 5\"")
		if [[ $TechoResult = *"OK"* ]] ; then
			su - iprs -c "bash --login -c \"$UTILSDIR/tcat $IPRS_RESPOSE_PIPE 1 10000 > $TMP_IPRS_RESPONSE_FILE\""
			read DbState ServerState Id < $TMP_IPRS_RESPONSE_FILE
			if [[ $ServerState -eq 40 ]] ; then break ; fi
		fi
		logger -p local1.info -t HA_TRIGGER_SCRIPT "Waiting for IPRS process init to standby"
		sleep 1
	done

	logger -p local1.info -t HA_TRIGGER_SCRIPT "IPRS is now in standby mode"
	rm -f $TMP_IPRS_RESPONSE_FILE
}

iprsStop ()
{
	logger -p local1.info -t HA_TRIGGER_SCRIPT "Killing IPRS process"
	pkill -x iprsd
	sleep 2
}

iprsActive ()
{
	logger -p local1.info -t HA_TRIGGER_SCRIPT "Switching IPRS process to active state"
	TechoRequest="\\\"$IPRS_REQ_STAT_ACTIVE $$\\\""
	su - iprs -c "bash --login -c \"$UTILSDIR/techo $IPRS_REQ_PIPE $IPRS_REQ_ACK_PIPE $TechoRequest\""
}

gpsStart ()
{
	logger -p local1.info -t HA_TRIGGER_SCRIPT "Starting GPS process"
	su - iprs -c "bin/gpsd.sh &"
}

gpsStop ()
{
	logger -p local1.info -t HA_TRIGGER_SCRIPT "Killing GPS process"
	pkill -x gpsd
}

sosStart ()
{
	logger -p local1.info -t HA_TRIGGER_SCRIPT "Starting SOS process"
	su - iprs -c "bin/sosd.sh &"
}

sosStop ()
{
	logger -p local1.info -t HA_TRIGGER_SCRIPT "Killing SOS process"
	pkill -x sosd
}

## Record time of change
echo $(date '+%Y-%b-%d %H:%M:%S %s') > $CHGREC


## Part 3: VRRP MASTER State commands
##
if [[ $CURR_STATE == "MASTER" ]] ; then

	# Stop script if system just booted (<3 minutes), cron will retry later
	if [[ $UPTIME -eq 0 || ($UPTIME_UNIT == *"min"* && $UPTIME -lt 2) ]] ; then  # remove -eq 0 statement ?
		logger -p local1.info -t HA_TRIGGER_SCRIPT "Uptime threshold startup delay"
		exit 0
	fi

	logger -p local1.info -t HA_TRIGGER_SCRIPT "Executing VRRP MASTER state commands"
	
	# Check if another instance of this script is running
	OtherPid=`ps -ef | grep ha_state_trigger.sh | grep -v grep | grep -v $$ | grep -v "sh -c" | awk '{print $2}'`
	if [ -n "$OtherPid" ] ; then
		kill -9 $OtherPid
	fi

	vrrpadm modify-router $VRRP_NAME -p 110

	# if iprsd is not running start it in standby mode
	if ! [[ $(pgrep -x iprsd) ]] ; then
		iprsStart
	fi

	# Switch IPRS process to active state
	iprsActive
	gpsStart
	sosStart
	
	while : ; do

		# Verify Monitor state
		if [ $(cat $STATUS_FILE) == "1" ] ; then
			logger -p local1.info -t HA_TRIGGER_SCRIPT "IPRS monitor return an error state"
			break
		fi

		# Verify IPRS process is running
		if ! [[ $(pgrep -x iprsd) ]] ; then
			logger -p local1.info -t HA_TRIGGER_SCRIPT "IPRS process has stopped"
			break
		fi

		# Verify VRRP still in MASTER state
		if ! [[ $(vrrpadm show-router -p -o STATE) == "MASTER" ]] ; then
			logger -p local1.info -t HA_TRIGGER_SCRIPT "VRRP state changed"
			break
		fi

		sleep 2
	done

	# Evaluate current state then terminate IPRS process if still running and if not in VRRP BACKUP state
	if [[ ! $(vrrpadm show-router -p -o STATE) == "BACKUP" && $(pgrep -x iprsd) ]] ; then
		iprsStop
	fi

	# Reduce VRRP priority to force failover
	logger -p local1.info -t HA_TRIGGER_SCRIPT "Lowering VRRP priority of MASTER to 80 and ending MASTER script"
	vrrpadm modify-router $VRRP_NAME -p 80

	gpsStop
	sosStop

	exit 0
fi


## Part 4: VRRP BACKUP State commands
##
if [[ $CURR_STATE == "BACKUP" ]] ; then

	sleep 6

	logger -p local1.info -t HA_TRIGGER_SCRIPT "Executing VRRP BACKUP state commands"

	# If my previous status was MASTER the IPRS process wasnt shutdown
	# terminate IPRS process forcefully
	if [[ $PREV_STATE == "MASTER" && $(pgrep -x iprsd) ]] ; then
		logger -p local1.info -t HA_TRIGGER_SCRIPT "Forcefully terminating IPRS process"
		pkill -9 -x iprsd
	fi

	# if iprsd is not running start it in standby mode
	if ! [[ $(pgrep -x iprsd) ]] ; then iprsStart ; fi
	
	# If monitor state is operational
	if [ $(cat $STATUS_FILE) == "0" ] ; then
		logger -p local1.info -t HA_TRIGGER_SCRIPT "IPRS appears to be healthy"
		vrrpadm modify-router $VRRP_NAME -p 90
		exit 0

	# else If monitor state is not operational - anything other than "0"
	elif ! [ $(cat $STATUS_FILE) == "0" ] ; then

		logger -p local1.info -t HA_TRIGGER_SCRIPT "IPRS does not appear to be healthy, waiting for recovery"
		vrrpadm disable-router $VRRP_NAME

		# wait for recovery ("0")
		while : ; do
	
			# Verify Monitor state
			if [ $(cat $STATUS_FILE) == "0" ] ; then
				logger -p local1.info -t HA_TRIGGER_SCRIPT "IPRS monitor is in error state"
				break
			fi

			sleep 2
		done

		logger -p local1.info -t HA_TRIGGER_SCRIPT "IPRS health apears to have recovered, restoring VRRP and exiting"
		vrrpadm modify-router $VRRP_NAME -p 90
		vrrpadm enable-router $VRRP_NAME
	fi
fi

exit 0
