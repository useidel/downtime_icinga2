#!/bin/sh 

PATH=/bin:/usr/bin:/usr/local/bin:
export PATH

MYNAME=`basename $0`

MYSTARTTIME=`date +%s`
# default maintenance window duration is 2 hours
MYENDTIME=`date -d '+2 hour' +%s`

# your icinga instance credentials can be hard coded here
MYICINGAADMIN=icinga2adminuser
MYICINGAPWD=icinga2adminpassword

MYICINGAHOST=youricinga2host.example.com
MYSEREVER=""

# default is to not cover children of the object - the variable MYCHILDHANDLE could be derived from that 
# will cover this in future releases
MYCOVERCHILDS=OFF
MYCHILDHANDLE="DowntimeNoChildren" # alternative is: DowntimeTriggeredChildren 
MYALLSERVICE="true" # if MYCHILDHANDLE=DowntimeTriggeredChildren set this to false and more actions are needed

# default maintenance message and by whom
MYCOMMENT="Known problem or simple restart"
MYAUTHOR="Icinga2-Boss"


MYDOWNTIMESET=OFF # default ist removing downtimes (OFF) ... adding downtimes is ON

# ln -s downtime.icinga2.sh downtime.off.sh
# ln -s downtime.icinga2.sh downtime.on.sh

echo $MYNAME|grep on > /dev/null # needs to be adapted to the actual name of the (soft) links (see previous comments)
if [ $? -eq 0 ]; then
	MYDOWNTIMESET=ON
fi

print_usage() {
echo 
echo " This will set/remove a server including all child services in/from Icinga2 maintenance."
echo 
echo 
if [ x${MYDOWNTIMESET}y == xONy ]; then
	echo " Usage: $MYNAME -s <server> <-h icingahost> <-u adminname> <-p password> <-d downtimelength> <-c> " 
	echo
	echo "   -s: the server you want to add a downtime"
else
	echo " Usage: $MYNAME -s <server> <-h icingahost> <-u adminname> <-p password>"
	echo
	echo "   -s: the server you want to remove a downtime"
fi
echo "   -h: where the icinga2 instance is running"
echo "   -u: the name of the icinga2 admin user"
echo "   -p: the password of the icinga2 admin user"
if [ x${MYDOWNTIMESET}y == xONy ]; then
	echo "   -d: in seconds starting from now (default is 7200)" 
	echo "   -c: cover child objects of the server" 
fi
echo 
}

# routine to check if a particular command is available
check_command() {
which $1 2>&1 > /dev/null
MYRC=$?
if [ $MYRC -ne 0 ]; then
	echo
	echo " command $1 is not available or not in a standard path"
	echo
	exit 1
fi
}

# can reach the icinga host (at least per ICMP)
ping_icingahost() {
echo
echo " ... checking for $1 ..."
echo
ping -c 3 $1 > /dev/null 2>&1
MYRC=$?
if [ $MYRC -ne 0 ]; then
	echo
	echo " Host $1 not reachable"
	echo
	exit 1
fi
}

# test routine if the provide figure is a positive integer
check_positivenumber(){
if ! [ "$1" -gt 0 ] 2> /dev/null
then
	echo
	echo "$1 is not an positive integer"
	echo
	exit 1
fi
}

# test routine to cover the usage of DNS aliases for a such an object instead of the real hostname 
check_dns(){
echo
echo "Server $1 unknown - will try lokal DNS alias"
echo
OLDIFS=$IFS
IFS=$'\n'
MYSERVERARRAY=( $(host $1) )
IFS=$OLDIFS
if [ "X${MYSERVERARRAY[1]}Y" = "XY" ]; then
        echo
        echo " Server $OPTARG locally unknown or hostname resolution not available"
        echo
        exit 1
else
        MYSERVER=`echo ${MYSERVERARRAY[1]}|cut -f1 -d"."`
fi
}

# test routine if that server is a valid object on the icinga instance
check_hostobject(){
		(eval curl -k -s -u $MYICINGAADMIN:$MYICINGAPWD -H \'Accept: application/json\' -X GET \'https://$MYICINGAHOST:5665/v1/objects/hosts\' -d \'{\"filter\": \"host.name==\\\"$1\\\"\", \"pretty\": true }\') |grep '__name' 2>&1 > /dev/null
return $?
}

if [ "$#" -lt 2 ]; then
        print_usage
        exit 1
fi


# we are checking if ping and curl are available
check_command ping
check_command curl


while getopts "s:h:d:u:p:c" OPT
do              
        case "$OPT" in
        s)
                MYSERVER=$OPTARG
		check_hostobject $MYSERVER 
		MYRC=$?
		if [ $MYRC -ne 0 ]; then
			check_dns $MYSERVER
		fi
                ;;
        h)
                MYICINGAHOST=$OPTARG
                ;;
        d)
		MYDURATION=$OPTARG
		check_command bc
		check_positivenumber $MYDURATION
		MYENDTIME=`echo $MYSTARTTIME + $MYDURATION|bc -l`
		MYRC=$?
		if [ $MYRC -ne 0 ]; then
			echo
			echo " Something went wrong when calculating the downtime end"
			echo
			exit 1
		fi
                ;;
	u)
		MYICINGAADMIN=$OPTARG
		;;
	p)
		MYICINGAPWD=$OPTARG
		;;
	c)
		MYCOVERCHILDS=ON
		;;
        *)
                print_usage
                exit $STATE_UNKNOWN
        esac
done

ping_icingahost $MYICINGAHOST

echo
echo " Trying to reach Icinga2 instance on $MYICINGAHOST ..."
echo

if [ x${MYDOWNTIMESET}y == xONy ]; then
	if [ x${MYCOVERCHILDS}y == xOFFy ]; then
		# we set the downtime on the server
		(eval curl -k -s -u $MYICINGAADMIN:$MYICINGAPWD -H \'Accept: application/json\' -X POST \'https://$MYICINGAHOST:5665/v1/actions/schedule-downtime\' -d \'{\"type\": \"Host\", \"filter\": \"host.name==\\\"$MYSERVER\\\"\", \"start_time\": \"$MYSTARTTIME\", \"end_time\": \"$MYENDTIME\", \"author\": \"$MYICINGAADMIN\", \"comment\": \"$MYCOMMENT\", \"all_services\": $MYALLSERVICE, \"child_options\": \"$MYCHILDHANDLE\", \"pretty\": true }\')
	else
		MYALLSERVICE=false
		MYCHILDHANDLE=DowntimeTriggeredChildren
		# we set the downtime on the server w/o it's services which would lead to duplicates
		(eval curl -k -s -u $MYICINGAADMIN:$MYICINGAPWD -H \'Accept: application/json\' -X POST \'https://$MYICINGAHOST:5665/v1/actions/schedule-downtime\' -d \'{\"type\": \"Host\", \"filter\": \"host.name==\\\"$MYSERVER\\\"\", \"start_time\": \"$MYSTARTTIME\", \"end_time\": \"$MYENDTIME\", \"author\": \"$MYICINGAADMIN\", \"comment\": \"$MYCOMMENT\", \"all_services\": $MYALLSERVICE, \"child_options\": \"$MYCHILDHANDLE\", \"pretty\": true }\')
		# and now we set tthe downtime of the services of the server
		(eval curl -k -s -u $MYICINGAADMIN:$MYICINGAPWD -H \'Accept: application/json\' -X POST \'https://$MYICINGAHOST:5665/v1/actions/schedule-downtime\' -d \'{\"type\": \"Service\", \"filter\": \"host.name==\\\"$MYSERVER\\\"\", \"start_time\": \"$MYSTARTTIME\", \"end_time\": \"$MYENDTIME\", \"author\": \"$MYICINGAADMIN\", \"comment\": \"$MYCOMMENT\", \"pretty\": true }\')

	fi
else
	# we remove the server downtime (covers keepalive)
	(eval curl -k -s -u $MYICINGAADMIN:$MYICINGAPWD -H \'Accept: application/json\' -X POST \'https://$MYICINGAHOST:5665/v1/actions/remove-downtime\' -d \'{\"type\": \"Host\", \"filter\": \"host.name==\\\"$MYSERVER\\\"\", \"pretty\": true }\')
	# we remove the servers services downtime if they are not removed automatically
	(eval curl -k -s -u $MYICINGAADMIN:$MYICINGAPWD -H \'Accept: application/json\' -X POST \'https://$MYICINGAHOST:5665/v1/actions/remove-downtime\' -d \'{\"type\": \"Service\", \"filter\": \"host.name==\\\"$MYSERVER\\\"\", \"pretty\": true }\')
fi

MYRC=$?

if [ $MYRC -ne 0 ];
then
	echo
	echo " Something went wrong. :-("
	echo " Icinga downtime is probably not set/removed!"
	echo " Please check!"
	echo
fi

