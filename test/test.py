#!/usr/bin/python
from pyparsing import *
import re
from JsonDataFilter import Filter


def parseSizeStr(sizeStr):
    size = sizeStr
    matchObj = re.match(r'(\d+)([MGTP]?)', sizeStr, re.IGNORECASE)
    if matchObj:
        size = float(matchObj.group(1))
        unit = matchObj.group(2).upper()
        if unit == 'M':
            size = round(size / 1000, 2)
        elif unit == 'T':
            size = size * 1000
        elif unit == 'P':
            size = size * 1000 * 1000
    return size


def parseTableHeader(headerLines, fieldLenArray):
    head = []
    for fieldLen in fieldLenArray:
        head.append('')

    for line in headerLines:
        if line == '':
            continue
        pos = 0
        for k in range(0, len(fieldLenArray)):
            fieldLen = fieldLenArray[k]
            head[k] = head[k] + line[pos:pos+fieldLen].strip() + ' '
            pos = pos + fieldLen

    for k in range(0, len(head)):
        head[k] = head[k].strip()

    return head


def parseTableBody(bodyLines, fieldLenArray):
    body = []
    for line in bodyLines:
        if line == '':
            continue

        record = []
        pos = 0
        for k in range(0, len(fieldLenArray)):
            fieldLen = fieldLenArray[k]
            record.append(line[pos:pos+fieldLen].strip())
            pos = pos + fieldLen

        body.append(record)

    return body


def parseTable(tableTxt):
    lines = tableTxt.split('\n')
    lineCount = len(lines)

    fieldLenArray = []
    headerLines = []
    idx = 0
    for idx in range(0, lineCount):
        line = lines[idx]
        headerLines.append(line)
        if re.match(r'^[- ]+$', line):
            for placeholder in line.split('  '):
                fieldLenArray.append(len(placeholder) + 2)
            headerLines.pop()
            break

    head = parseTableHeader(headerLines, fieldLenArray)
    body = parseTableBody(lines[idx+1:], fieldLenArray)

    return (head, body)


def testParse():
    summaryTxt = '''Cluster    Volume                               Volume          Oper   Health  Active  
Name       Name                                 Type            State  State           
---------  -----------------------------------  --------------  -----  ------  ------  
cluster-1  vplex1_meta_backup_2022Jan03_000013  meta-volume     ok     ok      False   
cluster-1  vplex1_log                           logging-volume  ok     ok      -       
cluster-1  vplex1_meta_backup_2022Jan04_000017  meta-volume     ok     ok      False   
cluster-1  vplex1_meta                          meta-volume     ok     ok      True    
cluster-2  vplex2_log                           logging-volume  ok     ok      -       
cluster-2  vplex2_meta_backup_2022Jan04_000015  meta-volume     ok     ok      False   
cluster-2  vplex2_meta                          meta-volume     ok     ok      True    
cluster-2  vplex2_meta_backup_2022Jan03_000020  meta-volume     ok     ok      False   

'''
    (head, body) = parseTable(summaryTxt)
    print(head)
    print(body)


if __name__ == "__main__":
    print("Test...")
    x = Filter({"eq": ("foo", 1)})
    assert x(foo=1)

    x = Filter({"eq": ("foo", "bar")})
    assert not x(foo=1)

    x = Filter({"or": (
        {"eq": ("foo", "bar")},
        {"eq": ("bar", 1)},
    )})
    assert x(foo=1, bar=1)

    x = Filter({"eq": ("baz.sub", 23)})
    assert x(foo=1, bar=1, baz={"sub": 23})

    x = Filter({"eq": ("baz.sub", 23)})
    assert not x(foo=1, bar=1, baz={"sub": 3})

    data_word = Word(alphas)
    label = data_word + FollowedBy(':')
    attr_expr = Group(label + Suppress(':') + OneOrMore(data_word).setParseAction(' '.join))

    text = "shape: SQUARE posn: upper left color: light blue texture: burlap"
    attr_expr = (label + Suppress(':') + OneOrMore(data_word, stopOn=label).setParseAction(' '.join))

    # print attributes as plain groups
    print(OneOrMore(attr_expr).parseString(text).dump())

    # instead of OneOrMore(expr), parse using Dict(OneOrMore(Group(expr))) - Dict will auto-assign names
    result = Dict(OneOrMore(Group(attr_expr))).parseString(text)
    print(result.dump())
    print("========================")
    # access named fields as dict entries, or output as dict
    print(result['shape'])
    print("========================")
    print(result.asDict())

    testParse()
