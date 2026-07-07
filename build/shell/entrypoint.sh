#!/bin/bash
set -e

# -----------------------------------------------------------------------------
# 다중 Kubernetes 클러스터 kubeconfig 부트스트랩
# -----------------------------------------------------------------------------
# KUBE_CONTEXTS 환경변수(JSON 배열)를 파싱하여 클러스터별 kubectl context를 등록한다.
# 변수가 비어있거나 미설정이면 no-op으로 단일 클러스터 동작을 유지한다(하위 호환).
# 한 항목 실패가 다른 항목 또는 본 entrypoint 흐름에 영향을 주지 않도록 격리한다.
#
# provider 분류:
#   - eks            : aws eks update-kubeconfig 로 등록. 클라우드 API(eks:DescribeCluster)로
#                      엔드포인트/CA를 발견하므로 IRSA의 IAM 권한이 필요하다. gke/aks는 향후 확장.
#   - raw            : server/caFile/tokenFile 을 명시적으로 받아 등록하는 범용 메커니즘.
#                      클라우드 API가 없는 클러스터(on-prem 등) 또는 정적 토큰/CA를 마운트한 경우에 사용.
#   - incluster      : raw 의 zero-config 프리셋. 현재 Pod가 떠 있는 클러스터 자신을
#                      마운트된 ServiceAccount(엔드포인트/CA/토큰) 기본값만으로 등록한다.
#                      AWS API/IRSA 없이 in-cluster RBAC만으로 성공한다.
#                      (현재 클러스터는 등록 없이도 기본 동작하므로, 로컬을 alias로도
#                       노출하려는 멀티클러스터 구성에서만 쓰는 선택 항목이다.)
#
# 스키마(예시):
#   [
#     {"alias":"onprem","provider":"raw","server":"https://10.0.0.1:6443",
#      "caFile":"/etc/kube/onprem-ca.crt","tokenFile":"/etc/kube/onprem-token","namespace":"default"},
#     {"alias":"prod-a","provider":"eks","cluster":"prod-a","region":"ap-northeast-2"},
#     {"alias":"prod-b","provider":"eks","cluster":"prod-b","region":"us-east-1",
#      "roleArn":"arn:aws:iam::222:role/CrossAcctEksAccess"},
#     {"alias":"main","provider":"incluster"}
#   ]
#
# 토큰은 정적 embed 대신 tokenFile 로 등록하여, projected SA 토큰의 회전 시에도
# 매 kubectl 호출 시점에 파일을 재읽기한다(eks 경로는 aws eks get-token exec plugin이 담당).
# -----------------------------------------------------------------------------

# 통일 로그 헬퍼. 첫 인자는 context alias(없으면 ""), 나머지는 메시지.
# `[KUBE_CONTEXTS]` 프리픽스와 `[alias]` 포맷을 한 곳에서 보장한다.
kc_log() {
  local ctx="$1"; shift
  echo "[KUBE_CONTEXTS]${ctx:+ [$ctx]} $*"
}

# 루프 변수 $item(JSON object)에서 단일 필드를 추출. 미존재 시 빈 문자열.
# 호출자(register_kube_contexts 루프)의 $item을 동적 스코프로 참조한다.
kc_field() { jq -r "$1 // \"\"" <<<"$item"; }

# raw/incluster 공통 등록 헬퍼. server/caFile/tokenFile/namespace 로 kubectl context를 구성한다.
# 한 항목 실패가 전체 흐름을 막지 않도록 호출부에서 `|| true` 로 격리한다.
register_raw_context() {
  # $5(namespace)는 콜론(:-) 형태라 미전달뿐 아니라 빈 문자열도 default로 폴백한다.
  local r_alias="$1" r_server="$2" r_ca_file="$3" r_token_file="$4" r_namespace="${5:-default}"
  local r_user="${r_alias}-sa"

  # alias에 '.'이 있으면 아래 `kubectl config set "users.${r_user}.tokenFile"` 의 dot 경로가
  # users→<앞부분>→<뒷부분>-sa→tokenFile 로 중첩 파싱되어, set-context가 참조하는 평면 user가
  # 존재하지 않게 된다(context는 등록되나 런타임 kubectl 호출이 인증 실패하는 silent failure).
  # eks provider는 aws CLI가 kubeconfig를 직접 쓰므로 무관하며, 이 제약은 raw/incluster에만 적용된다.
  case "$r_alias" in
    *.*)
      kc_log "$r_alias" "FAILED: raw/incluster alias must not contain '.' (breaks 'kubectl config set users.<alias>-sa.tokenFile' path parsing); use e.g. prod-a. Continuing with remaining contexts."
      return 1
      ;;
  esac

  if [ -z "$r_server" ]; then
    kc_log "$r_alias" "FAILED: server is empty; continuing with remaining contexts."
    return 1
  fi
  if [ -z "$r_token_file" ] || [ ! -r "$r_token_file" ]; then
    kc_log "$r_alias" "FAILED: tokenFile not readable ($r_token_file); continuing with remaining contexts."
    return 1
  fi

  local set_cluster_cmd=(kubectl config set-cluster "$r_alias" --server="$r_server")
  if [ -n "$r_ca_file" ] && [ -r "$r_ca_file" ]; then
    set_cluster_cmd+=(--certificate-authority="$r_ca_file" --embed-certs=true)
  else
    # CA 미지정 시 kubectl은 시스템 신뢰 저장소로 폴백한다. 사설 CA로 발급된 API 서버라면
    # 등록 자체는 성공해도 이후 모든 kubectl 호출이 런타임에 TLS 검증 실패한다(지연 실패).
    kc_log "$r_alias" "WARN: caFile not provided/readable ($r_ca_file); registering without CA pin. kubectl calls will fail TLS unless the server cert chains to the system trust store."
  fi

  # set-cluster 성공 후 다음 단계가 실패하면 cluster/user entry가 일부 남을 수 있으나,
  # 짝이 되는 context가 없으면 선택되지 않고 재기동 시 멱등 덮어쓰기되므로 무해하다.
  if "${set_cluster_cmd[@]}" >/dev/null \
     && kubectl config set "users.${r_user}.tokenFile" "$r_token_file" >/dev/null \
     && kubectl config set-context "$r_alias" \
          --cluster="$r_alias" \
          --user="$r_user" \
          --namespace="$r_namespace" >/dev/null; then
    kc_log "$r_alias" "context registered (server=$r_server, namespace=$r_namespace)."
    return 0
  fi

  kc_log "$r_alias" "FAILED to register context; continuing with remaining contexts."
  return 1
}

# raw의 zero-config 프리셋. 현재 Pod가 떠 있는 클러스터 자신을 마운트된 ServiceAccount
# 표준 경로(엔드포인트/CA/토큰)를 기본값으로 채워 등록한다. AWS API/IRSA 불필요.
register_incluster_context() {
  local ic_alias="$1" ic_namespace="$2"
  local sa_dir=/var/run/secrets/kubernetes.io/serviceaccount

  if [ -z "$KUBERNETES_SERVICE_HOST" ]; then
    kc_log "$ic_alias" "FAILED: not running in-cluster (KUBERNETES_SERVICE_HOST unset); continuing with remaining contexts."
    return 1
  fi

  local server="https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT:-443}"
  local namespace="${ic_namespace:-$(cat "$sa_dir/namespace" 2>/dev/null || echo default)}"
  kc_log "$ic_alias" "register in-cluster context from $sa_dir"
  register_raw_context "$ic_alias" "$server" "$sa_dir/ca.crt" "$sa_dir/token" "$namespace"
}

register_kube_contexts() {
  if [ -z "$KUBE_CONTEXTS" ]; then
    return 0
  fi

  if ! command -v jq >/dev/null 2>&1; then
    kc_log "" "jq not available; skip kubeconfig registration."
    return 0
  fi
  # aws CLI는 클라우드 발견형(eks) 경로에서만 필요하다. raw/incluster는 aws 없이도 동작하므로
  # 전역 게이트 대신 eks 분기에서 항목별로 확인한다.

  if ! jq -e 'type == "array"' >/dev/null 2>&1 <<<"$KUBE_CONTEXTS"; then
    kc_log "" "value is not a valid JSON array; skip."
    return 0
  fi

  # ~/.kube 디렉토리 보장. HOME 미설정 시 root 기본 경로로 폴백.
  local kube_home="${HOME:-/root}/.kube"
  mkdir -p "$kube_home"
  chmod 700 "$kube_home"

  kc_log "" "registering kubectl context(s)..."
  # 프로세스 치환으로 루프를 함수 본문 스코프에 유지한다(파이프 서브셸 회피 → 아래 변수들을 local로 가둔다).
  local item provider ctx_alias cluster region role_arn server ca_file token_file namespace cmd
  while IFS= read -r item; do
    provider=$(kc_field '.provider')
    ctx_alias=$(kc_field '.alias')
    cluster=$(kc_field '.cluster')
    region=$(kc_field '.region')
    role_arn=$(kc_field '.roleArn')
    server=$(kc_field '.server')
    ca_file=$(kc_field '.caFile')
    token_file=$(kc_field '.tokenFile')
    namespace=$(kc_field '.namespace')

    if [ -z "$ctx_alias" ]; then
      kc_log "" "item missing alias; skip. ($item)"
      continue
    fi

    case "$provider" in
      raw)
        kc_log "$ctx_alias" "register raw context (server=$server)"
        register_raw_context "$ctx_alias" "$server" "$ca_file" "$token_file" "$namespace" || true
        ;;
      incluster)
        register_incluster_context "$ctx_alias" "$namespace" || true
        ;;
      eks|"")
        # cluster 키는 클라우드 발견형(eks)에만 필요하므로 사용처 바로 옆에서 검증한다.
        if [ -z "$cluster" ]; then
          kc_log "" "item missing cluster; skip. ($item)"
          continue
        fi
        if ! command -v aws >/dev/null 2>&1; then
          kc_log "$ctx_alias" "FAILED: aws CLI not available for eks provider; continuing with remaining contexts."
          continue
        fi
        cmd=(aws eks update-kubeconfig --name "$cluster" --alias "$ctx_alias")
        [ -n "$region" ]   && cmd+=(--region "$region")
        [ -n "$role_arn" ] && cmd+=(--role-arn "$role_arn")
        kc_log "$ctx_alias" "${cmd[*]}"
        if ! "${cmd[@]}"; then
          kc_log "$ctx_alias" "FAILED to register; continuing with remaining contexts."
        fi
        ;;
      gke|aks)
        kc_log "$ctx_alias" "provider=$provider is reserved but not implemented in this image; skip."
        ;;
      *)
        kc_log "$ctx_alias" "unknown provider=$provider; skip."
        ;;
    esac
  done < <(jq -c '.[]' <<<"$KUBE_CONTEXTS")

  kc_log "" "registered contexts:"
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
## kubelet의 SIGTERM 수신시에만 루프를 탈출하여 PID 1을 정상 종료.
##
JJOBS_SIGTERM_RECEIVED=''
trap 'JJOBS_SIGTERM_RECEIVED=1' TERM
while [ -z "$JJOBS_SIGTERM_RECEIVED" ]; do
        sleep 5 &
        wait $! || true
done

exit 0;
