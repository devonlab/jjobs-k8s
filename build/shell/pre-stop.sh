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

if [ "$STOP_AGENT" == "Y" ]
then
	#2. Agent gracefully stop
	#2-1. Agent hold and stop + Check Agent down (Server API를 사용하므로 Server 종료보다 먼저 확인)
	STOP_REQUESTED="N"
	AGENT_ABSENT_COUNT=0
	while true :
	do
		pid="$(ps -ef | grep -E "cname=(agent|jjobs)" | grep -v "grep" | awk '{print $2}')"
		if [ -z "$pid" ]
		then
		echo "$(TZ="Asia/Seoul" date +'%Y-%m-%d %T') jjob-agent is terminated."
			break
		fi

		#2-2. 중지 요청은 성공할 때까지 재시도하고, 성공 후에는 다시 보내지 않음
		if [ "$STOP_REQUESTED" != "Y" ]
		then
			curl -fsS -m 10 -X POST \
			-H "Content-Type: application/json" \
			-H "private-token: $API_PRIVATE_TOKEN" \
			-d "{\"groupId\":1,\"agentGroupId\":null,\"agentName\":\"$HOSTNAME\"}" \
			$PROTOCOL://$JJOBS_SERVER_IP:$SERVER_WEB_PORT/jjob-server/api/v1/serversetting/agent/holdAndStopAgent \
			| jq -e '.status.result.dev_message == "success"' > /dev/null && STOP_REQUESTED="Y"
		fi

		#2-3. runtime만 남은 경우: Agent 종료 + 진행중 Job 0건 + (일시정지 or Agent 부재 60회 연속 확인)이면 종료로 판단
		if [ -z "$(ps -ef | grep cname=agent | grep -v "grep")" ]
		then
			AGENT_ABSENT_COUNT=$((AGENT_ABSENT_COUNT + 1))
			agent=$(curl -fsS -m 10 -G -H "private-token: $API_PRIVATE_TOKEN" \
			--data-urlencode "filter:groupId=1" \
			--data-urlencode "filter:agentNameMatch=$HOSTNAME" \
			$PROTOCOL://$JJOBS_SERVER_IP:$SERVER_WEB_PORT/jjob-server/api/v1/serversetting/agent/list \
			| jq -ce --arg name "$HOSTNAME" --argjson absent "$AGENT_ABSENT_COUNT" '.list[] | select(.agentName == $name and (.isHold == "Y" or $absent >= 60))') &&
			curl -fsS -m 10 -G -H "private-token: $API_PRIVATE_TOKEN" \
			--data-urlencode "filter:groupId=1" \
			--data-urlencode "filter:agentId=$(jq -r '.agentId' <<< "$agent")" \
			--data-urlencode "filter:agentGroupId=$(jq -r '.agentGroupId' <<< "$agent")" \
			--data-urlencode "filter:statusMajor='F'" \
			$PROTOCOL://$JJOBS_SERVER_IP:$SERVER_WEB_PORT/jjob-server/api/v1/job/request/count/map \
			| jq -e '.count == 0' > /dev/null
			if [ $? -eq 0 ]
			then
				echo "$(TZ="Asia/Seoul" date +'%Y-%m-%d %T') jjob-agent process is terminated and has no running job. (remaining pid: $pid)"
				break
			fi
		else
			# main이 다시 떴으면(재기동) 새 main에도 중지 요청을 다시 보낸다
			if [ "$AGENT_ABSENT_COUNT" -gt 0 ]
			then
				STOP_REQUESTED="N"
			fi
			AGENT_ABSENT_COUNT=0
		fi
		sleep 1;
	done
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

exit 0;
