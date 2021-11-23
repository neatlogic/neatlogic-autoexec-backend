#!/usr/bin/python
from pyparsing import *
from JsonDataFilter import Filter

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
