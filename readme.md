# J-Jobs for kubernetes
Kubernetes(이하 k8s) 환경에서 J-Jobs v2를 서비스하기 위한 방법을 기술한 문서입니다.
>기타 관련된 자세한 문의사항은 j-jobs@lgcns.com으로 연락주시기 바랍니다.

## 준비사항
### J-Jobs Meta DB
J-Jobs를 위한 Meta DBMS가 사전에 구성되어야 한다. 기존에 사용 중인 DBMS가 있을 경우, J-Jobs에서 사용할 수 있는 DB 계정을 준비한다. J-Jobs에서는 현재 Oracle, MariaDB, MySQL, PostgreSQL를 Meta DBMS로 지원한다.

### J-Jobs 구성
J-Jobs에서 사용되는 k8s 자원은 다음과 같다.
* `StatefulSet` : 배치 관리 서버 역할의 J-Jobs manager/server에서 사용하며, J-Jobs 이중화 구성 시 replica 개수로 조정한다.
* `Headless Service` : J-Jobs 서버와 에이전트 간의 Http/TCP 연결에 사용됨 (7075, 17075~17079)
* `LoadBalancer` : 사용자가 J-Jobs 매니저 접속 시 사용하는 service
  * 사용 환경 구성에 따라 달라질 수 있으며, ClusterIP의 externalIPs 혹은 LoadBalancer로 구성 가능
* `PersistentVolume(PV)` - J-Jobs 매니저/서버/에이전트의 로그 유지를 위한 볼륨
  * 사용 환경 구성에 따라 달라질 수 있으며, AWS 환경에서는 EFS 사용

## 시작하기
### 전체 설치
J-Jobs의 매니저, 서버, 에이전트를 하나의 Pod 안에 설치하고 기동한다.

#### Config 설정
초기 설치 시에는 `ON_BOOT` 설정을 'manual' 또는 'manager'로 설정하고, 설치가 종료된 이후에 'yes'로 변경하여 사용한다.
해당 설정은 statefulset manifest의 환경 변수(`.spec.template.spec.containers[].env`)로 관리한다.

| Key                  | Default value                          | Description                                                                                                                                                                                                                           |
|----------------------|----------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| INSTALL_KIND         | F                                      | J-Jobs 설치 유형<br/> - F : 전체 설치<br/>- M : Manager 단독 설치<br/>- S : Server 단독 설치<br/>- A : Agent 단독 설치                                                                                                                                    |
| ON_BOOT              | yes (or y)                             | 설치 & 구동 관련 옵션<br/> -yes (or y) : 설치 후 모두 기동<br/>- manual : 설치 후 기동은 Pod에 접속하여 직접 수행(초기 설치 시 사용)<br/>- manager : 설치 후 매니저만 기동(초기 설치 시 사용)<br/>- no (기타) : 설치 및 기동 모두 하지 않음 <br/>- exceptagent : 에이전트 제외한 매니저, 서버 기동                    |
| MANAGER_WEB_PORT     | 7065                                   | J-Jobs 매니저 web(was) port                                                                                                                                                                                                              |
| SERVER_WEB_PORT      | 7075                                   | J-Jobs 서버 web(was) port                                                                                                                                                                                                               |
| SERVER_TCP_PORT      | 17075                                  | J-Job 서버와 에이전트 간의 통신을 위한 TCP Port                                                                                                                                                                                                     |
| DB_TYPE              | postgres                               | J-Jobs의 Meta DB 유형<br/>-postgres<br/>-oracle<br/>-mysql<br/>mariadb                                                                                                                                                                   |
| JDBC_URL             | jdbc:postgresql://127.0.0.1:7432/jjobs | DB 접속 JDBC URL 설정                                                                                                                                                                                                                     |
| USE_DB_ENCRYPT       | N                                      | 	DB 사용자명, 패스워드 암호화 사용 여부 사용자명                                                                                                                                                                                                         |
| DB_USER              | jjobs                                  | 	JDBC URL로 DB에 접속할 때 사용자명                                                                                                                                                                                                             |
| DB_PASSWD	           | jjobs1234                              | JDBC URL로 DB에 접속할 때 패스워드                                                                                                                                                                                                              |
| ENCRYPTED_DB_USER    | oSAv48QO9j6VAy7mT8YYbA==               | 	JDBC URL로 DB에 접속할 때 사용자명<br/>USE_DB_ENCRTPY가 Y 일 때 사용                                                                                                                                                                                |
| ENCRYPTED_DB_PASSWD	 | v3bY7QfdJPzTEuxcVWlq3w==               | JDBC URL로 DB에 접속할 때 패스워드<br/>USE_DB_ENCRTPY가 Y 일 때 사용                                                                                                                                                                                 |
| JJOB_SERVICE_NAME    | jjobs.default.svc.cluster.local        | Manager에서 Server로 통신할 jjob-server의 서비스명을 입력한다.(전체 설치/서버 설치 시 사용)<br/>start_server.sh 에서 JJOB_SERVER_IP 값으로 "pod의 hostname + JJOB_SERVICE_NAME"를 사용한다.<br/><br/>(예시)<br/>export JJOB_SERVER_IP=jjobs-0.jjobs.default.svc.cluster.local |
| AGENT_GROUP_ID       | 0                                      | 	에이전트 그룹 ID 설정                                                                                                                                                                                                                        |
| LOGS_BASE	         | /logs001/jjobs	                        | (에이전트 설정) 로그 경로                                                                                                                                                                                                                       |
| LOG_KEEP_DATE	       | 5                                      | 	(에이전트 설정) 로그 유지 일수                                                                                                                                                                                                                   |
| LOG_DELETE_YN        | 	Y                                     | (에이전트 설정) 로그 백업 옵션<br/>-Y : 삭제<br/>-N : 백업<br/>-Z : 백업/압축                                                                                                                                                                             |
| JJOBS_SERVER_IP      | 	127.0.0.1                             | 에이전트가 서버에 접근하기 위한 서버의 서비스 IP<br/><br/>(예시)<br/>start_agent.sh에 들어가는 서버 IP(JJOBS_SERVER_IP)는 서비스 명을 사용해도 됨 → jjobs.default.svc.cluster.local                                                                                           |
| NETWORKADDRESS_CACHE_TTL      | 	1                                     | Java의 DNS positive cache (정상적으로 조회된 DNS)의 TTL(Time To Live) 설정                                                                                                                                                                        |
| NETWORKADDRESS_CACHE_NEGATIVE_TTL      | 	3                                     | Java의 DNS negative cache (실패한 DNS 조회)의 TTL(Time To Live) 설정                                                                                                                                                                           |
| API_PRIVATE_TOKEN    |                                        | `readinessProbe`와 `preStop`, `postStart` 훅에 사용할 J-Jobs 사용자의 비밀 토큰<br/><br/>(예시)<br/>26da841583291d1b6ef7                                                                                                                              |
| WGET_URL |                                        | 추가 APP 설치 필요 시 다운로드 URL<br/>zip, tar.gz, tar 형식의 경우 다운로드 후 WGET_FOLDER_PATH 경로에 압축 해제함<br/><br/>(예시)<br/>https://download.java.net/java/GA/jdk17.0.2/dfd4a8d0985749f896bed50d7138ee7f/8/GPL/openjdk-17.0.2_linux-x64_bin.tar.gz       |
| WGET_FOLDER_PATH |                                        | 추가 APP 설치 필요 시 설치 경로<br/><br/>(예시)<br/>/home/jjobs/jdk-test                                                                                                                                                                           |
| WGET_FILE_NAME |                                        | 추가 APP 다운로드 파일명<br/><br/>(예시)<br/>jdk17.tar.gz                                                                                                                                                                                        |
| CUSTOM_COMMAND |                                        | J-Jobs 설치 후, 기동 전 동적으로 실행할 명령어가 있을 경우 기입<br/><br/>(예시)<br/>"echo 'Hello from env!' && ls -l"<br/>명령어 내 쌍따옴표(")나 백슬래쉬(\\) 사용이 필요할 경우 이스케이프 처리하여 사용한다.                                                                                  |
| JJOBS_AGENT_STARTUP_TIMEOUT | 5                                      | J-Jobs Agent가 Runtime 프로세스를 기동한 뒤 기다리는 대기 시간을 기입한다.</br>Datadog Java Agent 주입 등 외부 애플리케이션과 상호 작용 등으로 Runtime 기동에 대기 시간이 필요할 경우 J-Jobs 담당자와 논의하여 대기 시간을 조정 설정한다.(Datadog java agent 주입의 경우 30초 권장)                     |
| CATALINA_OPTS        |                                        | J-Jobs Manager/Server(Tomcat)의 JVM 옵션 설정. 메모리 할당(RAMPercentage) 및 GC 옵션 등을 설정할 때 사용한다.                                                                                                                                  |
| KUBE_CONTEXTS        |                                        | (에이전트 설정) 다중 클러스터에 Job을 분배할 때 등록할 클러스터 kubectl context 정의(JSON 배열). 비우거나 미설정 시 no-op으로 단일 클러스터(현재 클러스터) 동작을 유지한다. provider(`eks`/`raw`/`incluster`)별 스키마·예시는 아래 "다중 클러스터(Multi-Cluster) 가이드" 참고. |
| AWS_DEFAULT_REGION   | ap-northeast-2                         | (에이전트 설정) `KUBE_CONTEXTS` 의 `eks` provider가 사용하는 aws CLI fallback region. 항목별 `region` 을 명시하므로 디버깅용 fallback이며, `eks` 를 쓰지 않으면(`raw`/`incluster`만 사용) 불필요하다. |

#### 메모리 최적화 설정
컨테이너 리소스 제한(`limits.memory`)에 따라 JVM Heap 메모리를 퍼센티지(%) 단위로 동적으로 할당하도록 설정을 권장한다. `CATALINA_OPTS` 환경 변수를 사용하며, 기동 모드(`ON_BOOT`)에 따라 다음과 같이 구성한다.
- Manager 또는 Server 단독 기동 시(`ON_BOOT: manager` 또는 `server`):
  - `-XX:InitialRAMPercentage=50.0 -XX:MaxRAMPercentage=50.0`
- Manager, Server 함께 기동 시(`ON_BOOT: exceptagent`):
  - `-XX:InitialRAMPercentage=25.0 -XX:MaxRAMPercentage=25.0`
  - 하나의 컨테이너에서 두 개의 WAS가 구동되므로, 각각 25%씩(총 50%) 할당하여 Non-Heap 영역 및 OS 여유 메모리를 확보한다.

#### Graceful shutdown 설정
재기동, 버전 업그레이드 등으로 pod의 종료/기동이 필요한 경우 Job 실행 정보의 정합성 유지를 위해 jjob-server와 Agent 종료 이후 pod를 종료하는 것을 권장한다.
- jjob-server: 서버에서 처리중인 job이 없을 때, jjob-server가 설치된 pod 내부의 stop_server.sh 스크립트 수행 후 pod 종료
- Agent: jjob-manager에 admin 계정으로 로그인 > 시스템설정 > 에이전트설정 메뉴에서 종료하려는 에이전트의 에이전트 일시정지 & 중지 버튼을 클릭하여, 실행중인 Job이 모두 처리 완료된 후 Agent 프로세스 종료

위 작업을 매니저/서버 Statefulset과 Agent Statefulset 설정을 통해 자동화할 수 있다.
- `.spec.template.spec.containers.lifecycle.preStop` : 컨테이너가 종료되기 직전 호출되는 명령어로, 위에서 설명한 매니저/서버/Agent가 권장 상태로 종료되도록 확인하고, pod를 삭제하도록 구성된 pre-stop.sh 파일이 호출된다.
- `.spec.template.spec.containers.lifecycle.postStart` : 컨테이너가 생성된 직후 호출되는 명령어로, 서비스 정상 기동 확인 및 일시정지된 서버/에이전트를 재개하는 post-start.sh 파일이 호출된다.
- `.spec.template.spec.terminationGracePeriodSeconds` : preStop 훅이 실행될 수 있는 충분한 유예(처리중인 Job이 완료될 수 있는) 시간을 정의한다. 해당 시간이 경과되면 처리중인 Job이 있더라도 Pod가 종료된다.
- 초기 설치 시에는 `preStop`과 `postStart` 훅에서 사용할 `API_PRIVATE_TOKEN`을 정의할 수 없으므로, 해당 환경 변수와 `.spec.template.spec.containers.lifecycle`을 정의하지 않음으로써 Graceful shutdown 설정을 구성하지 않고 설치한다.
- `API_PRIVATE_TOKEN` 확인 방법은 J-Jobs 가이드 문서의 `04_개발자가이드 > 01_REST_API > ##1.3 헤더` 부분을 참고한다.

#### 컨테이너 상태 검증
- J-Jobs 자원(매니저/서버/에이전트)에 대한 상태 검증을 위해 livenessProbe와 readinessProbe를 설정한다.
- livenessProbe는 컨테이너가 정상적으로 동작하는지 확인하기 위한 설정으로, liveness.sh 파일을 호출하여 J-Jobs 프로세스가 정상적으로 동작하는지 확인한다.
- readinessProbe는 컨테이너가 요청을 처리할 준비가 되었는지 확인하기 위한 설정으로, readiness.sh 파일을 호출하여 J-Jobs 자원의 통신 상태가 정상인지 확인한다.
- 초기 설치 시에는 `reaindessProbe` 커맨드에서 사용할 `API_PRIVATE_TOKEN`을 정의할 수 없으므로, `spec.template.spec.containers.readinessProbe`을 정의하지 않고 설치한다. 

#### 매니저/서버를 위한 StatefulSet 구성
- 초기 설치 시에는 replica 1로 설정하여 StatefulSet 생성
- J-Jobs 설치 이미지 URL 확인 (Docker Hub or 프로젝트의 Docker Registry)
- PersistentVolume(EFS) 사용 여부 확인 후 volumeClaimTemplates, volumeMounts 조정

##### 매니저/서버 Statefulset 예시

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: jjobs
spec:
  replicas: 2
  serviceName: jjobs
  selector:
    matchLabels:
      app.kubernetes.io/name: jjobs
  template:
    metadata:
      labels:
        app.kubernetes.io/name: jjobs
    spec:
      terminationGracePeriodSeconds: 36000
      containers:
        - name: jjobs
          image: devonlab/jjobs:latest
          imagePullPolicy: Always
          #lifecycle:
            #preStop:
              #exec:
                #command:
                  #- /bin/bash
                  #- -c
                  #- /pre-stop.sh
            #postStart:
              #exec:
                #command:
                  #- /bin/sh
                  #- -c
                  #- /post-start.sh
          env:
            - name: MANAGER_WEB_PORT
              value: "7065"
            - name: SERVER_WEB_PORT
              value: "7075"
            - name: SERVER_TCP_PORT
              value: "17075"
            - name: DB_TYPE
              value: <input_your_db_type>
            - name: JDBC_URL
              value: <input_your_jdbc_url>
            - name: JDBC_PARAMETERS
              value: <input_your_jdbc_parameters>
            - name: DB_USER
              value: <input_your_db_username>
            - name: DB_PASSWD
              value: <input_your_db_password>
            - name: LOGS_BASE
              value: "/logs001/jjobs"
            - name: LOG_KEEP_DATE
              value: "10"
            - name: LOG_DELETE_YN
              value: "Y"
            - name: NETWORKADDRESS_CACHE_TTL
              value: "1"
            - name: NETWORKADDRESS_CACHE_NEGATIVE_TTL
              value: "3"
            - name: ON_BOOT
              value: "exceptagent"
            - name: INSTALL_KIND
              value: "F"
            - name: AGENT_GROUP_ID
              value: "1"
            - name: JJOB_SERVICE_NAME
              value: "jjobs.default.svc.cluster.local"
            - name: LANG
              value: ko_KR.utf8
            - name: CATALINA_OPTS
              value: "-XX:InitialRAMPercentage=25.0 -XX:MaxRAMPercentage=25.0"
            #- name: CUSTOM_COMMAND
              #value: "echo 'Hello from env!' && ls -l"
            #- name: API_PRIVATE_TOKEN
              #value: <input_your_api_user_private_token>
          ports:
            - containerPort: 7065
            - containerPort: 7075
            - containerPort: 17075
            - containerPort: 17076
            - containerPort: 17077
            - containerPort: 17078
            - containerPort: 17079
          volumeMounts:
            - mountPath: /logs001/jjobs
              name: jjobs-logs
          resources:
            requests:
              memory: "1024Mi"
              cpu: "1"
            limits:
              memory: "2048Mi"
              cpu: "2"
          livenessProbe:
            exec:
              command:
                - /bin/bash
                - -c
                - /working/liveness.sh
            initialDelaySeconds: 300
            periodSeconds: 5
            timeoutSeconds: 10
          #readinessProbe:
            #exec:
              #command:
                #- /bin/bash
                #- -c
                #- /working/readiness.sh
            #initialDelaySeconds: 60
            #periodSeconds: 5
            #timeoutSeconds: 10
      volumes:
        - name: jjobs-logs
          persistentVolumeClaim:
            claimName: efs-pvc-jjobs
```

#### 매니저를 위한 Kubernetes Service 구성
- 할당 가능한 IP가 있을 경우 ClusterIP의 externalIPs 설정을 통한 매니저 서비스 노출이 가능함
- 매니저/서버가 다중화 된 경우 로드 밸런서를 구성해야 하는 등 설치 환경/프로젝트 환경에 따라 서비스 설정이 다를 수 있음
  (아래는 매니저/서버 Service 구성 예시임)

##### Service 사용 예시(externalIPs 사용)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: jjob-manager
spec:
  selector:
    app.kubernetes.io/name: jjobs
  ports:
    - name: service
      protocol: TCP
      port: 7065
      targetPort: 7065
  externalIPs:
  - 192.168.0.1
```

##### AWS LoadBalancer 사용 예시

```yaml
apiVersion: v1
kind: Service
metadata:
  name: jjobs-web-service
  namespace: default
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"
    service.beta.kubernetes.io/aws-load-balancer-type: external
    service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
spec:
  ports:
    - name: manager-web
      port: 7065
      targetPort: 7065
      protocol: TCP
    - name: server-web
      port: 7075
      targetPort: 7075
      protocol: TCP
  type: LoadBalancer
  selector:
    app.kubernetes.io/name: jjobs
```

#### Pod 실행 확인 및 수동 기동
J-Jobs Pod에 접속하여 설치 파일, 로그 파일, start*.sh을 확인하고 `ON_BOOT` 옵션에 따라 매니저, 서버, 에이전트 구동 프로세스 확인 또는 수동으로 start*.sh 수행한다.
컨테이너 환경에서는 `kubectl logs` 또는 컨테이너 로그를 통해 표준 출력에 기록되는 `매니저`, `서버`, `에이전트`, `런타임 로그`를 함께 확인한다.

```shell
> kubectl get pods

> kubectl exec -it jjobs-0 -- /bin/bash
> cd /engn001/jjobs
> ./start_manager.sh
```

#### 매니저 접속 URL 확인
설정에 따라 externalIPs 혹은 LoadBalance Address 확인 후 접속한다.

```
http://{loadbalancer_address}:7065/jjob-manager
or
http://{externalIP}:7065/jjob-manager
```

#### 메타 테이블 설치 & 초기화 마법사 수행
초기화 마법사 수행 시, 서버 IP를 Headless Service(Pod DNS) 주소로 설정한다.

#### Pod 접속하여 서버/에이전트 구동

```shell
> kubectl get pods

> kubectl exec -it jjobs-0 -- /bin/bash
> cd /engn001/jjobs
> ./start_server.sh
```

```shell
> kubectl get pods

> kubectl exec -it jjobs-agent-0 -- /bin/bash
> cd /engn001/jjobs
> ./start_agent.sh
```

#### 매니저 접속 (1번 서버 정상 동작 확인)
- 서버/에이전트 정상 연결 확인
- 샘플 Job/Planning 수행하여 정상 수행 여부 확인
- J-Jobs 매니저/서버 이중화 구성하고자 하는 경우 서버 설정 추가
- 이중화 구성의 경우, 서버 설정 화면에서 1-2 서버 정보 등록함
- 서버 IP는 Headless Service(Pod DNS) 주소로 설정
- J-Jobs 매니저/서버 이중화 구성 시 Pod 추가
- ConfigMap의 `ON_BOOT` 설정을 yes(또는 y)로 수정하여 반영
- StatefulSet의 replica 개수를 2로 수정하여 반영
- 서버 1-2 상태 확인

### J-Jobs 에이전트 설치
#### Agent를 위한 Statefulset 구성
- `jjobs-agent-statefulset.yaml` 은 `jjobs-rbac.yaml` 이 생성하는 `jjobs-agent` ServiceAccount를 참조한다. 따라서 **`jjobs-rbac.yaml` 을 먼저 apply한 뒤 StatefulSet을 apply**한다(SA가 없으면 Pod가 SA 생성 전까지 기동되지 못한다).
- PersistentVolume(EFS) 사용 여부 확인 후 PersistentVolumeClaim, volume 조정
- 에이전트가 서버에 접근하기 위한 서버의 서비스 IP(Headless Service의 dns)와 port 확인
- 에이전트 설치될 namespace 확인
- J-Jobs 매니저 접속하여 에이전트가 정상적으로 추가되었는지 확인
- 서버/에이전트 정상 연결 확인
- 샘플 작업 실행 테스트

#### Agent Statefulset 예시

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: jjobs-agent
  labels:
    app: jjobs-agent
  namespace: default
spec:
  replicas: 2
  serviceName: jjobs-agent
  podManagementPolicy: "Parallel"
  selector:
    matchLabels:
      app: jjobs-agent
  template:
    metadata:
      labels:
        app: jjobs-agent
    spec:
      terminationGracePeriodSeconds: 36000
      containers:
        - name: jjobs-agent-container
          image: devonlab/jjobs:latest
          #lifecycle:
            #preStop:
              #exec:
                #command:
                  #- /bin/bash
                  #- -c
                  #- /pre-stop.sh
            #postStart:
              #exec:
                #command:
                  #- /bin/sh
                  #- -c
                  #- /post-start.sh
          env:
            - name: AGENT_GROUP_ID
              value: "1"
            - name: JJOBS_SERVER_IP
              value: "jjobs-0.jjobs.default.svc.cluster.local"
            - name: SERVER_WEB_PORT
              value: "7075"
            - name: LOGS_BASE
              value: "/logs001/jjobs"
            - name: LOG_KEEP_DATE
              value: "5"
            - name: LOG_DELETE_YN
              value: "Y"
            - name: ON_BOOT
              value: "yes"
            - name: INSTALL_KIND
              value: "A"
            - name: NETWORKADDRESS_CACHE_TTL
              value: "1"
            - name: NETWORKADDRESS_CACHE_NEGATIVE_TTL
              value: "3"
            - name: LANG
              value: ko_KR.utf8
            #- name: CUSTOM_COMMAND
              #value: "echo 'Hello from env!' && ls -l"
            #- name: API_PRIVATE_TOKEN
              #value: <input_your_api_user_private_token>
            #- name: JJOBS_AGENT_STARTUP_TIMEOUT
              #value: "30"
          volumeMounts:
            - mountPath: /logs001/jjobs
              name: jjobs-default-log
          resources:
            requests:
              memory: "512Mi"
              cpu: "1"
            limits:
              memory: "1024Mi"
              cpu: "2"
          livenessProbe:
            exec:
              command:
              - /bin/bash
              - -c
              - /working/liveness.sh
            initialDelaySeconds: 300
            periodSeconds: 5
            timeoutSeconds: 10
          #readinessProbe:
            #exec:
              #command:
              #- /bin/bash
              #- -c
              #- /working/readiness.sh
            #initialDelaySeconds: 60
            #periodSeconds: 5
            #timeoutSeconds: 10
      volumes:
        - name: jjobs-default-log
          persistentVolumeClaim:
            claimName: efs-jjobs
```

#### PersistentVolumClaim 예시

```yaml
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: efs-jjobs
  namespace: default
  labels:
    app: jjobs-agent
  annotations:
    volume.beta.kubernetes.io/storage-class: "efs-provisioner"
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1Gi
```
#### Container Feature 기능 활성화
J-Jobs에서 사용자 그룹별로 namespace를 관리하거나, k8s Job template을 사용하기 위해서는 Container Feature가 활성화 되어 있어야 한다.</br>
J-Jobs manager를 통해 시스템 관리자(`root`)로 로그인한 뒤, [환경설정 > Feature 설정] 에서 `Container Feature`를 체크하고 저장한다.<br/>상세 설정
 - 종료된 에이전트 자동 삭제 : Job 수행을 위한 일회성 Agent의 생성 또는 Agent의 설정에 의해 Agent명이 유지되지 않는 경우, 연결 종료가 1시간 이상 경과한 Agent를 자동으로 정리(삭제)할 수 있는 기능이다.
 - 명령어 재시도 횟수 : Kubernetes/EKS/GKE 버전 혹은 내부 정책(csr등)에 따라 kubectl 명령어가 간헐적으로 실패할 가능성이 있는 경우, 명령어 실패로 인해 job lifecycle이 방해받지 않도록 재시도 횟수를 지정할 수 있다. (미사용: 0, 기본값: 1, 최댓값: 10, 성공할때 까지 재시작: -1)
 > Container Feature 기능을 활성화할 경우, [관리자 > 사용자설정 > 사용자 그룹]에서 사용자그룹 별로 k8s namespace를 설정할 수 있다. 설정한 namespace는 k8s 관련 템플릿에서 `.spec.namespace`의 값으로 설정되며, 동일한 사용자그룹이 설정된 1레벨 폴더 하위의 모든 job은 동일한 k8s namespace에서 수행되는 것을 의미한다.

##### Container 기능 활성화 이후 Agent의 재기동

J-Jobs에서 Agent가 재기동 될 경우 기본적으로 runtime이 종료되지 않고 실제 수행중인 Job을 완료될 때 까지 기다린 뒤 상태를 업데이트 한다. Agent 기동 이후 상태를 확인할 수 없는 Job 요청/실행건들은 `Stopped` 처리한다.
추가적으로, Container 기능이 활성화 되어 있는 상태에서 Agent가 기동될 경우, Running 상태의 k8sJob, s3WatcherJob의 실행건을 재기동 전 상태를 조회하여 실행 상태를 복원한다.

## 다중 클러스터(Multi-Cluster) 가이드

Agent가 설치된 클러스터 **외의 다른 Kubernetes 클러스터에도 Job Pod를 분배 생성**하기 위한 구성 가이드이다. (현재 클러스터에만 실행한다면 별도 구성이 필요 없다 — context 없이 기본 동작한다.) K8sJob 플러그인은 등록된 클러스터를 타깃할 때 `kubectl` 명령에 `--context=<alias>` 플래그를 부착하므로, Agent 컨테이너 내부에 대상 클러스터의 kubectl context가 등록되어 있고 해당 context로 인증이 동작하는 환경이라면 어떤 인증 방식이든 사용 가능하다.
J-Jobs 컨테이너 이미지에는 `awscli` / `kubectl` 이 포함되어 있어, OS/kubectl 단에서 인증이 동작하면 IRSA / kubeconfig Secret / 정적 자격증명 등 어떤 방식이든 사용할 수 있다.

등록 방식(`provider`)은 대상에 따라 고른다. **클라우드 API 없는 클러스터**(on-prem 등)는 `raw`, **다른 계정의 EKS**는 `eks` 이며, 이 cross-account 시나리오에 한해 아래 IRSA + AssumeRole 흐름을 권장한다. `incluster` 는 멀티클러스터 구성에서 로컬 클러스터까지 원격들과 **동일한 alias 체계로 노출**하고 싶을 때만 쓰는 선택지다(현재 클러스터는 등록 없이도 동작하므로 필수가 아니다).

### 권장 인증 흐름 (cross-account EKS 전용, IRSA + AssumeRole)

> 현재 클러스터에만 Job을 실행한다면 `KUBE_CONTEXTS` 자체가 불필요하다(context 없이 기본 실행). 이 절차는 **다른 계정의 EKS를 타깃**으로 할 때만 필요하다.


1. **Agent 측 클러스터(A 계정)**: Agent Pod의 ServiceAccount(`jjobs-agent`)에 IAM Role을 IRSA annotation으로 부여한다.
   - `jjobs-rbac.yaml` 의 `jjobs-agent` ServiceAccount metadata.annotations 에 `eks.amazonaws.com/role-arn: arn:aws:iam::<A-account>:role/<jjobs-agent-irsa-role>` 입력.
   - 해당 IAM Role의 신뢰 정책은 EKS OIDC Provider를 신뢰하도록 구성한다(표준 IRSA 셋업).
2. **대상 클러스터(B 계정) 측 IAM Role**: 대상 클러스터 접근용 IAM Role을 만들고, 해당 Role의 Trust Policy에서 A 계정의 IRSA Role(`<jjobs-agent-irsa-role>`)이 `sts:AssumeRole` 가능하도록 허용한다.
3. **대상 클러스터 RBAC**: 대상 EKS의 **Access Entry**(권장) 또는 `aws-auth` ConfigMap에 위 B 계정 IAM Role을 매핑하고, K8s Role/ClusterRole로 Pod/Job CRUD 권한을 부여한다.
4. **`KUBE_CONTEXTS` 등록**: StatefulSet env에 아래 스키마로 클러스터 정보를 주입하면 entrypoint가 Pod 부팅 시 항목별 provider에 맞게 context를 자동 등록한다(이 cross-account 흐름은 `provider:"eks"` 로 `aws eks update-kubeconfig` 를 호출한다. 자기 자신 클러스터는 `incluster`, 클라우드 API 없는 클러스터는 `raw` 를 사용).
5. **메타데이터 매핑(운영)**: J-Jobs 관리 화면에서 동일 alias를 K8sJob에 매핑한다.

`update-kubeconfig` 가 등록한 kubeconfig 의 exec credential plugin 이 매 kubectl 호출 시점에 `aws eks get-token` 을 자동 호출하므로, 토큰 캐시·갱신·STS 호출은 J-Jobs 가 아닌 kubectl + aws CLI 가 처리한다.

### `KUBE_CONTEXTS` 스키마

```json
[
  {
    "alias":     "onprem",
    "provider":  "raw",
    "server":    "https://10.0.0.1:6443",
    "caFile":    "/etc/kube/onprem-ca.crt",
    "tokenFile": "/etc/kube/onprem-token",
    "namespace": "default"
  },
  {
    "alias":    "prod-a",
    "provider": "eks",
    "cluster":  "prod-a",
    "region":   "ap-northeast-2"
  },
  {
    "alias":    "prod-b",
    "provider": "eks",
    "cluster":  "prod-b",
    "region":   "us-east-1",
    "roleArn":  "arn:aws:iam::<input_target_account_id>:role/<input_cross_account_role>"
  },
  {
    "alias":    "main",
    "provider": "incluster"
  }
]
```

> 위 예시의 `main`(`incluster`)은 **선택 항목**이다 — 로컬 클러스터까지 원격과 동일한 alias 체계로 노출하려는 경우에만 넣는다. 현재 클러스터는 등록 없이도 기본 동작한다.

`provider` 는 두 갈래로 나뉜다. **클라우드 발견형**(`eks`, 향후 `gke`/`aks`)은 클라우드 API로 엔드포인트·CA를 자동 발견하지만 그만큼 IAM 권한이 필요하다. **명시형**(`raw` 와 그 zero-config 프리셋 `incluster`)은 클라우드 API 없이 `server`/`caFile`/`tokenFile` 로 직접 등록한다.

| Key | 필수 | 적용 provider | 설명 |
|---|:---:|---|---|
| `alias` | ✅ | 공통 | kubectl context 이름. K8sJob 메타데이터에 동일 alias로 매핑한다. |
| `provider` |  | — | `incluster` / `raw` / `eks`. 미지정 시 `eks` 로 처리되어 `cluster` 와 AWS 권한을 요구하므로, 명시하는 것을 권장한다. `gke`/`aks` 는 향후 확장 예정. |
| `cluster` | ✅ | `eks` | 대상 EKS 클러스터 이름. `raw`/`incluster` 에서는 불필요(무시). |
| `region` |  | `eks` | 대상 클러스터의 AWS region. 다중 region 운영 시 항목별 명시 권장. |
| `roleArn` |  | `eks` | cross-account 시나리오에서 AssumeRole 대상 IAM Role ARN. 단일 계정이면 생략. |
| `server` | ✅ | `raw` | 대상 API 서버 URL(`https://host:port`). `incluster` 는 `KUBERNETES_SERVICE_HOST/PORT` 로 자동 설정. |
| `caFile` |  | `raw` | API 서버 CA 인증서 파일 경로(컨테이너 내부). 미지정 시 시스템 신뢰 저장소로 폴백하므로, **사설 CA로 발급된 API 서버라면 등록은 성공해도 이후 kubectl 호출이 TLS 검증에 실패**한다(사실상 필수). `incluster` 는 SA CA 자동 사용. |
| `tokenFile` | ✅ | `raw` | Bearer 토큰 파일 경로(컨테이너 내부). 토큰 회전을 고려해 `tokenFile` 로 등록되어 매 kubectl 호출 시 재읽기된다. `incluster` 는 SA 토큰 자동 사용. |
| `namespace` |  | `raw`/`incluster` | context 기본 namespace. 미지정 시 `incluster` 는 SA namespace, `raw` 는 `default`. |

> **`incluster`** 는 현재 Pod가 떠 있는 클러스터 자신을 alias로 등록한다. 단, **현재 클러스터는 context 없이도 기본 실행**되므로, 이건 멀티클러스터 구성에서 로컬도 원격과 동일하게 alias로 다루고 싶을 때만 쓰는 선택지다(필수 아님). 등록 시 `aws eks update-kubeconfig` 가 요구하는 AWS IAM(`eks:DescribeCluster`) 권한 없이 이미 부여된 in-cluster RBAC만으로 성공하며, 엔드포인트/CA/토큰은 `/var/run/secrets/kubernetes.io/serviceaccount` 에서 읽는다.
>
> **`raw`** 는 클라우드 API가 없는 클러스터(on-prem/kubeadm 등)나 정적 토큰/CA를 마운트한 원격 클러스터를 붙일 때 사용한다. 대상 클러스터에 ServiceAccount + RBAC를 만들고 그 토큰/CA를 Secret으로 마운트한 뒤 경로를 지정하면 된다.

값이 비어있거나 변수 자체가 미설정이면 entrypoint는 **no-op** 으로 단일 클러스터 동작을 유지한다(하위 호환).

### StatefulSet env 적용 예시

`jjobs-agent-statefulset.yaml` 의 `containers[].env` 에 다음을 추가한다(주석 처리된 placeholder 가 이미 manifest에 포함되어 있다).

**단일 클러스터(현재 클러스터에만 Job 실행)** 라면 `KUBE_CONTEXTS` 를 설정할 필요가 없다. 값을 비우거나 생략하면 entrypoint는 no-op하고, K8sJob은 context 없이 현재 클러스터에 그대로 실행된다(기본 동작).

**다중 클러스터**일 때만 아래처럼 대상별 entry를 등록한다.

```yaml
env:
  # AWS_DEFAULT_REGION은 eks provider(aws CLI)에서만 쓰인다. raw/incluster만 사용하면 불필요.
  - name: AWS_DEFAULT_REGION
    value: "ap-northeast-2"   # aws CLI fallback region (디버깅용). 환경에 맞게 조정.
  - name: KUBE_CONTEXTS
    value: |
      [
        {"alias":"onprem","provider":"raw","server":"https://10.0.0.1:6443","caFile":"/etc/kube/onprem-ca.crt","tokenFile":"/etc/kube/onprem-token"},
        {"alias":"prod-a","provider":"eks","cluster":"prod-a","region":"ap-northeast-2"},
        {"alias":"prod-b","provider":"eks","cluster":"prod-b","region":"us-east-1","roleArn":"arn:aws:iam::222222222222:role/CrossAcctEksAccess"},
        {"alias":"main","provider":"incluster"}
      ]
```

> 위 예시의 `main`(`incluster`) 항목은 **선택**이다 — 로컬 클러스터도 원격들과 동일한 alias 체계로 노출할 때만 넣는다. 로컬 Job을 context 없이 돌리는 기본 동작으로 충분하면 생략한다.

> `eks` provider가 호출하는 aws CLI가 컨테이너(비 TTY)에서 pager로 멈추지 않도록 `AWS_PAGER=""` 가 이미지에 내장돼 있다(별도 설정 불필요).

### 동작 확인

Pod 부팅 후 다음으로 검증한다.

```bash
# 컨테이너 진입 후
kubectl config get-contexts
# → KUBE_CONTEXTS에 정의한 alias 들이 모두 등록되어 있어야 한다.

kubectl --context=<alias> get pods -n <target-namespace>
# → 해당 context로 대상 클러스터의 Pod 목록이 조회되어야 한다. (예: --context=prod-a)

# (eks provider, cross-account인 경우에만) IRSA/AssumeRole 자격증명 확인
aws sts get-caller-identity
# → IRSA Role 의 STS 자격증명이 출력되어야 한다.
```

부팅 로그에서 `[KUBE_CONTEXTS] registering kubectl context(s)...` 로 시작하는 메시지로 등록 결과를 확인할 수 있다. 한 항목 실패는 다른 항목과 컨테이너 기동에 영향을 주지 않는다.

### 알려진 한계

- 현재 이미지는 EKS 만 지원한다. GKE / AKS 의 경우 `gcloud` / `az` CLI 가 이미지에 포함되어 있지 않아 향후 별도 image variant 또는 init container 전략으로 확장 예정이다.
- `raw` / `incluster` provider의 `alias` 에는 `.`(마침표)를 사용할 수 없다. entrypoint가 `kubectl config set users.<alias>-sa.tokenFile` 로 등록하는데, alias에 `.`이 있으면 dot 경로가 중첩 파싱되어 context는 등록되나 인증이 동작하지 않는다(예: `prod.a` → `prod-a`로 대체). `eks` provider는 이 제약이 없다.