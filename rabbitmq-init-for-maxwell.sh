#!/bin/bash

/usr/local/bin/wait-for-it.sh localhost:5672
sleep 2
echo "[maxwell] create user: rabbitmq_user=admin, rabbitmq_pass=admin vhost=/maxwell"

rabbitmqctl add_vhost /maxwell
rabbitmqctl add_user admin admin
rabbitmqctl set_user_tags admin administrator
rabbitmqctl set_permissions -p /maxwell admin '.*' '.*' '.*'
# rabbitmqadmin declare vhost name=/maxwell

echo "[maxwell] declare exchange=maxwell.binlog queue=maxwell_binlog binding_key=#"
rabbitmqadmin_args=" --vhost=/maxwell --username=admin --password=admin "
rabbitmqadmin declare exchange $rabbitmqadmin_args name=maxwell.binlog type=topic auto_delete=false durable=true
rabbitmqadmin declare queue $rabbitmqadmin_args name=maxwell_binlog durable=true
rabbitmqadmin declare binding $rabbitmqadmin_args source="maxwell.binlog" destination_type="queue" destination="maxwell_binlog" routing_key="#"

# use lazy queue to save memory
rabbitmqadmin declare policy $rabbitmqadmin_args name=Lazy pattern="^" definition='{"queue-mode":"lazy"}' apply-to='queues'

rabbitmqadmin list vhosts
# rabbitmqadmin list users
# rabbitmqadmin list queues
rabbitmqadmin list queues $rabbitmqadmin_args
rabbitmqadmin list policies $rabbitmqadmin_args
rabbitmqadmin list bindings $rabbitmqadmin_args
