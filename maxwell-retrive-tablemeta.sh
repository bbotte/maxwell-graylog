#!/bin/bash
# checkout the latest version

mysql_cmd_opts="--host=mysql_binlogsvr --user=root --password=strongpassword"

# MYSQL_HOST_GIT=db_crm0
if [ -z "$MYSQL_HOST_GIT" ]; then
  echo "[maxwell_binlog] MYSQL_HOST_GIT is not set, see http://git.workec.com/ops/DBschema(exit)"
  exit 1
fi

filterDir=${MYSQL_HOST_GIT}_maxwell

rm -rf DBschema $filterDir
mkdir -p $filterDir && chown 600 -R /root/.ssh
echo "    StrictHostKeyChecking no" >> /etc/ssh/ssh_config

#### replace with your git repository here ####
echo "[maxwell_binlog] git clone git@git.workec.com:ops/DBschema.git  to get database schema"
git clone git@git.workec.com:ops/DBschema.git

if [ -n "$MYSQL_HOST_GIT_COMMIT" ]; then
  cd DBschema ; git checkout $MYSQL_HOST_GIT_COMMIT ; cd ..
fi

cp -a DBschema/production/$MYSQL_HOST_GIT $MYSQL_HOST_GIT

# cp -a ./$MYSQL_HOST_GIT/*.${table}-schema.sql ./$filterDir/
# cp -a ./$MYSQL_HOST_GIT/${database}.*-schema.sql ./$filterDir/

cp -a -f ./$MYSQL_HOST_GIT/*-schema-create.sql ./$filterDir/

if [ -n "$include_tables" ];then
  filter=(${include_tables//,/ })
  for tbl in ${filter[@]}
  do
    tbl=${tbl//\//}
    cp -a -f ./$MYSQL_HOST_GIT/*.${tbl//\.\*/*}-schema.sql ./$filterDir/
  done
  # set sql_log_bin=0
elif [ -n "$include_dbs" ];then
  filter=(${include_dbs//,/ })
  for db in ${filter[@]}
  do
    db=${db//\//}
    cp -a -f ./$MYSQL_HOST_GIT/${db/\.\*/*}.*-schema.sql ./$filterDir/
  done
else
  echo "[maxwell_binlog] neither include_tables or include_dbs is specified. create all tables"
  cp -a -f ./$MYSQL_HOST_GIT/* ./$filterDir/ && rm -f ./$filterDir/mysql.*
fi
touch ./$filterDir/metadata
# no binlog enable
echo "myloader $mysql_cmd_opts -d ./$filterDir "
myloader $mysql_cmd_opts -t 1 -d ./$filterDir
