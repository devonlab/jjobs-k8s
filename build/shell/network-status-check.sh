#!/bin/bash
# Get JDBC Host and Port
db_host=$(echo $JDBC_URL | sed -E 's/jdbc:[a-z]+:\/\/([^:/]+).*/\1/')
db_port=$(echo $JDBC_URL | sed -E 's/jdbc:[a-z]+:\/\/[^:/]+:([0-9]+).*/\1/')

#check network status from manager/server to db
if [ "$INSTALL_KIND" == "S" ] || [ "$INSTALL_KIND" == "F" ]
then
    if [ "$ON_BOOT" == "yes" ] || [ "$ON_BOOT" == "y" ] || [ "$ON_BOOT" == "exceptagent" ]
    then
        while true; do
            (echo quit | telnet $db_host $db_port) 2>&1 | grep -q "Connected to"

            if [ $? -eq 0 ]; then
                echo "Database connection is available."
                break
            else
                echo "Database connection failed. Retrying in 5 seconds..."
                sleep 5
            fi
        done
    fi
fi
#check network status from agent to server
if [ "$INSTALL_KIND" == "A" ]
then
    if [ "$ON_BOOT" == "yes" ] || [ "$ON_BOOT" == "y" ]
    then
        while true; do
            curl -s $JJOBS_SERVER_IP:$SERVER_WEB_PORT/jjob-server/test.jsp > /dev/null

            if [ $? -eq 0 ]; then
                echo "jjob-server is available."
                break
            else
                echo "jjob-server status check failed. Retrying in 5 seconds..."
                sleep 5
            fi
        done
    fi
fi