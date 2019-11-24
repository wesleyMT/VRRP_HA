#!/bin/bash
#
# Works on Solaris 11.3
#

# Remove VRRP and assosiated IP
vrrpadm delete-router vrrp1
ipadm delete-addr net0/vaddr1

# Remove system event notification
syseventadm remove -v SUNW -p vrrpd -c EC_vrrp -s ESC_vrrp_state_change /usr/local/iprs/ha/ha_state_trigger.sh
syseventadm restart
