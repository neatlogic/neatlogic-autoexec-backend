#!/usr/bin/python

import os
import argparse
import sys 

binPaths = os.path.split(os.path.realpath(__file__))
libPath = os.path.realpath(binPaths[0]+'/../lib')
sys.path.append(libPath)
import MongoDB 
import Utils

def usage():
    pname = os.path.basename(__file__)
    print("请提供参数：")
    print(pname + " --output_path <output_path> --data_json <data_json>")
    exit(1)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('--output_path', default='', help='前置插件或步骤output输出路径')
    parser.add_argument('--data_json', default='', help='JSON数据文件')
    args = parser.parse_args()

    output_path = args.output_path
    data_json = args.data_json
    if (data_json == None or data_json == '') and (output_path == None or output_path == '' ) :
        usage()

    collect_data = None
    Util = Utils.Utils()
    if data_json != None and data_json != '' :
        collect_data = data_json
    else :
        collect_data = Util.getOutput(output_path)

    #valid = Util.isJson(collect_data)
    #if valid == False :
    #    print("Illegal parameter :{} / {}".format(output_path,data_json))
    #    exit(-1)
    
    table = collect_data['table']
    uniqueName = collect_data['uniqueName']
    data = collect_data['data'] 
    db = MongoDB.MongoDB()
    #保存采集的数据
    count = db.count(table ,uniqueName)
    #print("count:{}".format(count))
    if count == 0 : 
        db.insert(table,data)
    else :
        db.update(table ,uniqueName , data)
    db.close()
        


    
