#!/bin/bash
set -e

if [ "$ON_BOOT" == "yes" ] || [ "$ON_BOOT" == "y" ] || [ "$ON_BOOT" == "manual" ] || [ "$ON_BOOT" == "manager" ] || [ "$ON_BOOT" == "exceptagent" ]
then
  if [ "$INSTALL_KIND" == "A" ]
  then
          . $WORKING_DIR/install-agent.sh
  else
          . $WORKING_DIR/install-jjobs.sh
  fi

  sleep 1
  . $WORKING_DIR/after-install.sh

  if [ "$ON_BOOT" == "yes" ] || [ "$ON_BOOT" == "y" ]; then
    if [ "$INSTALL_KIND" == "A" ]; then
      env -u JAVA_TOOL_OPTIONS bash -c ". $JJOBS_BASE/start_agent.sh" &
    elif [ "$INSTALL_KIND" == "S" ]; then
      env -u JAVA_TOOL_OPTIONS bash -c ". $JJOBS_BASE/start_server.sh" &
    elif [ "$INSTALL_KIND" == "M" ]; then
      env -u JAVA_TOOL_OPTIONS bash -c ". $JJOBS_BASE/start_manager.sh" &
    else
      echo "start all..."
      env -u JAVA_TOOL_OPTIONS bash -c ". $WORKING_DIR/start-all.sh" &
    fi
  elif [ "$ON_BOOT" == "manager" ]; then
    echo "start manager..."
    env -u JAVA_TOOL_OPTIONS bash -c ". $JJOBS_BASE/start_manager.sh" &
  elif [ "$ON_BOOT" == "exceptagent" ]; then
    echo "start manager and server..."
    env -u JAVA_TOOL_OPTIONS bash -c ". $JJOBS_BASE/start_manager.sh" &
    sleep 10
    env -u JAVA_TOOL_OPTIONS bash -c ". $JJOBS_BASE/start_server.sh" &
  else
    echo "manual start..."
  fi
else
  echo "onBoot=No..."
fi

##
## Workaround for graceful shutdown.
##
while [ "$END" == '' ]; do
        sleep 5
done
;;
