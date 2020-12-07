#!/bin/bash


COUCHBASE_MASTER=$MASTER_NODE.$SERVICE_NAME;
POD_DNS_NAME="$HOSTNAME.$SERVICE_NAME.$NAMESPACE.svc.cluster.local";

_rebalance(){
    echo "Rebalancing from $COUCHBASE_MASTER:8091";
     couchbase-cli rebalance -c $COUCHBASE_MASTER:8091 \
            --username $ADMIN_USER \
            --password $ADMIN_PASSWORD;
    
    echo "ready" >/node_status
}

_addServer(){

    echo "Adding node to $COUCHBASE_MASTER:8091";
    couchbase-cli server-add -c $COUCHBASE_MASTER:8091 --username $ADMIN_USER --password $ADMIN_PASSWORD \
    --server-add "$POD_DNS_NAME:8091" --server-add-username $ADMIN_USER --server-add-password $ADMIN_PASSWORD \
    --services data,query,index,fts;
    if [ "$AUTO_REBALANCE" = "true" ]; then
            _rebalance;
      fi; 
}

_addServer;
