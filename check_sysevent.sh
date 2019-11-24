#!/bin/bash
#
# Check Solaris syevent process is online
#

if ! [[ $(svcs -xv svc:/system/sysevent:default | grep State | awk '{print ($2)}') == "online" ]] ; then
	svcadm disable svc:/system/sysevent:default
	sleep 2
	svcadm enable svc:/system/sysevent:default
fi

exit 0
