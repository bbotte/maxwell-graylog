#coding:utf-8
import os
import sys
import subprocess
import datetime
import json
from aliyunsdkcore import client
from aliyunsdkrds.request.v20140815 import DescribeBinlogFilesRequest as BinlogRequest

"""
author:  zhouxiao@ecqun.com
date:    2017-12
"""

VERSION_RDS = '20140815'
URL_RDS = 'https://rds.aliyuncs.com'


def gen_query_time(datetime_str):
    """
    convert string datetime format like '2017-12-14 18:16:11' + 8
    :return:
    """
    try:
        datetime_std = datetime.datetime.strptime(datetime_str.strip("'").strip('"'), "%Y-%m-%d %H:%M:%S")
    except Exception as e:
        print(e)
        sys.exit(2)
        # return 0
    else:
        datetime_utc = datetime_std - datetime.timedelta(hours=8)
        return datetime_utc.strftime("%Y-%m-%dT%H:%M:%SZ")


def check_and_get_args():
    """
    DBINSTANCE_ID, START_TIME, ENDTIME can be given in arguments or set in environment
    ACCESS_ID, ACCSSS_SECRET can be set only in environment variables
    :return:
    """
    print('check variables: DBINSTANCE_ID, START_TIME, ENDTIME, ACCESS_ID, ACCSSS_SECRET')
    sys_param = sys.argv[1:]
    env_dict = os.environ

    if len(sys_param) == 3:
        dbinstance_id = sys_param[0] or 0
        start_time = sys_param[1] or 0
        end_time = sys_param[2] or 0
    else:
        dbinstance_id = env_dict.get('DBINSTANCE_ID', 0)
        start_time = env_dict.get('START_TIME', 0)
        end_time = env_dict.get('END_TIME', 0)

    if dbinstance_id == 0 or start_time == 0 or end_time == 0:
        print('Wrong arguments or environment variables for [{0}] to download: \n'
              '  DBINSTANCE_ID={1}, START_TIME={2}, END_TIME={3}'.format(
            sys.argv[0], dbinstance_id, start_time, end_time))
        sys.exit(2)

    # convert datetime # start_time, end_time is string format '2017-12-14 18:16:11'
    start_time = gen_query_time(start_time)
    end_time = gen_query_time(end_time)

    # access_key
    access_id = env_dict.get('ACCESS_ID', 0)
    access_secret = env_dict.get('ACCESS_SECRET', 0)

    if access_id == 0 or access_secret == 0:
        print("Aliyun RDS 'ACCESS_ID' and 'ACCESS_SECRET' should be set in environment variables")
        sys.exit(2)

    return access_id, access_secret, dbinstance_id, start_time, end_time


def write_index_file(binlog_list):
    f = open('mysql-bin.index', 'w')
    for file_name in binlog_list:
        f.write('./' + file_name + '\n')
    f.close()


class RdsApi(object):
    def __init__(self, access_id, access_secret, dbinstance_id, start_time, end_time):
        self.output_format = 'json'
        self.version = VERSION_RDS

        self.dbinstance_id = dbinstance_id
        self.access_id = access_id
        self.access_secret = access_secret
        self.start_time = start_time
        self.end_time = end_time

    def get_binlog_list(self, page_size=30, page_no=1):
        request = BinlogRequest.DescribeBinlogFilesRequest()
        request.set_accept_format(self.output_format)
        request.set_DBInstanceId(self.dbinstance_id)

        request.set_StartTime(self.start_time)
        request.set_EndTime(self.end_time)
        request.set_PageSize(page_size)
        request.set_PageNumber(page_no)

        clt = client.AcsClient(self.access_id, self.access_secret, 'cn-hangzhou')
        ret = json.loads(clt.do_action_with_exception(request))
        if ret.has_key('Code'):
            print(ret)
            return []
        else:
            binlog_list = ret['Items']['BinLogFile']
            if ret['PageRecordCount'] >= page_size:
                # 递归调用，翻页
                binlog_list.extend(self.get_binlog_list(page_size,  page_no + 1))
        print('total binlog files: %s' % ret['TotalRecordCount'])

        return binlog_list

    def download(self, file_url, save_path='./'):
        file_name_tar = file_url.split('?')[0].split('/')[5]
        file_name = file_name_tar[:-4]  # remove .tar
        wget_cmd = 'wget -q -c "{0}" -O {1} && tar -xf {1} && rm -f {1}'.format(file_url, file_name_tar)
        try:
            ret = subprocess.check_output(wget_cmd, shell=True)  # , stderr=subprocess.STDOUT)
        except subprocess.CalledProcessError, e:
            print(e)
        except KeyError:
            print(e)
        return file_name

    def process_file(self):
        binlog_list = self.get_binlog_list()
        if len(binlog_list) == 0:
            print('[warninig] No binlog found!')
        binlog_file_list = []
        HostInstanceID = binlog_list[0]['HostInstanceID']  # only get master OR shadow instance
        for binlog in binlog_list:
            if HostInstanceID != binlog['HostInstanceID']:
                continue
            file_url = binlog['IntranetDownloadLink']
            file_url = file_url.replace('-i-internal', '-internal')  # VPC网络访问OSS内网地址，去掉 -i
            print("Downloading : '{0}'".format(file_url))
            file_name = self.download(file_url)
            binlog_file_list.append(file_name)
        binlog_file_list.sort()

        return binlog_file_list


if __name__ == '__main__':
    x_access_id, x_access_secret, x_dbinstance_id, x_start_time, x_end_time = check_and_get_args()

    api = RdsApi(
        access_id=x_access_id,
        access_secret=x_access_secret,
        dbinstance_id=x_dbinstance_id,
        start_time=x_start_time,  # '2017-12-14 18:16:11',
        end_time=x_end_time  # '2017-12-19 23:16:11'
    )

    binlog_list = api.process_file()
    write_index_file(binlog_list)
    sys.exit(0)
