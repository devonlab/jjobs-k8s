#!/bin/bash

TAILED_FILES="/tmp/agent_tailed_files_$$"
touch $TAILED_FILES

CURRENT_DATE=""

while true; do
  DATE=$(date +%Y%m%d)

  # 날짜 변경 시 TAILED_FILES 정리
  if [ -n "$CURRENT_DATE" ] && [ "$DATE" != "$CURRENT_DATE" ]; then
    echo "Date changed: $CURRENT_DATE -> $DATE, cleaning old entries..."
    grep -v "$CURRENT_DATE" $TAILED_FILES > ${TAILED_FILES}.tmp 2>/dev/null
    mv ${TAILED_FILES}.tmp $TAILED_FILES 2>/dev/null || touch $TAILED_FILES
  fi

  CURRENT_DATE=$DATE

  # 오늘 날짜 로그 파일 찾기
  for logfile in $LOGS_BASE/agent/$HOSTNAME/logs/agent/$DATE/sys_*.log \
                 $LOGS_BASE/agent/$HOSTNAME/logs/runtime/$DATE/sys_*.log; do

    # 파일이 존재하고 아직 tail 중이지 않으면
    if [ -f "$logfile" ] && ! grep -q "^${logfile}$" $TAILED_FILES; then
      # timeout으로 24시간 후 자동 종료
      timeout 86400 tail -F -n 100 -q "$logfile" 2>/dev/null &
      echo "$logfile" >> $TAILED_FILES
      echo "Started tailing: $logfile (PID: $!)"
    fi
  done

  # 1분마다 새 파일 확인
  sleep 60
done
