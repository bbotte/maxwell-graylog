#!/bin/bash

# run in background and wait for rabbitmq-server up, then initialize maxwell vhost/exchange/queue/bind for graylog to comsume
bash /usr/local/bin/rabbitmq-init-for-maxwell.sh &

# run official rabbitmq entrypoint
docker-entrypoint.sh $@