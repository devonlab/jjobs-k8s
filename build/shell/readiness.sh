#!/bin/bash
#install kind: M && ON_BOOT: yes or y or exeptagent  => Manager check
#install kind: S && ON_BOOT: yes or y or exeptagent && RESUME_ON_STARTUP: y or yes => Server check
#install kind: A && ON_BOOT: yes or y => Agent check
#install kind: F && ON_BOOT: yes or y => Manager, Server, Agent check
#                && ON_BOOT: exceptagent => Manager, Server check

if [ -z "$API_PRIVATE_TOKEN" ]
then
        echo "API_PRIVATE_TOKEN IS EMPTY!!"
        exit 1;
fi

if [ "$INSTALL_KIND" == "M" ] || [ "$INSTALL_KIND" == "F" ]
then
        if [ "$ON_BOOT" == "yes" ] || [ "$ON_BOOT" == "y" ] || [ "$ON_BOOT" == "exceptagent" ]
        then
                CHECK_MANAGER="Y"
        fi
fi
if [ "$INSTALL_KIND" == "S" ] || [ "$INSTALL_KIND" == "F" ]
then
        if [ "$ON_BOOT" == "yes" ] || [ "$ON_BOOT" == "y" ] || [ "$ON_BOOT" == "exceptagent" ]
        then
                CHECK_SERVER="Y"
        fi
fi
if [ "$INSTALL_KIND" == "F" ] || [ "$INSTALL_KIND" == "A" ]
then
        if [ "$ON_BOOT" == "yes" ] || [ "$ON_BOOT" == "y" ]
        then
                CHECK_AGENT="Y"
        fi
fi

if [ "$CHECK_AGENT" == "Y" ]
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

if [ "$CHECK_MANAGER" == "Y" ]
then
        #1. Check manager status
        curl -sS http://localhost:$MANAGER_WEB_PORT/jjob-manager/ > /dev/null

        if [ $? -ne 0 ]
        then
                echo "$(TZ="Asia/Seoul" date +'%Y-%m-%d %T') J-Jobs Manager readiness check Failed."
                exit 1;
        fi
        sleep 1;
fi

if [ "$CHECK_SERVER" == "Y" ]
then
        #1. Check server status
        str=$HOSTNAME
        id=${str:(-1):1}
        INT=$((id))
        SERVER_ID=$(($INT + 1))

        statusInfo=$(curl -X GET -sS \
                        -H "Content-Type: application/json" \
                        -H "private-token: $API_PRIVATE_TOKEN" \
                        "http://localhost:$SERVER_WEB_PORT/jjob-server/api/v1/statusmonitor/list" | jq -r ".list.group.g1.s${SERVER_ID}.status")

        if [ "$statusInfo" != "R" ] && [ "$statusInfo" != "W" ]
        then
                echo "$(TZ="Asia/Seoul" date +'%Y-%m-%d %T') J-Jobs Server readiness check Failed."
                exit 1;
        fi

        sleep 1;
fi

if [ "$CHECK_AGENT" == "Y" ]
then
        statusInfo=$(curl -X GET -sS \
                -H "Content-Type: application/json" \
                -H "private-token: $API_PRIVATE_TOKEN" \
                "$PROTOCOL://$JJOBS_SERVER_IP:$SERVER_WEB_PORT/jjob-server/api/v1/agentmonitor/$HOSTNAME" | jq -r '.vo.status // empty')

        if [[ "$statusInfo" != "RUNNING" ]]
        then
                echo "$(TZ="Asia/Seoul" date +'%Y-%m-%d %T') J-Jobs Agent readiness check Failed."
                exit 1;
        fi
        sleep 1;
fi
