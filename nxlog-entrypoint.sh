#!/bin/bash

maxwell_instance=/var/lib/mysql/maxwell_instance.id
touch $maxwell_instance
DBINSTANCE_ID=`cat $maxwell_instance`
if [ -z $DBINSTANCE_ID -o -z $graylogserver -o -z $graylog_maxwell_gelf_port -o -z $graylog_maxwell_source_collector ];then
  echo "DBINSTANCE_ID, graylogserver, graylog_maxwell_gelf_port, graylog_maxwell_source_collector can not be empty(exit)"
  exit 1
fi

sed -i "s/__maxwell_dbinstance_id__/${DBINSTANCE_ID}/g" /etc/nxlog/nxlog.conf
sed -i "s/__graylogserver__/${graylogserver}/g" /etc/nxlog/nxlog.conf
sed -i "s/__graylog_maxwell_gelf_port__/${graylog_maxwell_gelf_port}/g" /etc/nxlog/nxlog.conf
sed -i "s/__graylog_maxwell_source_collector__/${graylog_maxwell_source_collector}/g" /etc/nxlog/nxlog.conf

/usr/bin/nxlog -f