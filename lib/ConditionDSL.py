#!/usr/bin/python
import threading
import os.path
import re
import json
import pyparsing as pp
import operator


class Operation(object):
    def __repr__(self):
        return "OPERATOR:(%s)" % (",".join(str(oper) for oper in self.AST))

    def asList(self):
        AST = []
        for oper in self.AST:
            asListOp = getattr(oper, "asList", None)
            if callable(asListOp):
                AST.append(oper.asList())
            else:
                AST.append(oper)
        return AST


class UnaryOperation(Operation):
    # 一元运算
    def __init__(self, tokens):
        self.AST_TYPE = 'OPERATOR'
        op = tokens[0][0].lower()
        operand = tokens[0][1]
        self.AST = [op, operand]


class BinaryOperation(Operation):
    # 二元运算
    def __init__(self, tokens):
        self.AST_TYPE = 'OPERATOR'
        op = tokens[0][1].lower()
        operands = tokens[0][0::2]

        self.AST = [op]
        for oper in operands:
            self.AST.append(oper)


def Parser(ruleTxt):
    number = pp.pyparsing_common.integer | pp.pyparsing_common.real
    string = pp.QuotedString('"') | pp.QuotedString("'")
    value = number | string
    variable = pp.Regex(r'\$\{\w+\}|\$\w+')

    cmpOperator = pp.oneOf('= == != >= <= < > + - * / contains startswith')
    fileOperator = pp.oneOf('-f -d -e -l')
    AND = pp.CaselessLiteral("and")
    OR = pp.CaselessLiteral("or")
    NOT = pp.CaselessLiteral("not")

    oplist = [
        (cmpOperator, 2, pp.opAssoc.LEFT, BinaryOperation),
        (fileOperator, 1, pp.opAssoc.RIGHT, UnaryOperation),
        (NOT, 1, pp.opAssoc.RIGHT, UnaryOperation),
        (AND, 2, pp.opAssoc.LEFT, BinaryOperation),
        (OR, 2, pp.opAssoc.LEFT, BinaryOperation)
    ]

    ruleExp = pp.infixNotation(variable | value, oplist)

    try:
        ret = ruleExp.parseString(ruleTxt)
        ast = ret[0]
        return ast
    except pp.ParseSyntaxException as ex:
        print("Syntax error: " + str(ex))
        print(ex.line)
        print(' ' * ex.loc + '^')


class DSLError(Exception):
    def __init__(self, msg=None):
        self.msg = msg


def _startswith(a, b):
    return a.startswith(b)


def _not(a):
    return not a


def _or(a, b):
    return a or b


def _and(a, b):
    return a and b


def _isfile(a):
    return os.path.isfile(a)


def _isdir(a):
    return os.path.isdir(a)


def _fileExist(a):
    return os.path.exists(a)


def _isLink(a):
    return os.path.islink(a)


class Interpreter(object):
    _instance_lock = threading.Lock()

    def __new__(cls, *args, **kwargs):
        if not hasattr(Interpreter, "_instance"):
            with Interpreter._instance_lock:
                if not hasattr(Interpreter, "_instance"):
                    Interpreter._instance = object.__new__(cls)
        return Interpreter._instance

    def __init__(self, serverAdapter=None):
        self.operators = {
            '=': operator.eq,
            '==': operator.eq,
            '!=': operator.ne,
            '>=': operator.ge,
            '<=': operator.le,
            '<': operator.lt,
            '>': operator.gt,
            '+': operator.add,
            '-': operator.sub,
            '*': operator.mul,
            '/': operator.truediv,
            '-e': _fileExist,
            '-f': _isfile,
            '-d': _isdir,
            '-l': _isLink,
            'contains': operator.contains,
            'startswith': _startswith,
            'and': _and,
            'or': _or,
            'not': _not
        }

        # 初始化计算条件需要的发布相关的进程环境变量
        self.serverAdapter = serverAdapter
        gEnv = {}
        self.gEnv = gEnv
        dpNamePath = os.getenv('_DEPLOY_PATH')
        if dpNamePath is not None and dpNamePath != '':
            for key, value in os.environ.items():
                gEnv[key] = value

            parts = ('SYS', 'MODULE', 'ENV')

            rcObj = serverAdapter.getDeployIdPath(dpNamePath)
            dpIdPath = rcObj.get('idPath')

            if dpIdPath is not None:
                dpIds = dpIdPath.split('/')
                for idx in range(0, len(dpIds)):
                    gEnv[parts[idx] + '_ID'] = dpIds[idx]

            dpNames = dpNamePath.split('/')
            for idx in range(0, len(dpNames)):
                gEnv[parts[idx] + '_NAME'] = dpNames[idx]

            autoexecHome = os.getenv('AUTOEXEC_HOME')
            if autoexecHome is not None and autoexecHome != '':
                version = os.getenv('_VERSION')
                buildNo = os.getenv('_BUILD_NO')
                gEnv['DATA_PATH'] = dataPath = autoexecHome + '/data/verdata/' + gEnv['SYS_ID'] + '/' + gEnv['MODULE_ID']
                gEnv['PRJ_ROOT'] = prjRoot = dataPath + '/workspace'
                gEnv['PRJ_PATH'] = prjPath = prjRoot + '/project'
                gEnv['VER_ROOT'] = verRoot = dataPath + '/artifact/'
                gEnv['DIST_ROOT'] = distRoot = "$verRoot/env"
                gEnv['MIRROR_ROOT'] = mirrorRoot = "$dataPath/mirror"
                gEnv['BUILD_ROOT'] = buildRoot = dataPath + '/artifact/' + version + '/build'
                gEnv['BUILD_PATH'] = buildPath = buildRoot + '/' + buildNo

    def getOperator(self, operName):
        if operName in self.operators:
            return self.operators[operName]
        else:
            raise DSLError("Operation '{}' not supported.".format(operName))

    def getVarValue(self, nodeEnv, varName):
        varVal = nodeEnv.get(varName)
        if varVal is None:
            varVal = self.gEnv.get(varName)
        return varVal

        # 展开字串中的变量
    def resolveValue(self, nodeEnv, val):
        if not isinstance(val, str):
            return int(val)

        matchObjs = re.findall(r'^\$\{(\w+)\}$|^\$(\w+)$', val)
        if matchObjs:
            for varName in matchObjs[0]:
                if varName != '':
                    varVal = self.getVarValue(nodeEnv, varName)
                    if varVal is not None:
                        val = varVal
                        if re.match(r'^\d+$', varVal):
                            val = int(val)
                        elif re.match(r'^[\d\.]+$', varVal):
                            val = float(val)
        else:
            matchObjs1 = re.findall(r'(\$\{\s*([^\{\}]+)\s*\})', val)
            for matchObj in matchObjs1:
                exp = matchObj[0]
                varVal = self.getVarValue(nodeEnv, matchObj[1])
                if varVal is not None:
                    val = val.replace(exp, varVal)

            matchObjs2 = re.findall(r'(\$(\w+))', val)
            for matchObj in matchObjs2:
                exp = matchObj[0]
                varVal = self.getVarValue(nodeEnv, matchObj[1])
                if varVal is not None:
                    val = val.replace(exp, varVal)

        return val

    def resolveExp(self, nodeEnv, AST):
        if not isinstance(AST, list):
            return self.resolveValue(nodeEnv, AST)

        result = 0
        operName = AST[0]
        op = self.getOperator(operName)

        operandsCount = len(AST) - 1
        if operandsCount == 2:
            operand1 = self.resolveExp(AST[1])
            operand2 = self.resolveExp(AST[2])
            if isinstance(operand1, str):
                operand2 = str(operand2)
            else:
                if isinstance(operand2, str):
                    if re.match(r'^\d+$', operand2):
                        operand2 = float(operand2)
                    else:
                        operand2 = int(operand2)

            result = op(operand1, operand2)
        else:
            operand1 = self.resolveExp(AST[1])
            result = op(operand1)

        return result

    # 据根据抽象语法树从数据中抽取匹配的字段的path
    def resolve(self, nodeEnv, AST):
        return self.resolveExp(nodeEnv, AST)


if __name__ == "__main__":
    print("Test...")
    print("----------------------------\n")

    rule = '$MYVAR == "hello" and (-f "/tmp/test.txt" or -d "/tmp/tt")'
    ast = Parser(rule)
    if isinstance(ast, Operation):
        print(json.dumps(ast.asList(), sort_keys=True, indent=4))

        interpreter = Interpreter(AST=ast.asList())
        result = interpreter.resolve()
        print(result)
    else:
        print("ERROR: Parse error, syntax error at char 0\n")
