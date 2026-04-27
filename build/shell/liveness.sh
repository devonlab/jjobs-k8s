#!/bin/bash
#install kind: M && ON_BOOT: yes or y or exeptagent  => Manager check
#install kind: S && ON_BOOT: yes or y or exeptagent && RESUME_ON_STARTUP: y or yes => Server check
#install kind: A && ON_BOOT: yes or y => Agent check
#install kind: F && ON_BOOT: yes or y => Manager, Server, Agent check
#                && ON_BOOT: exceptagent => Manager, Server check

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

if [ "$CHECK_MANAGER" == "Y" ]
then
        if [ $(ps -ef | grep "Dcatalina.home=$JJOBS_BASE/manager" | grep -v grep | wc -l) -ne 1 ]
        then
                echo "$(TZ="Asia/Seoul" date +'%Y-%m-%d %T') J-Jobs Manager liveness check failed."
                exit 1
        fi

fi

if [ "$CHECK_SERVER" == "Y" ]
then
        if [ $(ps -ef | grep "Dcatalina.home=$JJOBS_BASE/server" | grep -v grep | wc -l) -ne 1 ]
        then
                echo "$(TZ="Asia/Seoul" date +'%Y-%m-%d %T') J-Jobs Server liveness check failed."
                exit 1
        fi

fi

if [ "$CHECK_AGENT" == "Y" ]
then
        if [ $(ps -ef | grep -v grep | grep "cname=agent" | wc -l) -ne 1 ]
        then
                echo "$(TZ="Asia/Seoul" date +'%Y-%m-%d %T') J-Jobs Agent liveness check failed."
                exit 1
        fi
fi
