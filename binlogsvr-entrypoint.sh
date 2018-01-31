#!/bin/bash

if [ -z "$ACCESS_ID" -o -z "$ACCESS_SECRET" -o -z "$DBINSTANCE_ID" ]; then
  echo 'error: you should set ACCESS_ID, ACCESS_SECRET, DBINSTANCE_ID (exit)'
  echo '' > /var/lib/mysql/maxwell_instance.id
  exit 1
else
  # set source flag, used for graylog collecting
  echo $DBINSTANCE_ID > /var/lib/mysql/maxwell_instance.id
fi

lockfile=/var/lib/mysql/initialized.lock
if [ ! -f $lockfile ]; then
  echo "[binlogsvr] initial mysqld in /var/lib/mysql/"
  ls -lad /var/lib/mysql
  chown -R mysql:mysql /var/lib/mysql
  /usr/local/bin/docker-entrypoint.sh mysqld &
  echo "[binlogsvr] wait 1 minutes to initilize over"
  sleep 30 && touch $lockfile && echo
  echo "[binlogsvr] stop mysqld to save binlogs"
  mysqladmin -uroot -p$MYSQL_ROOT_PASSWORD shutdown

  if [ ! -f /var/lib/mysql/mysql/user.frm ];then
    echo "[warning] initialize failed, delete /var/lib/mysql/mysql for later initialization"
    rm -rf /var/lib/mysql/mysql /var/lib/mysql/ibdata1 /var/lib/mysql/ibdata1/ib_logfile* /var/lib/mysql/test
  fi
  sleep 10 && echo
else
  echo "[binlogsvr] mysqld initialized already."
fi
# mysqladmin --protocol=socket -uroot -hlocalhost --socket="${SOCKET}" --password=${MYSQL_ROOT_PASSWORD} shutdown

if [ -n "$START_TIME" -a -n "$END_TIME" ]; then
  echo 'download from oss'
  work_mode=0
  is_initialized=`cat $lockfile`
  if [ -z "$is_initialized" ];then
    echo 0 > $lockfile
  fi
elif [ -z "$START_TIME" -a -z "$END_TIME" ]; then
  echo 'retrive binlog from MYSQL_HOST directly from current postion'
  work_mode=1
  echo 1 > $lockfile
  # if [ -z "$MYSQL_USER" -o -z "$MYSQL_PASSWORD" -o -z "$MYSQL_HOST" ]; then
  #   echo "MYSQL_HOST must be given!"
  #   exit 1
  # fi
else
  echo 'You shoud set START_TIME and END_TIME, both of them or none of them (exit)'
  exit 1
fi

# in case restart the container
if [ $work_mode -eq 0 ]; then
  is_downloaded=`cat $lockfile`
  echo "is_downloaded: $is_downloaded"
  if [ $is_downloaded -eq 2 ]; then
    echo "[binlogsvr] binlog have been downloaded already"
    ret=0
  else
    echo "[binlogsvr] download binlogs from $DBINSTANCE_ID : $START_TIME $END_TIME"
    echo "pwd: `pwd`"
    python ./download_binlog.py  # $DBINSTANCE_ID $START_TIME $END_TIME # $ACCESS_ID $ACCESS_SECRET
    ret=$?
  fi
  if [ $ret -eq 0 ]; then
    echo 2 > $lockfile
    export ACCESS_SECRET="********"
    echo "[binlogsvr] start mysqld again to act as binlogsvr. (cat ./mysql-bin.index)"
    cat ./mysql-bin.index
    /usr/local/bin/docker-entrypoint.sh "mysqld"

    # if maxwell start fail, this code executed
    rm -f $lockfile 
  else
    echo "[binlogsvr] process binlog failed!(exit)"
  fi
fi