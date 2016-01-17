#!/bin/bash
INTERFACE=ppp0
TUNNEL_NAME=hev6
ROUTER_INTERFACE=eth0

USERNAME=
PASSWD=
TUNNEL_ID=
SERVER_IPV4_ADDRESS=
CLIENT_IPV6_ADDRESS=
ROUTED_IPV6_ADDRESS=
#CLIENT_IPV4_ADDRESS=

MAKE_ROUTE=yes

HE_IP_DETECT=no
HE_PING_SERVER=66.220.2.74
HE_IP_SUBMIT_SERVER=64.62.200.2

SLEEP_TIME=10

PID_FILE="/run/hev6.pid"

get_ip(){
	echo `ip addr show dev $INTERFACE | grep "inet" | head -1 | awk '{print $2}'`
}

wait_for_ip(){
	IPADR=$(get_ip)
	while [ -z $IPADR ] ; do
		ifup $INTERFACE
		sleep $SLEEP_TIME
		IPADR=$(get_ip)
	done
	echo $IPADR
}

make_route(){
	if [ "$MAKE_ROUTE" == "yes" ] ; then
		ip route add $HE_PING_SERVER dev $INTERFACE
		ip route add $SERVER_IPV4_ADDRESS dev $INTERFACE
		if [ "$HE_IP_DETECT" == "yes" ] ; then
			ip route add $HE_IP_SUBMIT_SERVER dev $INTERFACE
		fi
	fi
}

wait_for_ip_change(){
	DEV=$INTERFACE

	ORI_IP=$(get_ip)

	if [ -z $ORI_IP ] ; then
		exit 1
	fi

	while [ true ] ; do
		sleep $SLEEP_TIME
		NEW_IP=$(get_ip)
		if [ "$NEW_IP" != "$ORI_IP" ] ; then
			exit 0
		fi
	done
}

if [ `whoami` != "root" ] ; then
	echo "Thsi script must be run as root, exiting."
	exit
fi


if [ "$1" == "listen" ] ; then
	$(wait_for_ip_change)
	exit 0
fi

if [ -f "$PID_FILE" ] ; then
	kill -TERM -$(cat $PID_FILE)
fi

if [ "$1" == "clear" ] ; then
	if [ -f "$PID_FILE" ] ; then
		rm "$PID_FILE"
	fi
	ip link set $TUNNEL_NAME down 
	ip tunnel del $TUNNEL_NAME
	if [ "$MAKE_ROUTE" == "yes" ] ; then
		ip route del $HE_PING_SERVER dev $INTERFACE
		ip route del $SERVER_IPV4_ADDRESS dev $INTERFACE
		if [ "$HE_IP_DETECT" == "yes" ] ; then
			ip route del $HE_IP_SUBMIT_SERVER dev $INTERFACE
		fi
	fi
	exit 0
fi

echo $$ > $PID_FILE

echo "$TUNNEL_NAME: $TUNNEL_NAME initiallizing."

IPADR=$(wait_for_ip)

$(make_route)

echo "Setting up $TUNNEL_NAME..."
ip tunnel add $TUNNEL_NAME mode sit remote $SERVER_IPV4_ADDRESS local $IPADR ttl 255
#echo "Adding $CLIENT_IPV6_ADDRESS to local tunnel."
ip addr add $CLIENT_IPV6_ADDRESS dev $TUNNEL_NAME
#echo "Make $TUNNEL_NAME as default route for ipv6."
ip route add ::/0 dev $TUNNEL_NAME
#echo "Set tunnel up."
ip link set $TUNNEL_NAME up
#echo "Set up routing."
ip route add $ROUTED_IPV6_ADDRESS dev $ROUTER_INTERFACE

#Updata client ip address on server and wait for ip change
while [ true ] ; do

	#Update server config
	#echo "Updating client ipv4 address on tunnel broker server."
	wget -O /dev/null "https://$USERNAME:$PASSWD@ipv4.tunnelbroker.net/nic/update?hostname=$TUNNEL_ID&myip=$IPADR" &>/dev/null

	$0 "listen" & #Wait for ip to change
	echo "$TUNNEL_NAME: $TUNNEL_NAME is up."
	wait

	#IP Changed
	echo "$TUNNEL_NAME: Client IPv4 address changed, waiting for $INTERFACE to assign a new ip."
	IPADR=$(wait_for_ip)

	$(make_route)
	echo "$TUNNEL_NAME: Client IPv4 address changed to ${IPADR}."
	ip tunnel change $TUNNEL_NAME mode sit remote $SERVER_IPV4_ADDRESS local $IPADR ttl 255

done
