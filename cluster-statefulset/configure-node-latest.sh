#!/bin/bash
#Tested for CE 6 version
#----------------------------------------------------------------
#----------------------------------------------------------------
# Bash script for Couchbase cluster initialization
# Work only with K8's
#----------------------------------------------------------------
#----------------------------------------------------------------
#Following functionalities can be achieved
#
# 1. Set Admin credentials
# 2. Set Read only admin credentials
# 3. Create mutliple buckets (support only two for now.)
# 4. Set Cluster Memory Quota & Cluster Index Quota
# 5. Set Memory Quota for buckets
# 6. Set hostname for the nodes
# 7. Initialize and rebalance the node
#----------------------------------------------------------------
COUCHBASE_HOME="/opt/couchbase/var";
COUCHBASE_MASTER=$MASTER_NODE.$SERVICE_NAME;
POD_DNS_NAME="$HOSTNAME.$SERVICE_NAME.$NAMESPACE.svc.cluster.local";

DATE_FORMAT=$(date +"%d_%m_%Y")
LOG_FILE="${COUCHBASE_HOME}/node_initializer_${DATE_FORMAT}.log";


IP=`hostname -i`

[ -z "$ADMIN_USER" ] && ADMIN_USER=admin
[ -z "$ADMIN_PASSWORD" ] && ADMIN_PASSWORD=password
[ -z "$RO_ADMIN_USER" ] && RO_ADMIN_USER=admin_ro
[ -z "$RO_ADMIN_PASSWORD" ] && RO_ADMIN_PASSWORD=password

[ -z "$RW_USER" ] && RW_USER=usr001
[ -z "$RW_USER_PASSWORD" ] && RW_USER_PASSWORD=usr001

[ -z "$BUCKET_1_MEMORY_QUOTA" ] && BUCKET_1_MEMORY_QUOTA=300
[ -z "$BUCKET_2_MEMORY_QUOTA" ] && BUCKET_2_MEMORY_QUOTA=300

[ -z "$BUCKET_1" ] && BUCKET_1=bucket1
[ -z "$BUCKET_2" ] && BUCKET_2=bucket2

[ -z "$CLUSTER_MEMORY_QUOTA" ] && CLUSTER_MEMORY_QUOTA=300
[ -z "$CLUSTER_MEMORY_INDEX_QUOTA" ] && CLUSTER_MEMORY_INDEX_QUOTA=300


_dbStatus(){
while true
do
  STATUS=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8091)
  if [ $STATUS -eq 301 ]; then
    echo "Got 301! Db is up and running!" 2>>${LOG_FILE}
    sleep 2;
    break
  else
    echo "Got $STATUS :( Not done yet..." 2>>${LOG_FILE}
  fi
  sleep 10;
done
}

_cacheNodeName(){
    #Set node name to a file
    echo "$POD_DNS_NAME" >$COUCHBASE_HOME/$POD_DNS_NAME
}

_rebalance(){
    echo "Rebalancing from $COUCHBASE_MASTER:8091" >> ${LOG_FILE}
     couchbase-cli rebalance -c $COUCHBASE_MASTER:8091 \
            --username $ADMIN_USER \
            --password $ADMIN_PASSWORD --no-progress-bar >>${LOG_FILE} 2>>${LOG_FILE};
}

_addServer(){

    echo "Adding node to $COUCHBASE_MASTER:8091" >> ${LOG_FILE}
    couchbase-cli server-add -c $COUCHBASE_MASTER:8091 --username $ADMIN_USER --password $ADMIN_PASSWORD \
    --server-add "$POD_DNS_NAME:8091" --server-add-username $ADMIN_USER --server-add-password $ADMIN_PASSWORD \
    --services data,query,index,fts >>${LOG_FILE} 2>>${LOG_FILE};
    
    if [ "$AUTO_REBALANCE" = "true" ]; then
            _rebalance;
      fi; 
}

_initializeMasterNode(){

  echo "Cluster initialization started">>${LOG_FILE}
  couchbase-cli cluster-init -c 127.0.0.1:8091 --cluster-username Administrator \
  --cluster-password password --services data,index,query,fts \
  --cluster-ramsize $CLUSTER_MEMORY_QUOTA  --cluster-index-ramsize $CLUSTER_MEMORY_INDEX_QUOTA \
  --index-storage-setting default >>${LOG_FILE} 2>>${LOG_FILE}

}

_manageCredentials(){
  # Setup credentials
  echo "Setting up credentials">>${LOG_FILE}
  curl -v -u Administrator:password  http://127.0.0.1:8091/settings/web -d port=8091 \
  -d username=$ADMIN_USER -d password=$ADMIN_PASSWORD >>${LOG_FILE} 2>>${LOG_FILE};

  if [ "$TYPE" = "MASTER" ]; then
      # Create read only admin user
      echo "Create read only admin user : $RO_ADMIN_USER">>${LOG_FILE}
      curl -v -X  PUT -u $ADMIN_USER:$ADMIN_PASSWORD http://127.0.0.1:8091/settings/rbac/users/local/$RO_ADMIN_USER \
            -d password=$RO_ADMIN_PASSWORD -d roles=ro_admin >>${LOG_FILE} 2>>${LOG_FILE};

      echo "Create read-write user : $RW_USER">>${LOG_FILE}
       curl -v -X  PUT -u $ADMIN_USER:$ADMIN_PASSWORD http://127.0.0.1:8091/settings/rbac/users/local/$RW_USER \
            -d password=$RW_USER_PASSWORD -d roles=ro_admin,bucket_full_access[*]   >>${LOG_FILE} 2>>${LOG_FILE};   

  fi;
}

_setNodeName(){
  # Initialize the node
  echo "Initialize the node with the hostname $POD_DNS_NAME" >>${LOG_FILE}
  couchbase-cli node-init -c 127.0.0.1:8091 -u $ADMIN_USER -p $ADMIN_PASSWORD --node-init-hostname $POD_DNS_NAME >>${LOG_FILE} 2>>${LOG_FILE};
}

_createBucket(){
  BUCKET_NAME=$1;
  BUCKET_MEMORY_QUOTA=$2;

          couchbase-cli bucket-create -c 127.0.0.1:8091 --username $ADMIN_USER \
    --password $ADMIN_PASSWORD --bucket $BUCKET_NAME --bucket-type couchbase \
    --bucket-ramsize $BUCKET_MEMORY_QUOTA >>${LOG_FILE} 2>>${LOG_FILE};

}


_initializeWorkerNode(){
  # Setup index and memory quota
  echo "Setting up index and memory quota" >>${LOG_FILE}
  curl -v -X  POST http://127.0.0.1:8091/pools/default -d memoryQuota=$CLUSTER_MEMORY_QUOTA -d indexMemoryQuota=$CLUSTER_MEMORY_INDEX_QUOTA >>${LOG_FILE}  2>>${LOG_FILE};

  # Setup services
  echo "Setting up services" >>${LOG_FILE}
  curl -v http://127.0.0.1:8091/node/controller/setupServices -d services=kv%2Cn1ql%2Cindex%2Cfts >>${LOG_FILE} 2>>${LOG_FILE};

}


if [[ "$HOSTNAME" == *-0 ]]; then
  TYPE="MASTER"
    #Check Node is already initialized or not.
    [ -f "$COUCHBASE_HOME/$POD_DNS_NAME" ] && { echo "Node $POD_DNS_NAME already initialized" >>${LOG_FILE} 2>>${LOG_FILE}; exit 0; }
else
  TYPE="WORKER"
    #Check Node is already initialized or not.
    [ -f "$COUCHBASE_HOME/$POD_DNS_NAME" ] && { echo "Node $POD_DNS_NAME already initialized" >>${LOG_FILE} 2>>${LOG_FILE}; _rebalance; exit 0; }

fi

_dbStatus;



if [ "$TYPE" = "MASTER" ]; then


_initializeMasterNode;
_manageCredentials;
_setNodeName;

  echo "Creating bucket $BUCKET_1" >>${LOG_FILE}
    _createBucket $BUCKET_1 $BUCKET_1_MEMORY_QUOTA;
  echo "Creating bucket $BUCKET_2" >>${LOG_FILE}
    _createBucket $BUCKET_2 $BUCKET_2_MEMORY_QUOTA;

  echo "ready" >/node_status
else

#    _initializeWorkerNode;
    _manageCredentials;
    _setNodeName;

fi;

_cacheNodeName;

exit 0;


