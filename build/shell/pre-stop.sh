#!/bin/bash
#install kind: M => Do nothing
#install kind: S && ON_BOOT: yes or y or exeptagent => Server gracefully stop
#install kind: A && ON_BOOT: yes or y =>  Agent gracefully stop
#install kind: F && ON_BOOT: yes or y => Server & Agent gracefully stop 
#		 && ON_BOOT: exceptagent => Server gracefully stop

if [ "$INSTALL_KIND" == "S" ] || [ "$INSTALL_KIND" == "F" ]
then
	if [ "$ON_BOOT" == "yes" ] || [ "$ON_BOOT" == "y" ] || [ "$ON_BOOT" == "exceptagent" ]
	then
		STOP_SERVER="Y"
	fi
fi
if [ "$INSTALL_KIND" == "F" ] || [ "$INSTALL_KIND" == "A" ]
then
	if [ "$ON_BOOT" == "yes" ] || [ "$ON_BOOT" == "y" ]
	then
		STOP_AGENT="Y"
	fi
fi

if [ "$STOP_AGENT" == "Y" ]
then
  while true :
  do
    curl -sS http://$JJOBS_SERVER_IP:$SERVER_WEB_PORT/jjob-server/test.jsp
    if [ $? -eq 0 ]; then
      PROTOCOL="http"
      break
    fi

    curl -sS https://$JJOBS_SERVER_IP:$SERVER_WEB_PORT/jjob-server/test.jsp
    if [ $? -eq 0 ]; then
      PROTOCOL="https"
      break
    fi

    sleep 5;
  done
else
  PROTOCOL="http"
fi

#check server status
pid="$(ps -ef | grep $JJOBS_BASE/server | grep -v "grep" | awk '{print $2}')"
if [ -z "$pid" ]
then
	SERVER_STATUS="STOPPED"
else
	SERVER_STATUS="RUNNING"
fi
sleep 1;

#check agent status
pid="$(ps -ef | grep cname=jjobs | grep -v "grep" | awk '{print $2}')"
if [ -z "$pid" ]
then
	AGENT_STATUS="STOPPED"
else
	AGENT_STATUS="RUNNING"
fi
sleep 1;


if [ "$STOP_SERVER" == "Y" ] && [ "$SERVER_STATUS" == "RUNNING" ]
then
	#1. Server gracefully stop
	#1-1. Get Server ID
	str=$HOSTNAME
	id=${str:(-1):1}
	INT=$((id))
	realServerId=$(($INT + 1))

	#1-2. Server hold
	curl -X PUT \
	-H "Content-Type: application/json" \
	-H "private-token: $API_PRIVATE_TOKEN" \
	-d '{"groupId":1,"serverId":'$realServerId',"holdWorkerYn":"Y"}' \
	http://localhost:$SERVER_WEB_PORT/jjob-server/api/v1/serversetting/server/hold
fi

if [ "$STOP_AGENT" == "Y" ] && [ "$AGENT_STATUS" == "RUNNING" ]
then
	#2. Agent gracefully stop
	#2-1. Agent hold and stop
	curl -X POST \
	-H "Content-Type: application/json" \
	-H "private-token: $API_PRIVATE_TOKEN" \
	-d "{\"groupId\":1,\"agentGroupId\":null,\"agentName\":\"$HOSTNAME\"}" \
	$PROTOCOL://$JJOBS_SERVER_IP:$SERVER_WEB_PORT/jjob-server/api/v1/serversetting/agent/holdAndStopAgent
fi

if [ "$STOP_SERVER" == "Y" ] && [ "$SERVER_STATUS" == "RUNNING" ]
then
	#1-3. waiting request list finish
	while true :
	do
		#if [[ "${workingRequestInfo[@]}" != "{\"list\":[]}" ]]; then
			 #workingRequestInfo=$(curl -X GET \
		 		 #-H "Content-Type: application/json" \
		 		 #-H "private-token: $API_PRIVATE_TOKEN" \
		 		 #"$PROTOCOL://$JJOBS_SERVER_IP:$SERVER_WEB_PORT/jjob-server/api/v1/statusmonitor/selectWorkingRequestList?groupId=1&serverId=$realServerId")
		#else
			#1-4. stop tcp#1 port
			#hold -> kill all port -> processing wait -> stop server
	                #iptables -A INPUT -p tcp --dport $SERVER_TCP_PORT -j DROP
        	        #iptables -D INPUT -p tcp --dport $SERVER_TCP_PORT -j DROP			
			            #iptables -A INPUT -p tcp --match multiport --dports $SERVER_TCP_PORT:$(($SERVER_TCP_PORT+4)) -j DROP

			sleep 1;
			#1-5. stop server

			$JJOBS_BASE/stop_server.sh
			sleep 5;
			break;
		#fi
		sleep 1;
	done

	#1-6. server end check
	while true :
	do
		pid="$(ps -ef | grep $JJOBS_BASE/server | grep -v "grep" | awk '{print $2}')"
		if [ -z "$pid" ]
		then
			echo "$(TZ="Asia/Seoul" date +'%Y-%m-%d %T') jjob-server is terminated."
			break
		fi
		sleep 1;
	done
fi

if [ "$STOP_AGENT" == "Y" ] && [ "$AGENT_STATUS" == "RUNNING" ]
then
	#2-2. Check Agent down and delete pod
	while true :
	do
		pid="$(ps -ef | grep cname=jjobs | grep -v "grep" | awk '{print $2}')"
		if [ -z "$pid" ]
		then
		echo "$(TZ="Asia/Seoul" date +'%Y-%m-%d %T') jjob-agent is terminated."
			break
		fi
		sleep 1;
	done
fi

exit 0;
