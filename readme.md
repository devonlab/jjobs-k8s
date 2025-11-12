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

| Key                  | Default value                          | Description                                                                                                                                                                                                                     |
|----------------------|----------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| INSTALL_KIND         | F                                      | J-Jobs 설치 유형<br/> - F : 전체 설치<br/>- M : Manager 단독 설치<br/>- S : Server 단독 설치<br/>- A : Agent 단독 설치                                                                                                                              |
| ON_BOOT              | yes (or y)                                   | 설치 & 구동 관련 옵션<br/> -yes (or y) : 설치 후 모두 기동<br/>- manual : 설치 후 기동은 Pod에 접속하여 직접 수행(초기 설치 시 사용)<br/>- manager : 설치 후 매니저만 기동(초기 설치 시 사용)<br/>- no (기타) : 설치 및 기동 모두 하지 않음 <br/>- exceptagent : 에이전트 제외한 매니저, 서버 기동              |
| MANAGER_WEB_PORT     | 7065                                   | J-Jobs 매니저 web(was) port                                                                                                                                                                                                        |
| SERVER_WEB_PORT      | 7075                                   | J-Jobs 서버 web(was) port                                                                                                                                                                                                         |
| SERVER_TCP_PORT      | 17075                                  | J-Job 서버와 에이전트 간의 통신을 위한 TCP Port                                                                                                                                                                                               |
| DB_TYPE              | postgres                               | J-Jobs의 Meta DB 유형<br/>-postgres<br/>-oracle<br/>-mysql<br/>mariadb                                                                                                                                                             |
| JDBC_URL             | jdbc:postgresql://127.0.0.1:7432/jjobs | DB 접속 JDBC URL 설정                                                                                                                                                                                                               |
| USE_DB_ENCRYPT       | N                                  | 	DB 사용자명, 패스워드 암호화 사용 여부 사용자명                                                                                                                                                                                                   |
| DB_USER              | jjobs                                  | 	JDBC URL로 DB에 접속할 때 사용자명                                                                                                                                                                                                       |
| DB_PASSWD	           | jjobs1234                              | JDBC URL로 DB에 접속할 때 패스워드                                                                                                                                                                                                        |
| ENCRYPTED_DB_USER    | oSAv48QO9j6VAy7mT8YYbA==                                  | 	JDBC URL로 DB에 접속할 때 사용자명<br/>USE_DB_ENCRTPY가 Y 일 때 사용                                                                                                                                                                          |
| ENCRYPTED_DB_PASSWD	 | v3bY7QfdJPzTEuxcVWlq3w==                              | JDBC URL로 DB에 접속할 때 패스워드<br/>USE_DB_ENCRTPY가 Y 일 때 사용                                                                                                                                                                           |
| JJOB_SERVICE_NAME    | jjobs.default.svc.cluster.local        | Manager에서 Server로 통신할 jjob-server의 서비스명을 입력한다.(전체 설치/서버 설치 시 사용)<br/>start_server.sh 에서 JJOB_SERVER_IP 값으로 "pod의 hostname + JJOB_SERVICE_NAME"를 사용한다.<br/><br/>(예시)<br/>export JJOB_SERVER_IP=jjobs-0.jjobs.default.svc.cluster.local      |
| AGENT_GROUP_ID       | 0                                      | 	에이전트 그룹 ID 설정                                                                                                                                                                                                                  |
| LOGS_BASE	         | /logs001/jjobs	                        | (에이전트 설정) 로그 경로                                                                                                                                                                                                                 |
| LOG_KEEP_DATE	       | 5                                      | 	(에이전트 설정) 로그 유지 일수                                                                                                                                                                                                             |
| LOG_DELETE_YN        | 	Y                                     | (에이전트 설정) 로그 백업 옵션<br/>-Y : 삭제<br/>-N : 백업<br/>-Z : 백업/압축                                                                                                                                                                       |
| JJOBS_SERVER_IP      | 	127.0.0.1                             | 에이전트가 서버에 접근하기 위한 서버의 서비스 IP<br/><br/>(예시)<br/>start_agent.sh에 들어가는 서버 IP(JJOBS_SERVER_IP)는 서비스 명을 사용해도 됨 → jjobs.default.svc.cluster.local                                                                                     |
| NETWORKADDRESS_CACHE_TTL      | 	1                                     | Java의 DNS positive cache (정상적으로 조회된 DNS)의 TTL(Time To Live) 설정                                                                                                                                                        |
| NETWORKADDRESS_CACHE_NEGATIVE_TTL      | 	3                                     | Java의 DNS negative cache (실패한 DNS 조회)의 TTL(Time To Live) 설정                                                                                                                                                                    |
| API_PRIVATE_TOKEN    |                                        | `readinessProbe`와 `preStop`, `postStart` 훅에 사용할 J-Jobs 사용자의 비밀 토큰<br/><br/>(예시)<br/>26da841583291d1b6ef7                                                                                                                                          |
| WGET_URL |                                        | 추가 APP 설치 필요 시 다운로드 URL<br/>zip, tar.gz, tar 형식의 경우 다운로드 후 WGET_FOLDER_PATH 경로에 압축 해제함<br/><br/>(예시)<br/>https://download.java.net/java/GA/jdk17.0.2/dfd4a8d0985749f896bed50d7138ee7f/8/GPL/openjdk-17.0.2_linux-x64_bin.tar.gz |
| WGET_FOLDER_PATH |                                        | 추가 APP 설치 필요 시 설치 경로<br/><br/>(예시)<br/>/home/jjobs/jdk-test                                                                                                                                                                     |
| WGET_FILE_NAME |                                        | 추가 APP 다운로드 파일명<br/><br/>(예시)<br/>jdk17.tar.gz                                                                                                                                                                                  |
| CUSTOM_COMMAND |                                        | J-Jobs 설치 후, 기동 전 동적으로 실행할 명령어가 있을 경우 기입<br/><br/>(예시)<br/>"echo 'Hello from env!' && ls -l"<br/>명령어 내 쌍따옴표(")나 백슬래쉬(\\) 사용이 필요할 경우 이스케이프 처리하여 사용한다.                                                                         |

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