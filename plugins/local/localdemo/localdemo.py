#!/usr/bin/python

import os
import sys
import argparse
import Utils

binPaths = os.path.split(os.path.realpath(__file__))
libPath = os.path.realpath(binPaths[0]+'/../lib')
sys.path.append(libPath)


def usage():
    # 帮助提示信息
    pname = os.path.basename(__file__)
    print(pname + "--tinput <tinput> --tjson <tjson> --tselect <tselect> --tmultiselect <tmultiselect> --tpassword <tpassword> --tfile <tfile> --tnode <node id> --tdate <tdate> --ttime <ttime> --tdatetime <tdatetime>")


if __name__ == "__main__":
    # 参数处理
    parser = argparse.ArgumentParser()
    parser.add_argument('--tinput', default='', help='XXXXXX')
    parser.add_argument('--tjson', default='', help='XXXXXXX')
    parser.add_argument('--tselect', default='', help='XXXXXXX')
    parser.add_argument('--tmultiselect', default='', help='XXXXXXX')
    parser.add_argument('--tpassword', default='', help='XXXXXXX')
    parser.add_argument('--tfile', default='', help='XXXXXXX')
    parser.add_argument('--tnode', default='', help='XXXXXXX')
    parser.add_argument('--tdate', default='', help='XXXXXXX')
    parser.add_argument('--ttime', default='', help='XXXXXXX')
    parser.add_argument('--tdatetime', default='', help='XXXXXXX')

    args = parser.parse_args()

    # 主体处理逻辑
    print("Get options:============\n")
    print("tinput:" + args.tinput)
    print("tjson:" + args.tjson)
    print("tselect:" + args.tselect)
    print("tmultiselect:" + args.tmultiselect)
    print("tpassword:" + args.tpassword)
    print("tfile:" + args.tfile)
    print("tnode:" + args.tnode)
    print("tdate:" + args.tdate)
    print("ttime:" + args.ttime)
    print("tdatetime:" + args.tdatetime)

    print("Do some jobs=====\n")

    # 保存输出到json文件
    print("Save output to file\n")
    out = []
    out['outtext'] = "this is the text out value"
    out['outpassword'] = "{RC4}xxxxxxxxxx"
    out['outfile'] = "this is the output file name"
    out['outjson'] = '{"key1":"value1", "key2":"value2"}'
    out['outcsv'] = '"name","sex","age"\n"张三“,"男“,"30"\n"李四","女“,"35"}'
    Utils.saveOutput(out)
