#!/bin/sh

echo "properties,log setting"
HOSTNAME=`hostname`

if [ "$INSTALL_KIND" == "A" ] || [ "$INSTALL_KIND" == "F" ] ; then
        echo "agent log setting - resource.properties"

        sed -i 's@log.file.base_path=.*$@log.file.base_path='"$LOGS_BASE/agent/\$AGENT_NAME/logs"'@g' $JJOBS_BASE/agent/app/META-INF/resource.properties
        sed -i 's@log.file.keep.backup_path=.*$@log.file.keep.backup_path='"$LOGS_BASE/agent/\$AGENT_NAME/backup"'@g' $JJOBS_BASE/agent/app/META-INF/resource.properties
        sed -i 's@log.file.keep.date_cnt=.*$@log.file.keep.date_cnt='"$LOG_KEEP_DATE"'@g' $JJOBS_BASE/agent/app/META-INF/resource.properties
        sed -i 's@log.file.keep.backup_delete_yn=.*$@log.file.keep.backup_delete_yn='"$LOG_DELETE_YN"'@g' $JJOBS_BASE/agent/app/META-INF/resource.properties

        mkdir -p $JJOBS_BASE/agent/.bin
fi

if [ "$INSTALL_KIND" == "S" ] || [ "$INSTALL_KIND" == "F" ] ; then
        echo "unwar..."
        unzip $JJOBS_BASE/server/webapps/jjob-server.war -d $JJOBS_BASE/server/webapps/jjob-server

        echo "server log setting"
        mkdir -p $LOGS_BASE
        sed -i "52d" $JJOBS_BASE/server/webapps/jjob-server/WEB-INF/classes/properties/log4j2.xml
        sed -i "7d" $JJOBS_BASE/server/webapps/jjob-server/WEB-INF/classes/properties/log4j2.xml
        sed -i '/<AppenderRef ref="console/d' $JJOBS_BASE/server/webapps/jjob-server/WEB-INF/classes/properties/log4j2.xml
        sed -i 's@<!--@@g' $JJOBS_BASE/server/webapps/jjob-server/WEB-INF/classes/properties/log4j2.xml
        sed -i 's@-->@@g' $JJOBS_BASE/server/webapps/jjob-server/WEB-INF/classes/properties/log4j2.xml
        sed -i 's@/logs001/jjobs/server@'"$LOGS_BASE"'/server/'"$HOSTNAME"'@g' $JJOBS_BASE/server/webapps/jjob-server/WEB-INF/classes/properties/log4j2.xml

        if [ "$USE_DB_ENCRYPT" == "Y" ] && [ -n "$ENCRYPTED_DB_USER" ] && [ -n "$ENCRYPTED_DB_PASSWD" ] ; then
                echo "meta db encryption setting"
                sed -i 's/org\.apache\.commons\.dbcp2\.BasicDataSource/jjob.common.api.common.datasource.SecureDataSource/g' $JJOBS_BASE/server/webapps/jjob-server/WEB-INF/classes/spring/context-datasource.xml
                sed -i '18d'  $JJOBS_BASE/server/webapps/jjob-server/WEB-INF/classes/spring/context-datasource.xml
                sed -i '18i    <property name="username" value='\"$ENCRYPTED_DB_USER\"'/>' $JJOBS_BASE/server/webapps/jjob-server/WEB-INF/classes/spring/context-datasource.xml
                sed -i '19d'  $JJOBS_BASE/server/webapps/jjob-server/WEB-INF/classes/spring/context-datasource.xml
                sed -i '19i    <property name="password" value='\"$ENCRYPTED_DB_PASSWD\"'/>' $JJOBS_BASE/server/webapps/jjob-server/WEB-INF/classes/spring/context-datasource.xml
        fi

        if [ -n "$JDBC_PARAMETERS" ]; then
                echo "add the jdbc url connection parameters.."
                sed -i '17s/\"\/>/'$JDBC_PARAMETERS'\"\/>/' $JJOBS_BASE/server/webapps/jjob-server/WEB-INF/classes/spring/context-datasource.xml
        fi

        echo "edit start_server.sh"

        str=$HOSTNAME
        id=${str:(-1):1}
        INT=$((id))
        SERVER_ID=$(($INT + 1))
        sed -i 's@export JJOB_SERVER_ID=.*$@export JJOB_SERVER_ID=1-'"$SERVER_ID"'@g' $JJOBS_BASE/start_server.sh
        sed -i 's@tail -f /engn001/jjobs/server/logs/catalina.out@if [ ! -e $LOGS_BASE/server/$HOSTNAME/server.log ]; then\
    sleep 10\
fi\
if [ ! -e $LOGS_BASE/server/$HOSTNAME/server.log ]; then\
    sleep 10\
fi\
tail -f $LOGS_BASE/server/$HOSTNAME/server.log@g' $JJOBS_BASE/start_server.sh

        if [ -z "$JJOB_SERVICE_NAME" ]; then
          echo "skip to set the JJOB_SERVER_IP"
        else
          sed -i '3iexport JJOB_SERVER_IP='"$HOSTNAME"'.'"$JJOB_SERVICE_NAME"'' $JJOBS_BASE/start_server.sh
        fi
fi

echo "setting for java security.."
if [ -z "$NETWORKADDRESS_CACHE_TTL" ]; then
  export NETWORKADDRESS_CACHE_TTL=1
fi
if [ -z "$NETWORKADDRESS_CACHE_NEGATIVE_TTL" ]; then
  export NETWORKADDRESS_CACHE_NEGATIVE_TTL=3
fi
sed -i '313d' $JJOBS_BASE/openjdk-8u462-b08-linux-x64/jre/lib/security/java.security
sed -i '313inetworkaddress.cache.ttl='"$NETWORKADDRESS_CACHE_TTL"'' $JJOBS_BASE/openjdk-8u462-b08-linux-x64/jre/lib/security/java.security
sed -i '328d' $JJOBS_BASE/openjdk-8u462-b08-linux-x64/jre/lib/security/java.security
sed -i '328inetworkaddress.cache.negative.ttl='"$NETWORKADDRESS_CACHE_NEGATIVE_TTL"'' $JJOBS_BASE/openjdk-8u462-b08-linux-x64/jre/lib/security/java.security

if [ "$INSTALL_KIND" == "M" ] || [ "$INSTALL_KIND" == "F" ] ; then
        echo "unwar..."
        unzip $JJOBS_BASE/manager/webapps/jjob-manager.war -d $JJOBS_BASE/manager/webapps/jjob-manager

        echo "manager log setting"
        sed -i "26d" $JJOBS_BASE/manager/webapps/jjob-manager/WEB-INF/classes/properties/log4j2.xml
        sed -i "7d" $JJOBS_BASE/manager/webapps/jjob-manager/WEB-INF/classes/properties/log4j2.xml
        sed -i '/<AppenderRef ref="console/d' $JJOBS_BASE/manager/webapps/jjob-manager/WEB-INF/classes/properties/log4j2.xml
        sed -i 's@<!--@@g' $JJOBS_BASE/manager/webapps/jjob-manager/WEB-INF/classes/properties/log4j2.xml
        sed -i 's@-->@@g' $JJOBS_BASE/manager/webapps/jjob-manager/WEB-INF/classes/properties/log4j2.xml
        sed -i 's@/logs001/jjobs/manager@'"$LOGS_BASE"'/manager/'"$HOSTNAME"'@g' $JJOBS_BASE/manager/webapps/jjob-manager/WEB-INF/classes/properties/log4j2.xml

        if [ "$USE_REDIS_SESSION_CLUSTERING" == "Y" ] && [ -n "$REDIS_NAMESPACE" ] && [ -n "$REDIS_HOST" ] && [ -n "$REDIS_PORT" ]; then
                echo "manager xml setting for redis"
                cp $WORKING_DIR/web_redis.xml $JJOBS_BASE/manager/webapps/jjob-manager/WEB-INF/web.xml
                cp $WORKING_DIR/context-manager_redis.xml $JJOBS_BASE/manager/webapps/jjob-manager/WEB-INF/classes/spring/context-manager.xml
                sed -i 's/$REDIS_NAMESPACE/'"$REDIS_NAMESPACE"'/g' $JJOBS_BASE/manager/webapps/jjob-manager/WEB-INF/classes/spring/context-manager.xml
                sed -i 's/$REDIS_HOST/'"$REDIS_HOST"'/g' $JJOBS_BASE/manager/webapps/jjob-manager/WEB-INF/classes/spring/context-manager.xml
                sed -i 's/$REDIS_PORT/'"$REDIS_PORT"'/g' $JJOBS_BASE/manager/webapps/jjob-manager/WEB-INF/classes/spring/context-manager.xml
        fi

        if [ "$USE_DB_ENCRYPT" == "Y" ] && [ -n "$ENCRYPTED_DB_USER" ] && [ -n "$ENCRYPTED_DB_PASSWD" ] ; then
                echo "meta db encryption setting"
                sed -i 's/org\.apache\.commons\.dbcp2\.BasicDataSource/jjob.common.api.common.datasource.SecureDataSource/g' $JJOBS_BASE/manager/webapps/jjob-manager/WEB-INF/classes/spring/context-datasource.xml
                sed -i '15d'  $JJOBS_BASE/manager/webapps/jjob-manager/WEB-INF/classes/spring/context-datasource.xml
                sed -i '15i    <property name="username" value='\"$ENCRYPTED_DB_USER\"'/>' $JJOBS_BASE/manager/webapps/jjob-manager/WEB-INF/classes/spring/context-datasource.xml
                sed -i '16d'  $JJOBS_BASE/manager/webapps/jjob-manager/WEB-INF/classes/spring/context-datasource.xml
                sed -i '16i    <property name="password" value='\"$ENCRYPTED_DB_PASSWD\"'/>' $JJOBS_BASE/manager/webapps/jjob-manager/WEB-INF/classes/spring/context-datasource.xml

                DECRYPTED_DB_USER=`$JJOBS_BASE/encrypter.sh d $ENCRYPTED_DB_USER`
                DECRYPTED_DB_PASSWD=`$JJOBS_BASE/encrypter.sh d $ENCRYPTED_DB_PASSWD`
                sed -i '29d' $JJOBS_BASE/manager/conf/context.xml
                sed -i '29i\                         username='\"$DECRYPTED_DB_USER\"' password='\"$DECRYPTED_DB_PASSWD\"' driverClassName="org.postgresql.Driver"' $JJOBS_BASE/manager/conf/context.xml

        fi

        if [ -n "$JDBC_PARAMETERS" ]; then
                echo "add the jdbc url connection parameters.."
                sed -i '14s/\"\/>/'$JDBC_PARAMETERS'\"\/>/' $JJOBS_BASE/manager/webapps/jjob-manager/WEB-INF/classes/spring/context-datasource.xml
        fi
        
	echo "edit start_manager.sh"
	sed -i "5d" $JJOBS_BASE/start_manager.sh

        if [ -n "$SSO_KEYCLOAK_ISSUER_URI" ]; then
                sed -i '3iexport SSO_KEYCLOAK_ISSUER_URI='$SSO_KEYCLOAK_ISSUER_URI'' start_manager.sh
        fi
fi

if [ "$WGET_URL" ] && [ "$WGET_FOLDER_PATH" ] && [ "$WGET_FILE_NAME" ] ; then
        mkdir -p $WGET_FOLDER_PATH
        wget $WGET_URL -O $WGET_FOLDER_PATH/$WGET_FILE_NAME

        cd $WGET_FOLDER_PATH

        if [[ "$WGET_FILE_NAME" == *.tar.gz ]]; then
                echo "unarchive .tar.gz File :: $WGET_FILE_NAME"
                tar -zxvf $WGET_FOLDER_PATH/$WGET_FILE_NAME
                echo "unarchive successfully completed."
                echo "Delete Archive File :: $WGET_FILE_NAME"
                rm $WGET_FOLDER_PATH/$WGET_FILE_NAME
        elif [[ "$WGET_FILE_NAME" == *.tar ]]; then
                echo "unarchive .tar File :: $WGET_FILE_NAME"
                tar -xvf $WGET_FOLDER_PATH/$WGET_FILE_NAME
                echo "unarchive successfully completed."
                echo "Delete Archive File :: $WGET_FILE_NAME"
                rm $WGET_FOLDER_PATH/$WGET_FILE_NAME
        elif [[ "$WGET_FILE_NAME" == *.zip ]]; then
                echo "unarchive .zip File :: $WGET_FILE_NAME"
                unzip $WGET_FOLDER_PATH/$WGET_FILE_NAME
                echo "unarchive successfully completed."
                echo "Delete Archive File :: $WGET_FILE_NAME"
                rm $WGET_FOLDER_PATH/$WGET_FILE_NAME
        fi
fi
