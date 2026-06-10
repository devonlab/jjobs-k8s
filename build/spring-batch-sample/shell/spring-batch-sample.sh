#!/bin/sh
cd /working

PARAMS=""
[ -n "$FILE_NAME" ]        && PARAMS="$PARAMS FILE_NAME=$FILE_NAME"
[ -n "$SLEEP_TIME" ]       && PARAMS="$PARAMS SLEEP_TIME=$SLEEP_TIME"
[ -n "$SLEEP_TIME_INDEX" ] && PARAMS="$PARAMS SLEEP_TIME_INDEX=$SLEEP_TIME_INDEX"

$JAVA_HOME/bin/java -jar ./springbatch-sample-1.0.0.jar $PARAMS $@
exit $?

