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

| Key                | Default value                          | Description                                                                                                                                                                                                |
|--------------------|----------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| INSTALL_KIND       | F                                      | J-Jobs 설치 유형<br/> - F : 전체 설치<br/>- M : Manager 단독 설치<br/>- S : Server 단독 설치<br/>- A : Agent 단독 설치                                                                                                         |
| ON_BOOT            | yes                                    | 설치 & 구동 관련 옵션<br/> -yes : 설치 후 모두 기동<br/>- manual : 설치 후 기동은 Pod에 접속하여 직접 수행(초기 설치 시 사용)<br/>- manager : 설치 후 매니저만 기동(초기 설치 시 사용)<br/>- no (기타) : 설치 및 기동 모두 하지 않음 <br/>- exceptagent : 에이전트 제외한 매니저, 서버 기동    |
| MANAGER_WEB_PORT   | 7065                                   | J-Jobs 매니저 web(was) port                                                                                                                                                                                   |
| SERVER_WEB_PORT    | 7075                                   | J-Jobs 서버 web(was) port                                                                                                                                                                                    |
| SERVER_TCP_PORT    | 17075                                  | J-Job 서버와 에이전트 간의 통신을 위한 TCP Port                                                                                                                                                                          |
| DB_TYPE            | postgres                               | J-Jobs의 Meta DB 유형<br/>-postgres<br/>-oracle<br/>-mysql<br/>mariadb                                                                                                                                        |
| JDBC_URL           | jdbc:postgresql://127.0.0.1:7432/jjobs | DB 접속 JDBC URL 설정                                                                                                                                                                                          |
| DB_USER            | jjobs                                  | 	JDBC URL로 DB에 접속할 때 사용자명                                                                                                                                                                                  |
| DB_PASSWD	         | jjobs1234                              | JDBC URL로 DB에 접속할 때 패스워드                                                                                                                                                                                   |
| JJOB_SERVICE_NAME  | jjobs.default.svc.cluster.local        | 전체 설치/서버 설치 시 사용<br/>(start_server.sh 에서 JJOB_SERVER_IP 환경 변수로 "StatefulSet으로 생성된 pod의 hostname + JJOB_SERVICE_NAME"를 추가함)<br/><br/>(예시)<br/>export JJOB_SERVER_IP=jjobs-0.jjobs.default.svc.cluster.local |
| AGENT_GROUP_ID     | 0                                      | 	에이전트 그룹 ID 설정                                                                                                                                                                                             |
| LOGS_BASE	         | /logs001/jjobs                         | 	(에이전트 설정) 로그 경로                       |
| LOG_KEEP_DATE	     | 5                                      | 	(에이전트 설정) 로그 유지 일수                                                                                                                                                                                        |
| LOG_DELETE_YN      | 	Y                                     | (에이전트 설정) 로그 백업 옵션<br/>-Y : 삭제<br/>-N : 백업<br/>-Z : 백업/압축                                                                                                                                                  |
| JJOBS_SERVER_IP    | 	127.0.0.1                             | 에이전트가 서버에 접근하기 위한 서버의 서비스 IP<br/><br/>(예시)<br/>start_agent.sh에 들어가는 서버 IP(JJOBS_SERVER_IP)는 서비스 명을 사용해도 됨 → jjobs.default.svc.cluster.local


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
      terminationGracePeriodSeconds: 180
      containers:
        - name: jjobs
          image: devonlab/jjobs
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
              value: "Z"
            - name: ON_BOOT
              value: "exceptagent"
            - name: INSTALL_KIND
              value: "F"
            - name: AGENT_GROUP_ID
              value: "1"
            - name: JJOB_SERVICE_NAME
              value: "jjobs.default.svc.cluster.local"
            - name: USE_REDIS_SESSION_CLUSTERING
              value: "N"
            - name: REDIS_NAMESPACE
              value: <input_your_redis_namespace>
            - name: REDIS_HOST
              value: <input_your_redis_host>
            - name: REDIS_PORT
              value: "6379"
            - name: USE_DB_ENCRYPT
              value: "Y"
            - name: ENCRYPTED_DB_USER
              value: <input_your_db_encrypted_username>
            - name: ENCRYPTED_DB_PASSWD
              value: <input_your_db_encrypted_password>
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
- ConfigMap의 `ON_BOOT` 설정을 yes로 수정하여 반영
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
      terminationGracePeriodSeconds: 300
      containers:
      - name: jjobs-agent-container
        image: devonlab/jjobs:keycloak
        lifecycle:
          preStop:
            exec:
              command: ["/bin/sh","-c","kubectl delete pods $HOSTNAME --force"]
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
            - /engn001/jjobs/agent/healthcheck.sh
          initialDelaySeconds: 300
          periodSeconds: 5
          timeoutSeconds: 10
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



