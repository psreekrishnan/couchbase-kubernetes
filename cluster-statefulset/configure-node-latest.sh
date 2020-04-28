#!/bin/bash
#Tested for CE 6 and 6.5 version
set -m

/bin/bash /entrypoint.sh couchbase-server  &
sleep 15

[ -z "$USER_NAME" ] && USER_NAME=admin
[ -z "$PASSWORD" ] && PASSWORD=password
[ -z "$MEMORY_QUOTA" ] && MEMORY_QUOTA=300
[ -z "$INDEX_MEMORY_QUOTA" ] && INDEX_MEMORY_QUOTA=300
[ -z "$INIT_BUCKET" ] && INIT_BUCKET=travel


_dbStatus(){
while true
do
  STATUS=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8091)
  if [ $STATUS -eq 301 ]; then
    echo "Got 301! Db is up and running!"
    sleep 2;
    break
  else
    echo "Got $STATUS :( Not done yet..."
  fi
  sleep 5;
done
}

_dbStatus;

# Setup index and memory quota
curl -v -X POST http://127.0.0.1:8091/pools/default -d memoryQuota=$MEMORY_QUOTA -d indexMemoryQuota=$INDEX_MEMORY_QUOTA 

# Setup services
curl -v http://127.0.0.1:8091/node/controller/setupServices -d services=kv%2Cn1ql%2Cindex 

# Setup credentials
curl -v http://127.0.0.1:8091/settings/web -d port=8091 -d username=$USER_NAME -d password=$PASSWORD 

# Setup Memory Optimized Indexes
curl -i -u $USER_NAME:$PASSWORD -X POST http://127.0.0.1:8091/settings/indexes -d 'storageMode=memory_optimized' 

IP=`hostname -i`

if [[ "$HOSTNAME" == *-0 ]]; then
  TYPE="MASTER"
else
  TYPE="WORKER"
fi


_addServer(){
            couchbase-cli server-add -c $COUCHBASE_MASTER:8091 \
            --username $USER_NAME \
            --password $PASSWORD \
            --server-add="http://$IP:8091" \
            --server-add-username $USER_NAME \
            --server-add-password $PASSWORD \
            --services data,query,index;
}

if [ "$TYPE" = "WORKER" ]; then
  sleep 15


  echo "Auto Rebalance: $AUTO_REBALANCE"
  if [ "$AUTO_REBALANCE" = "true" ]; then
        _addServer;
        couchbase-cli rebalance -c $COUCHBASE_MASTER:8091 \
            --username $USER_NAME \
            --password $PASSWORD;

  else
        echo "add server"
        _addServer;
  fi;
  else
      # Create an initial bucket
      curl -v -X POST -u $USER_NAME:$PASSWORD  http://127.0.0.1:8091/pools/default/buckets -d ramQuotaMB=100 -d name=$INIT_BUCKET 
fi;

fg 1
