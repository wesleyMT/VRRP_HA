#!/bin/bash
#
# #v1.2 - Connection timeout for curl
#

UTILSDIR="/usr/local/iprs/bin"
REQUEST_PIPE="/usr/local/iprs/pipes/veritas_to_monitor.pipe"
REQUEST_ACK_PIPE="/usr/local/iprs/pipes/veritas_to_monitor_ack.pipe"
RESPONSE_PIPE="/usr/local/iprs/pipes/monitor_to_veritas.pipe"
TMP_RESPONSE_FILE="/tmp/monitor.tmp"
TMP_CLEAR_REQUESTS="/tmp/clear_requests.tmp"
TMP_MONITOR_RESPONSE="/tmp/monitor_response.tmp"
STATUS_FILE="/usr/local/iprs/ha/STATUS"
FAILED_RES=0

ReasonToString ()
{
	case $1 in
	1) echo "cpu load" ;;
	2) echo "cpu fan" ;;
	4) echo "cpu temperature" ;;
	8) echo "NIC utilization" ;;
	16) echo "NIC link failure" ;;
	32) echo "virtual memory" ;;
	64) echo "disk space" ;;
	128) echo "diagnostic client" ;;
	*) echo $1
	esac
}

ErrorToString()
{
	case $1 in
	1) echo "failure" ;;
	2) echo "reboot" ;;
	3) echo "restart hardware" ;;
	4) echo "no DB connection" ;;
	5) echo "unrecoverable failure" ;;
	6) echo "maintenance" ;;
	7) echo "software reset" ;;
	*) echo $1
	esac
}

logger -p local1.info -t HA_IPRS_MONITOR "Start script"

## Verify if another instance of this script is running
#
logger -p local1.info -t HA_IPRS_MONITOR "Checking if another instance is running"
OtherPid=`ps -ef | grep ha_iprs_monitor.sh | grep -v grep | grep -v $$ | grep -v "sh -c" | awk '{print $2}'`
if [ -n "$OtherPid" ] ; then
	kill -9 $OtherPid
fi

## Main
#
while : ; do

	## Check current VRRP state and translate to IPRS states
	#
	logger -p local1.info -t HA_IPRS_MONITOR "Checking current VRRP state"
	CURR_STATE=$(vrrpadm show-router -o NAME,STATE| grep -i vrrp | awk '{print ($2)}')
	if [[ $CURR_STATE == "MASTER" ]] ; then
		STATE=41
	elif [[ $CURR_STATE == "BACKUP" ]] ; then
		STATE=40
	else
		STATE=0
	fi

	## Request monitor for IPRSD health status
	#
	if [[ $(pgrep -x iprs_monitor) ]] ; then
		( curl -s --connect-timeout 5 -m 10 'http://monitoring:5050/'$HOSTNAME'-monitor-state?Value=0' > /dev/null ) &
		logger -p local1.info -t HA_IPRS_MONITOR "Requesting monitor for IPRSD health status"
		TechoResult=`su - iprs -c "bash --login -c \"$UTILSDIR/techo $REQUEST_PIPE $REQUEST_ACK_PIPE \"$0,$$,1,1,$STATE,\"\""`

		# If monitor returns a FAIL status, terminate it and set failover condition
		if [[ $TechoResult == *"FAIL"* ]] ; then
			logger -p local1.info -t HA_IPRS_MONITOR "Received 'FAIL' Response from techo, terminating iprs_monitor .."
			pkill -9 -x iprs_monitor
			
			# Count 3 times that iprs_monitor FAILed then set failover condition
			((FAILED_RES++))
			logger -p local1.info -t HA_IPRS_MONITOR "FAILed counter raised to "$FAILED_RES

			if [ $FAILED_RES -eq 3 ] ; then
				logger -p local1.info -t HA_IPRS_MONITOR "Communication with iprs_monitor failed 3 times, setting fail-over condition .."
				echo "1" > $STATUS_FILE
				# Reset FAILed counter
				FAILED_RES=0
			fi

		# If monitor returns any other response (OK status)
		else
			su - iprs -c "bash --login -c \"$UTILSDIR/tcat $RESPONSE_PIPE 1 10000"\"  > $TMP_RESPONSE_FILE
			
			# Monitor clear response
			if [ -n "`grep clear_request $TMP_RESPONSE_FILE`" ] ; then
				`grep clear_request $TMP_RESPONSE_FILE | awk '{print $2}' > $TMP_CLEAR_REQUESTS`
				read ClearNum < $TMP_CLEAR_REQUESTS
				TechoResult=`su - iprs -c "bash --login -c \"$UTILSDIR/techo $REQUEST_PIPE $REQUEST_ACK_PIPE \"2,$ClearNum,\"\""`
				logger -p local1.info -t HA_IPRS_MONITOR "Clear sequence successfully completed"
				echo "0" > $STATUS_FILE
				
				# Reset FAILed counter
				if [ $FAILED_RES -ne 0 ] ; then
					FAILED_RES=0
					logger -p local1.info -t HA_IPRS_MONITOR "FAILed counter reset to 0"
				fi

			# Normal monitor response
			elif [ -n "`grep monitor_response $TMP_RESPONSE_FILE`" ] ; then
				logger -p local1.info -t HA_IPRS_MONITOR "IPRS monitor returned OK status"
				`grep monitor_response $TMP_RESPONSE_FILE > $TMP_MONITOR_RESPONSE`
				read RequestType RequestId Status Reason < $TMP_MONITOR_RESPONSE
				TechoResult=`su - iprs -c "bash --login -c \"$UTILSDIR/techo $REQUEST_PIPE $REQUEST_ACK_PIPE \"3,$RequestId,\"\""`
				echo $Status > $STATUS_FILE
				if [ "$Status" != "0" ] ; then
					logger -p local1.info -t HA_IPRS_MONITOR "IPRS Monitor Status: `ErrorToString $Status`; Reason: `ReasonToString $Reason`"
				fi
				
				# Reset FAILed counter
				if [ $FAILED_RES -ne 0 ] ; then
					FAILED_RES=0
					logger -p local1.info -t HA_IPRS_MONITOR "FAILed counter reset to 0"
				fi

			# NO response from monitor, terminate it and set failover condition
			elif [ -z "`cat $TMP_RESPONSE_FILE`" ] ; then
				pkill -9 -x iprs_monitor
				logger -p local1.info -t HA_IPRS_MONITOR "Monitor did not respond, terminating it .."

				# Count 3 times that iprs_monitor did not respond then set failover condition
				((FAILED_RES++))
				logger -p local1.info -t HA_IPRS_MONITOR "FAILed counter raised to "$FAILED_RES

				if [ $FAILED_RES -eq 3 ] ; then
					logger -p local1.info -t HA_IPRS_MONITOR "Communication with iprs_monitor failed 3 times, setting fail-over condition .."
					echo "1" > $STATUS_FILE
					# Reset FAILed counter
					FAILED_RES=0
				fi
			fi

			# Remove temporary files
			rm -f $TMP_RESPONSE_FILE
			rm -f $TMP_CLEAR_REQUESTS
			rm -f $TMP_MONITOR_RESPONSE
		fi
	else
		logger -p local1.info -t HA_IPRS_MONITOR "Monitor process is not running"
		( curl -s --connect-timeout 5 -m 10 'http://monitoring:5050/'$HOSTNAME'-monitor-state?Value=1' > /dev/null ) &
	fi
	
	sleep 10

done

logger -p local1.info -t HA_IPRS_MONITOR "End script"

exit 0