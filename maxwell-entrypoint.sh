#!/bin/bash

chown -R 999:999 /var/lib/mysql
sleep 10
lockfile_bin=/var/lib/mysql/initialized.lock
touch $lockfile_bin  # make sure it exists

# mysql_binlogsvr need to be ready first
work_mode=`cat $lockfile_bin`
while [ "$work_mode" = "0" -o "$work_mode"x = ""x ]; do
  # else $work_mode=1 or 2
  echo "waiting for mysql_binlogsvr prepared"
  sleep 20
  work_mode=`cat $lockfile_bin`
done

echo "binlog download is done, wait more seconds for mysql_binlogsvr ready" && sleep 40  # should be ready when first mysql initialize failed
ping mysql_binlogsvr -c 2
mysql_login=""
if [ $work_mode -eq 1 ];then
  work_mode=1
  echo "warning: work_mode=1 > MYSQL_HOST=${MYSQL_HOST}, MYSQL_USER=${MYSQL_USER}, MYSQL_PASSWORD=**** is used as binlog and schema svr"
  if [ -z "$MYSQL_USER" -o -z "$MYSQL_PASSWORD" -o -z "$MYSQL_HOST" ]; then
    echo "MYSQL_HOST, MYSQL_USER, MYSQL_PASSWORD must be given! (exit)"
    exit 1
  fi
  mysql_login="--host=$MYSQL_HOST --user=$MYSQL_USER --password=$MYSQL_PASSWORD"
  maxwell_options="$mysql_login --schema_database=monitor "
  # get binlog file:postion from MYSQL_HOST. Because stored schema info may already exists in `monitor` db, we can't leave it empty
  init_binlog_file=$(mysql ${mysql_login} -s -e 'show binary logs'|tail -1|cut -f1)
else
  # 0 or 2
  work_mode=0
  echo "warning: work_mode=0 > using default root:stron****d@127.0.0.1 as binlogsvr "
  mysql_login="--host=mysql_binlogsvr --user=root --password=strongpassword"
  maxwell_options="$mysql_login --schema_database=monitor "
  # init_binlog_file=$(head -1 /var/lib/mysql/mysql-bin.index | cut -d/ -f2)
  init_binlog_file=$(mysql ${mysql_login} -s -e 'show binary logs'|head -1|cut -f1)

  if [ -n "$MYSQL_HOST_GIT" ];then
    echo "    create table schema from git repoisitory"
    # create table schema for binlogsvr to construct data
    bash ./maxwell-retrive-tablemeta.sh
    # if set MAXWELL_SCHEMA_HOST, use MYSQL_HOST as schema_host
  elif [ -n "$MYSQL_HOST" ];then
    echo "    using ${MYSQL_USER}:${MYSQL_PASSWORD}@${MYSQL_HOST} as schema svr"
    maxwell_options+="--schema_host=$MYSQL_HOST --schema_user=$MYSQL_USER --schema_password=$MYSQL_PASSWORD "
  else
    echo "please set MYSQL_HOST_GIT or MYSQL_HOST to let maxwell know where to get table structure(exit 1)"
    exit 1
  fi
fi

# make sure mysql_binlogsvr is accessable
if [ "$init_binlog_file" = "" ]; then
  echo "wrong init_binlog_file, maybe binlogsvr cannot be connected(exit)"
  exit 1
fi 

################ lock: init_postion ################
# in case restart maxwell container
lockfile=/var/lib/mysql/initialized_maxwell.lock
if [ ! -f $lockfile ]; then
  if [ -z "$init_position" ]; then
    export init_position="${init_binlog_file}:4:0"
  fi
  echo "maxwell --init_position is set to $init_position"
  maxwell_options+="--init_position=$init_position "
  # touch $lockfile  # later
else
  echo "maxwell do not need init_positon because it has been started before"
fi

################  producer (required and default arguments) ################
# producer file
# output_file=maxwell_binlog_stream.json  # , OUT_FILTER outdated, use `include_column_values` instead
function producer_file() {
  if [ -z "$OUT_FILTER" ]; then
    export output_file=${output_file}.log
    touch $output_file && echo
    echo "info: OUT_FILTER is not set, maxwell binlog json stream is writen to ${output_file}"
  else
    touch $output_file
    echo "warning: OUT_FILTER is set: grep -E '$OUT_FILTER' , maxwell binlog json stream is writen to ${output_file}"
    tail -f $output_file |grep -E '${OUT_FILTER}' > $output_file.log &
  fi
}

# producer rabbitmq
function producer_rabbitmq() {
  if [ -n "$rabbitmq_exchange_type" ];then
    maxwell_options+="--rabbitmq_exchange_type=$rabbitmq_exchange_type "
  else
    maxwell_options+="--rabbitmq_exchange_type=topic "
  fi
  if [ -n "$rabbitmq_virtual_host" ];then
    maxwell_options+="--rabbitmq_virtual_host=$rabbitmq_virtual_host "
  else
    maxwell_options+="--rabbitmq_virtual_host=/ "
  fi
  if [ -n "$rabbitmq_user" -a -n "$rabbitmq_pass" ];then
    maxwell_options+="--rabbitmq_user=$rabbitmq_user --rabbitmq_pass=$rabbitmq_pass "
  else
    maxwell_options+="--rabbitmq_user=guest --rabbitmq_pass=guest "
    # only for vhost / 
  fi
}

# producer kafka
function producer_kafka() {
  if [ -n "$kafka_producer_partition_by" ];then
    maxwell_options+="--producer_partition_by=$kafka_producer_partition_by "
    # else default: database
    # you can set other maxwell options in MAXWELL_OPTS
  fi
}
########################################
# producer base config
if [ "$producer" = "file" ];then
  producer_file
  maxwell_options+=" --producer=file --output_file=$output_file "
elif [ "$producer" = "rabbitmq" -a -n "$rabbitmq_host" ];then
  maxwell_options+=" --producer=rabbitmq --rabbitmq_host=$rabbitmq_host "
  maxwell_options+="--rabbitmq_exchange=maxwell.binlog --rabbitmq_exchange_durable=true --rabbitmq_exchange_autodelete=false --rabbitmq_routing_key_template=%db%.%table% "
  producer_rabbitmq
elif [ "$producer" = "kafka" -a -n "$kafka_server" ]; then
  maxwell_options+=" --producer=kafka --kafka.bootstrap.servers=$kafka_server "
  maxwell_options+="--kafka_topic=maxwell "
  producer_kafka
else
  echo "please give the right --producer=file/rabbitmq/kafka --output_file=$output_file / --rabbitmq_host=$rabbitmq_host / --kafka_server=$kafka_server"
  exit 1
fi

################ filter ################
# mysql_cmd_opts='-u$MYSQL_USER -p$MYSQL_PASS --default-character-set=utf8mb4'
# mysql_filter=''
if [ -n "$include_tables" ];then
  maxwell_options+="--include_tables=$include_tables "
  # mysql_filter='--tables ${include_tables//,/ }'
fi
if [ -n "$include_dbs" ];then
  maxwell_options+="--include_dbs=$include_dbs "
fi
if [ ! -z "$include_column_values" ];then
  maxwell_options+="--include_column_values=$include_column_values "
fi
if [ -n "$exclude_columns" ];then
  maxwell_options+="--exclude_columns=$exclude_columns "
fi
# you can set other maxwell filter options in MAXWELL_OPTS

# other options, like --port=3307
if [ -n "$MAXWELL_OPTS" ]; then
  maxwell_options+=" $MAXWELL_OPTS "
fi

echo
echo "[maxwell] maxwell command options: $maxwell_options"
echo "JAVA_OPTS: $JAVA_OPTS"

touch $lockfile  # start it and create lockfile
./bin/maxwell $maxwell_options

# if maxwell start fail, this code executed
rm -f $lockfile 