#!/bin/bash

#**************************************************************************************
#
# Default Gateway Failover Script
# modified: 12.01.08 Micha Richter (micha.richter@projekt-linux.de)
# modified: 11.04.17 Matteo Temporini - Revision
#
# This script has to be run as root, because of modifiing the routing tables.
# It should be run in backround (e.g. scriptname &)
#
# needed packages:
# - iproute2
#
# functions:
# - checking if internet are reachable via default gateway
# - switching to backup gateway if needed
# - switching back to default gateway if all is ok again
# - writes each gateway switch to logfile
# - it does NOT check if internet is working via the backup gateway
#**************************************************************************************

#*********************************************************************
# Configuration part
#*********************************************************************
DEF_GATEWAY="192.168.2.254" # Default Gateway (e.g. Loadbalancer)
BCK_GATEWAY="192.168.2.150" # Backup Gateway
RMT_HOST="www.google.it"
RMT_IP_1="$(host $RMT_HOST | awk '/has address/ { print $4 }')" # first remote ip
RMT_IP_2="8.8.8.8" # Second remote ip
SLEEP_TIME="30" # time till next check in seconds
LOG_FILE="/var/log/syslog" # logfile, default is syslog
#*********************************************************************
# PLEASE CHANGE NOTHING BELOW THAT LINE !
#*********************************************************************

#LOG_TIME=`date +%b' '%d' '%T`
#
# functions
#
check_via_def_gw() {
#****************************************************************************
# function:
# - checks which gateway is used
# - checking via default gw or static routes if remote ip is reachable
#
# results
# - PING_1: result of ping to RMT_IP_1
# - PING_2: result of ping to RMT_IP_2
#****************************************************************************
# check def gw
CURRENT_GW=`ip route show | grep default | awk '{ print $3 }'`
if [ $CURRENT_GW == $DEF_GATEWAY ]
then
 ###echo "Running on def. gateway $CURRENT_GW"
 ping -c 2 $RMT_IP_1 > /dev/null
 PING_1=$?
 ping -c 2 $RMT_IP_2 > /dev/null
 PING_2=$?
else
 ###echo "Not running on default gateway, currently we're running via $CURRENT_GW"
 # add static routes to remote ip's
 ip route add $RMT_IP_1 via $DEF_GATEWAY
 ip route add $RMT_IP_2 via $DEF_GATEWAY
 ping -c 2 $RMT_IP_1 > /dev/null
 PING_1=$?
 ping -c 2 $RMT_IP_2 > /dev/null
 PING_2=$?
 # del static route to remote ip's
 ip route del $RMT_IP_1
 ip route del $RMT_IP_2
fi
}


change_gw() {
LOG_TIME=`date +%b' '%d' '%T`
#****************************************************************************
# function:
# - checks which gateway is used
# - using results of check_via_def_gw
# - switching to backup gateway if default way isn't working
# - switching back to default gateway if line is ok again
#
# used variables:
# - PING_1: result of ping to RMT_IP_1
# - PING_2: result of ping to RMT_IP_2
#****************************************************************************
# change gw if remote ip's not reachable
if [ $PING_1 == "1" ] && [ $PING_2 == "1" ]
then
 # both ip's not reachable
 # check which gw is set and change
 if [ $CURRENT_GW == $DEF_GATEWAY ]
 then
 # current gateway is default gateway
 # switch to backup gateway
 ip route del default
 ip route add default via $BCK_GATEWAY
 # flushing routing cache
 ip route flush cache
 echo "$LOG_TIME: $0 - switched Gateway to Backup with IP $BCK_GATEWAY" | tee -a $LOG_FILE
 echo "$LOG_TIME: $0 - switched Gateway to Backup with IP $BCK_GATEWAY" | mail -s "Switched Gateway to Backup" mail@domain.tld
 else
 # current gateway is backup gateway or manual setted gateway
 # no switch necessary
 echo "$LOG_TIME: No switch, we're running on backup line"
 fi
elif [ $CURRENT_GW != $DEF_GATEWAY ]
 # one ore both ip's are reachable
 # checks if right gw is set
 # wrong or backup default gateway is set
 then
 # switching to default
 ip route del default
 ip route add default via $DEF_GATEWAY
 ip route flush cache
 echo "$LOG_TIME: $0 - Gateway switched to default with IP $DEF_GATEWAY" | tee -a $LOG_FILE
 echo "$LOG_TIME: $0 - Gateway switched to default with IP $DEF_GATEWAY" | mail -s "Switched Gateway to default" mail@domain.tld
 else
 # nothing to do, gateways ok
 echo "$LOG_TIME: default Gateway is ok, remote IP's are reachable"
fi
}

main_part() {
# check user at first
if [ `whoami` != "root" ]
then
 echo "Gateway Failover script must be run as root!"
else
 check_via_def_gw
 change_gw
 sleep $SLEEP_TIME
 main_part
fi
}

# run the whole stuff
# checking if gateways are reachable
ping -c 2 $DEF_GATEWAY > /dev/null
PING_DEF_GW=$?
ping -c 2 $BCK_GATEWAY > /dev/null
PING_BCK_GW=$?
if [ $PING_DEF_GW == "0" ] && [ $PING_BCK_GW == "0" ]
then
 # if gateways reachable start the loop
 main_part
else
 # if gateways not reachable do not start the script
 echo "Warning, one or both defined gateways are not ok!"
 if [ $PING_DEF_GW != "0" ]
 then
 echo "Default Gateway ($DEF_GATEWAY) is NOT reachable!"
 fi
 if [ $PING_BCK_GW != "0" ]
 then
 echo "Backup Gateway ($BCK_GATEWAY) is NOT reachable!"
 fi
 echo "Please check the gateway configuration."
fi

exit 0
