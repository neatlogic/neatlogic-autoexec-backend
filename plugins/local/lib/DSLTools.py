#!/usr/bin/python
import warnings
import json
import pyparsing as pp
import operator


class Operation(object):
    def __repr__(self):
        return "OPERATOR:(%s)" % (",".join(str(oper) for oper in self.AST))

    def asList(self):
        AST = ['OPERATOR']
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


class FieldTerm(object):
    def __init__(self, tokens):
        self.AST_TYPE = 'FIELD'
        self.name = tokens[0]
        if len(tokens) > 1:
            self.AST = tokens[1]
        else:
            self.AST = None

    def __repr__(self):
        return "FIELD:(%s,%s)" % (self.name, self.AST)

    def asList(self):
        AST = ['FIELD', self.name]
        if self.AST:
            asListOp = getattr(self.AST, "asList", None)
            if callable(asListOp):
                AST.append(self.AST.asList())
            else:
                AST.append(self.AST)
        else:
            AST.append(None)
        return AST


class QueryTerm(object):
    def __init__(self, tokens):
        self.AST_TYPE = 'QUERY'
        self.AST = tokens

    def __repr__(self):
        return "QUERY:(%s)" % (",".join(str(a) for a in self.AST))

    def asList(self):
        AST = ['QUERY']
        for a in self.AST:
            AST.append(a.asList())
        return AST


class FieldCalcTerm(object):
    def __init__(self, tokens):
        self.AST_TYPE = 'FIELD_CALC'
        self.AST = tokens

    def __repr__(self):
        return "FIELD_CALC:(%s)" % (",".join(str(a) for a in self.AST))

    def asList(self):
        AST = ['FIELD_CALC']
        for a in self.AST:
            AST.append(a.asList())
        return AST


def Parser(ruleTxt):
    DOT = pp.Suppress('.')
    LBRACK = pp.Suppress('[')
    RBRACK = pp.Suppress(']')
    LCURLY = pp.Suppress('{')
    RCURLY = pp.Suppress('}')
    CURRDOC = pp.Literal('$')
    this = pp.CaselessKeyword("$this")

    number = pp.pyparsing_common.integer | pp.pyparsing_common.real
    string = pp.QuotedString('"') | pp.QuotedString("'")
    value = number | string
    fieldName = pp.pyparsing_common.identifier | string

    cmpOperator = pp.oneOf('= == != >= <= < > contains startswith')
    calcOperator = pp.oneOf('+ - * / %')
    AND = pp.CaselessLiteral("and")
    OR = pp.CaselessLiteral("or")
    NOT = pp.CaselessLiteral("not")

    oplist = [
        (cmpOperator, 2, pp.opAssoc.LEFT, BinaryOperation),
        (NOT, 1, pp.opAssoc.RIGHT, UnaryOperation),
        (AND, 2, pp.opAssoc.LEFT, BinaryOperation),
        (OR, 2, pp.opAssoc.LEFT, BinaryOperation)
    ]

    calcOpList = [
        (calcOperator, 2, pp.opAssoc.LEFT, BinaryOperation)
    ]

    fieldFilter = LBRACK + pp.infixNotation(fieldName | value, oplist) + RBRACK
    emptyFilter = LBRACK + RBRACK

    thisDoc = CURRDOC + pp.Optional(fieldFilter | emptyFilter)
    thisDoc.setParseAction(FieldTerm)

    bareField = DOT + fieldName
    bareField.setParseAction(FieldTerm)

    fieldDef = DOT + fieldName + pp.Optional(fieldFilter | emptyFilter)
    fieldDef.setParseAction(FieldTerm)

    pureQuery = thisDoc + pp.ZeroOrMore(fieldDef)
    pureQuery.setParseAction(QueryTerm)

    fieldCalc = LCURLY - pp.infixNotation(this | pureQuery | value, calcOpList) - RCURLY
    fieldCalc.setParseAction(FieldCalcTerm)

    lastField = DOT + fieldName + fieldCalc
    lastField.setParseAction(FieldTerm)

    calcQuery = thisDoc + pp.ZeroOrMore(fieldDef, stopOn=lastField) + lastField
    calcQuery.setParseAction(QueryTerm)

    ruleDef = pp.infixNotation(calcQuery | pureQuery | value, oplist)

    try:
        ret = ruleDef.parseString(ruleTxt)
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


class Interpreter(object):
    def __init__(self, AST=None, ruleName=None, ruleLevel=None, data=None):
        # data格式为dict格式
        self.AST = AST
        self.ruleName = ruleName
        self.ruleLevel = ruleLevel
        self.data = data
        self.matchedFields = []

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
            '%': operator.mod,
            'contains': operator.contains,
            'startswith': _startswith,
            'and': _and,
            'or': _or,
            'not': _not
        }

    def getOperator(self, operName):
        if operName in self.operators:
            return self.operators[operName]
        else:
            raise DSLError("Operation '{}' not supported.".format(operName))

    # operateStr：顶层操作符号，查询出的属性比较计算的操作符号子串
    # operands：操作符号设计的操作数的列表，可能是QUERY，也可能是嵌套的操作符结构

    def resolveValueQueryOper(self, fieldValue, operateStr, operands):
        result = None

        operandsVal = []
        for operand in operands:
            if operand == '$this':
                operandsVal.append(fieldValue)
                continue

            elif not isinstance(operand, list):
                operandsVal.append(operand)
                continue

            if operand[0] == 'QUERY':
                operandsVal.append(self.resolveValueQuery(operand))
            elif operand[0] == 'OPERATOR':
                # 如果是嵌套的操作，则拼装参数调用 resolveValueQueryOper
                operand.pop(0)  # 去掉'OPERATOR'标记符
                nextOperateStr = operand.pop(0)  # 取出操作符
                subOperands = operand  # 剩下的就是操作数
                operandsVal.append(self.resolveValueQueryOper(fieldValue, nextOperateStr, subOperands))
            else:
                raise DSLError("Invalid AST node type {} in: {}".format(operand[0], json.dumps(operand)))

        if operateStr in self.operators:
            op = self.getOperator(operateStr)
            operandsLen = len(operandsVal)
            if operandsLen == 1:
                result = op(operandsVal[0])
            else:
                result = op(operandsVal[0], operandsVal[1])

        return result

    # 右操作数的json字段值查询
    # fields：查询的字段列表，第一个元素是"QUERY",第二个元素开始才是字段的描述
    def resolveValueQuery(self, fields):
        return self.resolveFieldValue(self.data, '', fields, 1)

    # 右操作数的json字段值查询
    # parentDoc：上级数据（包含当前field属性）
    # jsonPath：上级数据的jsonPath，格式$.ATTR1.ATTR2[2].ATTR3
    # fields：当前Query查询的字段列表
    # idx：当前字段在字段列表中的下标
    def resolveFieldValue(self, parentDoc, jsonPath, fields, idx):
        fieldsCount = len(fields)
        field = fields[idx]

        if len(field) < 3 and field[0] != 'FIELD':
            raise DSLError("Invalid field node {} in: {}".format(json.dumps(field), json.dumps(self.AST)))

        fieldName = field[1]
        fieldValue = None

        if fieldName == '$' and jsonPath == '':
            fieldValue = parentDoc
        elif fieldName in parentDoc:
            fieldValue = parentDoc[fieldName]

        jsonPath = jsonPath + '.' + fieldName

        if idx >= fieldsCount - 1:
            # 最后一个属性字段，取出值返回
            if fieldValue is not None:
                return fieldValue
            else:
                warnings.warn("Data field not found: " + jsonPath[1:], category=Warning)
                return None

        if fieldValue is not None:
            resolvedValue = None

            fieldFilter = field[2]
            if fieldFilter is None:
                # 如果属性字段没有配置filter
                if isinstance(fieldValue, list):
                    # for record in fieldValue:
                    for k in range(len(fieldValue)):
                        record = fieldValue[k]
                        nextJsonPath = jsonPath + '[' + str(k) + ']'
                        resolvedValue = self.resolveFieldValue(record, nextJsonPath, fields, idx + 1)
                        if resolvedValue is not None:
                            break
                elif isinstance(fieldValue, dict):
                    resolvedValue = self.resolveFieldValue(fieldValue, jsonPath, fields, idx + 1)
            else:
                # 属性存在filter设置
                matched = False
                if isinstance(fieldValue, list):
                    for k in range(len(fieldValue)):
                        record = fieldValue[k]
                        nextJsonPath = jsonPath + '[' + str(k) + ']'
                        matched = self.resolveFilter(record, fieldFilter)
                        if matched:
                            resolvedValue = self.resolveFieldValue(record, nextJsonPath, fields, idx + 1)
                            if resolvedValue is not None:
                                break
                elif isinstance(fieldValue, dict):
                    matched = self.resolveFilter(fieldValue, fieldFilter)
                    if matched:
                        resolvedValue = self.resolveFieldValue(fieldValue, jsonPath, fields, idx + 1)

            return resolvedValue
        else:
            warnings.warn("Data field not found: " + jsonPath[1:], category=Warning)
            return None

    # operate：顶层操作符号，查询出的属性比较计算的操作符号子串
    # operands：操作符号设计的操作数的列表，可能是QUERY，也可能是嵌套的操作符结构

    def resolveQueryOper(self, operateStr, operands):
        result = None

        operandsVal = []
        for operand in operands:
            if not isinstance(operand, list):
                operandsVal.append(operand)
                continue

            if operand[0] == 'OPERATOR':
                nextOperateStr = operand[1]
                if operand[2][0] == 'QUERY':
                    # 如果是查询，则拼装参数调用resolveQuery
                    fields = operand[2]
                    value = None
                    if len(operand) >= 4:
                        value = operand[3]
                    operandsVal.append(self.resolveQuery(fields, nextOperateStr, value))
                elif operand[2][0] == 'OPERATOR':
                    # 如果是嵌套的操作，则拼装参数调用resolveQueryOper
                    subOperands = [operand[2]]
                    if nextOperateStr not in ('not', '!'):
                        subOperands.append(operand[3])
                    operandsVal.append(self.resolveQueryOper(nextOperateStr, subOperands))
                else:
                    raise DSLError("Invalid AST node type {} in: {}".format(operand[2][0], json.dumps(self.AST)))
            else:
                raise DSLError("Invalid AST node type {} in: {}".format(operands[0], json.dumps(self.AST)))

        if operateStr in self.operators:
            op = self.getOperator(operateStr)
            operandsLen = len(operandsVal)
            if operandsLen == 1:
                result = op(operandsVal[0])
            else:
                result = op(operandsVal[0], operandsVal[1])

        return result

    # fields：查询的字段列表，第一个元素是"QUERY",第二个元素开始才是字段的描述
    # operate：比较操作符号字串
    # value：比较的目标值
    def resolveQuery(self, fields, operate, value):
        result = None
        op = self.getOperator(operate)
        # 解析查询返回多个数值并根value进行operate计算返回True或False

        jsonPath = ''
        matchedRecord = self.resolveField(self.data, jsonPath, op, value, fields, 1)

        if matchedRecord > 0:
            result = True
        else:
            result = False

        return result

    # parentDoc：上级数据（包含当前field属性）
    # jsonPath：上级数据的jsonPath，格式$.ATTR1.ATTR2[2].ATTR3
    # op：Query查询的运算符函数
    # value：与最终匹配出的属性值比较的值
    # fields：当前Query查询的字段列表
    # idx：当前字段在字段列表中的下标

    def resolveField(self, parentDoc, jsonPath, op, value, fields, idx):
        matchedRecord = 0
        fieldsCount = len(fields)
        field = fields[idx]

        if len(field) < 3 and field[0] != 'FIELD':
            raise DSLError("Invalid field node {} in: {}".format(json.dumps(field), json.dumps(self.AST)))

        fieldName = field[1]
        fieldValue = None

        if fieldName == '$' and jsonPath == '':
            fieldValue = parentDoc
        elif fieldName in parentDoc:
            fieldValue = parentDoc[fieldName]

        jsonPath = jsonPath + '.' + fieldName

        if idx >= fieldsCount - 1:
            # 最后一个属性字段，取出值返回
            if fieldValue is not None:
                resultFieldVal = fieldValue
                fieldCalc = field[2]
                if fieldCalc is not None and fieldCalc[0] == 'FIELD_CALC':
                    filedCalcAST = fieldCalc[1]
                    if filedCalcAST[0] == 'OPERATOR':
                        operate = filedCalcAST[1]
                        # 嵌套操作符号
                        operands = [filedCalcAST[2], filedCalcAST[3]]
                        resultFieldVal = self.resolveValueQueryOper(fieldValue, operate, operands)
                    else:
                        raise DSLError("Invalid AST node type {} in: {}".format(filedCalcAST[0], json.dumps(filedCalcAST)))

                try:
                    if op(resultFieldVal, value):
                        matchedField = {
                            'jsonPath': jsonPath[1:],
                            'ruleName': self.ruleName,
                            'ruleLevel': self.ruleLevel,
                            'fieldValue': fieldValue,
                        }
                        self.matchedFields.append(matchedField)
                        return matchedRecord + 1
                except Exception as ex:
                    warnings.warn(str(ex) + ", invalid field value type for " + jsonPath[1:], category=Warning)
            else:
                warnings.warn("Data field not found: " + jsonPath[1:], category=Warning)
                return matchedRecord

        if fieldValue is not None:
            fieldFilter = field[2]

            if fieldFilter is None:
                # 如果属性字段没有配置filter
                if isinstance(fieldValue, list):
                    # for record in fieldValue:
                    for k in range(len(fieldValue)):
                        record = fieldValue[k]
                        nextJsonPath = jsonPath + '[' + str(k) + ']'
                        matchedCount = self.resolveField(record, nextJsonPath, op, value, fields, idx + 1)
                        matchedRecord = matchedRecord + matchedCount
                elif isinstance(fieldValue, dict):
                    matchedCount = self.resolveField(fieldValue, jsonPath, op, value, fields, idx + 1)
                    matchedRecord = matchedRecord + matchedCount
                else:
                    return 0
            else:
                # 属性存在filter设置
                matched = False
                if isinstance(fieldValue, list):
                    for k in range(len(fieldValue)):
                        record = fieldValue[k]
                        nextJsonPath = jsonPath + '[' + str(k) + ']'
                        matched = self.resolveFilter(record, fieldFilter)
                        if matched:
                            matchedCount = self.resolveField(record, nextJsonPath, op, value, fields, idx + 1)
                            matchedRecord = matchedRecord + matchedCount
                elif isinstance(fieldValue, dict):
                    matched = self.resolveFilter(fieldValue, fieldFilter)
                    if matched:
                        matchedCount = self.resolveField(fieldValue, jsonPath, op, value, fields, idx + 1)
                        matchedRecord = matchedRecord + matchedCount
                else:
                    return matchedRecord

            return matchedRecord
        else:
            warnings.warn("Data field not found: " + jsonPath[1:], category=Warning)
            return matchedRecord

    # 计算字段属性的过滤条件，符合则返回True，否则返回False
    # record：当前属性的当前记录
    # fieldFilter：字段过滤设置
    def resolveFilter(self, record, fieldFilter):
        if fieldFilter[0] != 'OPERATOR':
            raise DSLError("Invalid AST node type {} in: {}".format(json.dumps(fieldFilter), json.dumps(self.AST)))

        operatorStr = fieldFilter[1]
        operands = []
        for operand in fieldFilter[2:]:
            if isinstance(operand, list):
                operands.append(self.resolveFilter(record, operand))
            else:
                operands.append(operand)

        result = False
        op = self.getOperator(operatorStr)
        if len(operands) == 0:
            raise DSLError("Invalid AST node type {} in: {}".format(json.dumps(fieldFilter), json.dumps(self.AST)))

        recordFieldName = operands[0]
        recordFieldVal = None
        # 如果字段选择规则的左操作数是字符串，则判断为字段名
        # 因为计算最终只能产生数值或者bool类型的结果
        if isinstance(recordFieldName, str):
            recordFieldVal = self.resolveValue(record, recordFieldName)
        else:
            recordFieldVal = recordFieldName

        if recordFieldVal is not None:
            if len(operands) > 1:
                result = op(recordFieldVal, operands[1])
            elif len(operands) == 1:
                result = op(recordFieldVal)

        return result

    # 从属性记录中抽取值
    # record：属性的某个记录
    # nameStr：属性，例如：attr1.attr2
    def resolveValue(self, record, nameStr):
        values = record
        try:
            for name in nameStr.split('.'):
                values = values[name]
            return values
        except KeyError:
            return None

    # 据根据抽象语法树从数据中抽取匹配的字段的path
    def resolve(self):
        result = False
        self.matchedFields = []

        AST = self.AST
        if AST[0] == 'OPERATOR':
            operate = AST[1]
            if AST[2][0] == 'QUERY':
                # 查询匹配规则计算
                fields = AST[2]
                value = None
                if len(AST) >= 3:
                    value = AST[3]
                result = self.resolveQuery(fields, operate, value)
            else:
                # 嵌套操作符号
                operands = [AST[2]]
                if operate not in ('not', '!'):
                    operands.append(AST[3])
                result = self.resolveQueryOper(operate, operands)
        else:
            raise DSLError("Invalid AST node type {} in: {}".format(AST[0], json.dumps(AST)))

        if result:
            return self.matchedFields
        else:
            return []


if __name__ == "__main__":
    print("Test...")
    print("----------------------------\n")
    txt = '''$.DISKS[name == "/home" or not (name contains "/boot" and size > 100)].CAPACITY{$this/$.CPU_LOGIC_CORES} > 1000
        and ($.DISKS[name == "/home" or name contains '/boot' ].CAPACITY > 1500 and $.DISKS[name == "/home" or name contains "/boot" ].CAPACITY {$this/$.CPU_LOGIC_CORES} < 99999)
        '''
    #txt = '''$[IS_VERTUAL==1].DISKS[name == "/home"].CAPACITY > 1000 and $.DISKS[].CAPACITY[] > 1500 or $.DISKS[name == "/home1"].CAPACITY < 99999'''

    #ast = Parser(txt)
    #print(json.dumps(ast.asList(), sort_keys=True, indent=4))
    data = None
    with open('/Users/wenhb/git/autoexec/test/sample.json', 'r') as f:
        data = json.load(f)
        f.close()

    rule = '$.DISKS["NAME" contains "/dev/"].CAPACITY {$this/$.CPU_LOGIC_CORES} > 5 or $.MEM_AVAILABLE{$this/1000}>2'
    rule1 = '$.MOUNT_POINTS.USED_PCT >= 80'
    rule2 = '$.TOP_CPU_RPOCESSES.CPU_USAGE{$this/$.CPU_LOGIC_CORES} >= 30'
    ast = Parser(rule1)
    print(json.dumps(ast.asList(), sort_keys=True, indent=4))

    interpreter = Interpreter(AST=ast.asList(), ruleName="测试", ruleLevel="L1", data=data)
    matchedFields = interpreter.resolve()

    print(json.dumps(matchedFields, ensure_ascii=False, sort_keys=True, indent=4))
