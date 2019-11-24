#!/bin/bash
#
# Works on Solaris 11.3
#

VRRP_GROUP=0
read -p "What VRRP group to use? [12]: " VRRP_GROUP
if [[ $VRRP_GROUP -eq '0' ]] ; then
	VRRP_GROUP=12
fi

NODE_PRIO=90
read -p "Is this Node is the MASTER? <y/n> [N]: " prompt
if [[ $prompt =~ [yY](es)* ]] ; then
	NODE_PRIO=100
fi

prompt=""

while [ ! $prompt ] ; do
	read -p "Enter the Virtual IP to use: " prompt
		if [[ $prompt =~ [qQ](uit)* ]] ; then
			echo "Operation aborted"
			exit 0
		fi
	VIP=$prompt
done

prompt=""

while [ ! $prompt ] ; do
	read -p "Enter the subnet mask to use: (e.g. /24) " prompt
		if [[ $prompt =~ [qQ](uit)* ]] ; then
			echo "Operation aborted"
			exit 0
		fi
	SUBNET=$prompt
done

read -p "Last Chance.. proceed? <y/n> [N]: " prompt
if [[ ! $prompt =~ [yY](es)* ]] ; then
	echo "Operation aborted"
	exit 0
fi

# Install VRRP package if not installed
which vrrpadm 1>&- 2>&- || pkg install vrrp

# Set VRRP and assosiate IP
vrrpadm create-router -V $VRRP_GROUP -A inet -p $NODE_PRIO -I net0 -T l3 vrrp1
ipadm create-addr -T vrrp -n vrrp1 -a $VIP/$SUBNET net0/vaddr1

# Set system event notification
syseventadm add -v SUNW -p vrrpd -c EC_vrrp -s ESC_vrrp_state_change /usr/local/iprs/ha/ha_state_trigger.sh
syseventadm restart

echo ""
echo -e "\033[0;32m####################################################"
echo "VRRP Setup is Complete"
echo -e "####################################################\033[m"
echo ""
vrrpadm show-router -o NAME,STATE,PRV_STAT,PRIMARY_IP,PEER,VIRTUAL_IPS
echo ""
vrrpadm show-router
echo ""
