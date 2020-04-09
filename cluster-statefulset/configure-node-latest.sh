#Tested for CE 6 and 6.5 version
set -m

/entrypoint.sh couchbase-server &

sleep 15

# Setup index and memory quota
curl -v -X POST http://127.0.0.1:8091/pools/default -d memoryQuota=300 -d indexMemoryQuota=300

# Setup services
curl -v http://127.0.0.1:8091/node/controller/setupServices -d services=kv%2Cn1ql%2Cindex

# Setup credentials
curl -v http://127.0.0.1:8091/settings/web -d port=8091 -d username=Administrator -d password=password

# Setup Memory Optimized Indexes
curl -i -u Administrator:password -X POST http://127.0.0.1:8091/settings/indexes -d 'storageMode=memory_optimized'

# Load travel-sample bucket
curl -v -u Administrator:password -X POST http://127.0.0.1:8091/sampleBuckets/install -d '["travel-sample"]'

IP=`hostname -i`

if [[ "$HOSTNAME" == *-0 ]]; then
  TYPE="MASTER"
else
  TYPE="WORKER"
fi

echo "Type: $TYPE"

_addServer(){
            couchbase-cli server-add -c $COUCHBASE_MASTER:8091 \
            --username Administrator \
            --password password \
            --server-add="http://$IP:8091" \
            --server-add-username Administrator \
            --server-add-password password \
            --services data,query,index;
}

if [ "$TYPE" = "WORKER" ]; then
  sleep 15


  echo "Auto Rebalance: $AUTO_REBALANCE"
  if [ "$AUTO_REBALANCE" = "true" ]; then

        _addServer;
        couchbase-cli rebalance -c $COUCHBASE_MASTER:8091 \
            --username Administrator \
            --password password;

  else
        _addServer;
  fi;
fi;

fg 1
