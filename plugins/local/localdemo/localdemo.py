#!/usr/bin/python

import os
import argparse


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
