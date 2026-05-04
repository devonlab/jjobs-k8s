#!/bin/bash
set -e

# -----------------------------------------------------------------------------
# 다중 Kubernetes 클러스터 kubeconfig 부트스트랩
# -----------------------------------------------------------------------------
# KUBE_CONTEXTS 환경변수(JSON 배열)를 파싱하여 클러스터별 kubectl context를 등록한다.
# 변수가 비어있거나 미설정이면 no-op으로 단일 클러스터 동작을 유지한다(하위 호환).
# 한 항목 실패가 다른 항목 또는 본 entrypoint 흐름에 영향을 주지 않도록 격리한다.
#
# 스키마(예시):
#   [
#     {"alias":"prod-a","provider":"eks","cluster":"prod-a","region":"ap-northeast-2"},
#     {"alias":"prod-b","provider":"eks","cluster":"prod-b","region":"us-east-1",
#      "roleArn":"arn:aws:iam::222:role/CrossAcctEksAccess"}
#   ]
#
# provider 키는 reserved 이며 현재는 "eks"만 구현되어 있다(GKE/AKS는 향후 확장).
# update-kubeconfig 가 등록한 exec credential plugin 이 매 kubectl 호출 시점에
# `aws eks get-token` 을 자동 호출하므로 우리 entrypoint 는 부트스트랩 1회면 충분하다.
# -----------------------------------------------------------------------------
register_kube_contexts() {
  if [ -z "$KUBE_CONTEXTS" ]; then
    return 0
  fi

  if ! command -v jq >/dev/null 2>&1; then
    echo "[KUBE_CONTEXTS] jq not available; skip kubeconfig registration."
    return 0
  fi
  if ! command -v aws >/dev/null 2>&1; then
    echo "[KUBE_CONTEXTS] aws CLI not available; skip kubeconfig registration."
    return 0
  fi

  if ! echo "$KUBE_CONTEXTS" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "[KUBE_CONTEXTS] value is not a valid JSON array; skip."
    return 0
  fi

  # ~/.kube 디렉토리 보장. HOME 미설정 시 root 기본 경로로 폴백.
  local kube_home="${HOME:-/root}/.kube"
  mkdir -p "$kube_home"
  chmod 700 "$kube_home"

  echo "[KUBE_CONTEXTS] registering kubectl context(s)..."
  echo "$KUBE_CONTEXTS" | jq -c '.[]' | while IFS= read -r item; do
    provider=$(echo "$item" | jq -r '.provider // ""')
    ctx_alias=$(echo "$item" | jq -r '.alias // ""')
    cluster=$(echo "$item" | jq -r '.cluster // ""')
    region=$(echo "$item" | jq -r '.region // ""')
    role_arn=$(echo "$item" | jq -r '.roleArn // ""')

    if [ -z "$ctx_alias" ] || [ -z "$cluster" ]; then
      echo "[KUBE_CONTEXTS] item missing alias/cluster; skip. ($item)"
      continue
    fi

    case "$provider" in
      eks|"")
        cmd=(aws eks update-kubeconfig --name "$cluster" --alias "$ctx_alias")
        [ -n "$region" ]   && cmd+=(--region "$region")
        [ -n "$role_arn" ] && cmd+=(--role-arn "$role_arn")
        echo "[KUBE_CONTEXTS] [$ctx_alias] ${cmd[*]}"
        if ! "${cmd[@]}"; then
          echo "[KUBE_CONTEXTS] [$ctx_alias] FAILED to register; continuing with remaining contexts."
        fi
        ;;
      gke|aks)
        echo "[KUBE_CONTEXTS] [$ctx_alias] provider=$provider is reserved but not implemented in this image; skip."
        ;;
      *)
        echo "[KUBE_CONTEXTS] [$ctx_alias] unknown provider=$provider; skip."
        ;;
    esac
  done

  echo "[KUBE_CONTEXTS] registered contexts:"
  kubectl config get-contexts -o name 2>/dev/null || true
}

# 한 클러스터 실패가 컨테이너 기동을 막지 않도록 함수 호출 자체도 보호한다.
register_kube_contexts || true

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
  sleep 1
  if [ -n "$CUSTOM_COMMAND" ]; then
    echo "Executing dynamic command: $CUSTOM_COMMAND"
    eval "$CUSTOM_COMMAND"
  fi
  sleep 1
  (
    $WORKING_DIR/network-status-check.sh || true
  )

  if [ "$ON_BOOT" == "yes" ] || [ "$ON_BOOT" == "y" ]; then
    if [ "$INSTALL_KIND" == "A" ]; then
      . $JJOBS_BASE/start_agent.sh &
    elif [ "$INSTALL_KIND" == "S" ]; then
      . $JJOBS_BASE/start_server.sh &
    elif [ "$INSTALL_KIND" == "M" ]; then
      . $JJOBS_BASE/start_manager.sh &
    else
      echo "start all..."
      . $WORKING_DIR/start-all.sh
    fi
  elif [ "$ON_BOOT" == "manager" ]; then
    echo "start manager..."
    . $JJOBS_BASE/start_manager.sh &
  elif [ "$ON_BOOT" == "exceptagent" ]; then
    echo "start manager and server..."
    . $JJOBS_BASE/start_manager.sh &
    sleep 10
    . $JJOBS_BASE/start_server.sh &
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
