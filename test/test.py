#!/usr/bin/python
import VContext
import Utils


def testEncrypt():
    data = 'E!YO@JyjD^RIwe*OE739#Sdk%'
    vContext = VContext.VContext()
    enrypted = Utils._rc4_encrypt_hex('c3H002LGZRrseEPc', data)
    print(enrypted)


def testDecrypt():
    encrypted = '05a90b9d7fcd2449928041'
    vContext = VContext.VContext()
    data = Utils._rc4_decrypt_hex(vContext.passKey, encrypted)
    print(data)


if __name__ == "__main__":
    print("test...")
    testEncrypt()
    testDecrypt()
