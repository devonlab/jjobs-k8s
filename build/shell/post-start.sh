#!/bin/bash
#install kind: M => Do nothing
#install kind: S && ON_BOOT: yes or y or exeptagent && RESUME_ON_STARTUP: y or yes => Server resume
#install kind: A && ON_BOOT: yes or y && RESUME_ON_STARTUP: y or yes => Agent resume
#install kind: F && ON_BOOT: yes or y && RESUME_ON_STARTUP: y or yes => Server & Agent resume 
#		 && ON_BOOT: exceptagent && RESUME_ON_STARTUP: y or yes => Server resume

if [ "$INSTALL_KIND" == "S" ] || [ "$INSTALL_KIND" == "F" ]
then
  if [ "$ON_BOOT" == "yes" ] || [ "$ON_BOOT" == "y" ] || [ "$ON_BOOT" == "exceptagent" ]
  then
    RELEASE_SERVER="Y"
  fi
fi

if [ "$INSTALL_KIND" == "F" ] || [ "$INSTALL_KIND" == "A" ]
then
  if [ "$ON_BOOT" == "yes" ] || [ "$ON_BOOT" == "y" ]
  then
    RELEASE_AGENT="Y"
  fi
fi

if [ "$RELEASE_AGENT" == "Y" ]
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


if [ "$RELEASE_SERVER" == "Y" ]
then
	str=$HOSTNAME
	id=${str:(-1):1}
	INT=$((id))
	realServerId=$(($INT + 1))

	while true :
	do
		#1. Server gracefully release
		#1-1. Check server startup
		curl -sS http://localhost:$SERVER_WEB_PORT/jjob-server/test.jsp

		if [ $? -eq 0 ]; then
		  echo "$(TZ="Asia/Seoul" date +'%Y-%m-%d %T') J-Jobs Server Started up"
		  break
		fi

		sleep 1;
	done

  while true :
  do
		#1-2. Release Server
		RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
                    -H "Content-Type: application/json" \
                    -H "private-token: $API_PRIVATE_TOKEN" \
                    -d '{"groupId":1,"serverId":'"$realServerId"',"holdWorkerYn":"N"}' \
                    http://localhost:$SERVER_WEB_PORT/jjob-server/api/v1/serversetting/server/hold)

    if [ "$RESPONSE" -eq 200 ]; then
      echo "$(TZ="Asia/Seoul" date +'%Y-%m-%d %T') J-Jobs Server successfully released"
      break
    fi
    sleep 1;
  done
fi

if [ "$RELEASE_AGENT" == "Y" ]
then
	while true :
	do
	  statusInfo=$(curl -X GET \
                      -H "Content-Type: application/json" \
                      -H "private-token: $API_PRIVATE_TOKEN" \
                      "$PROTOCOL://$JJOBS_SERVER_IP:$SERVER_WEB_PORT/jjob-server/api/v1/agentmonitor/$HOSTNAME" | jq -r '.vo.status // empty')

    if [[ "$statusInfo" == "RUNNING" ]]
    then
      echo "$(TZ="Asia/Seoul" date +'%Y-%m-%d %T') J-Jobs Agent succesfully started"
      break
    fi
    sleep 1;
  done


  #2. Agent gracefully release
  #2-1. Agent release
  while true :
  do
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
                    -H "Content-Type: application/json" \
                    -H "private-token: $API_PRIVATE_TOKEN" \
                    -d "{\"groupId\":1,\"agentGroupId\":null,\"agentName\":\"$HOSTNAME\"}" \
                    $PROTOCOL://$JJOBS_SERVER_IP:$SERVER_WEB_PORT/jjob-server/api/v1/serversetting/agent/releaseAgent)

    if [ "$RESPONSE" -eq 200 ]; then
      echo "$(TZ="Asia/Seoul" date +'%Y-%m-%d %T') J-Jobs Agent successfully released"
      break
    fi
    sleep 1;
  done
fi

sleep 1;
exit 0;
