#!/usr/bin/python
import VContext
import Utils


def testEncrypt():
    data = 'zanyue$2012'
    vContext = VContext.VContext()
    enrypted = Utils._rc4_encrypt_hex(vContext.MY_KEY, data)
    print(enrypted)


def testDecrypt():
    encrypted = '05a90b9d7fcd2449928041'
    vContext = VContext.VContext()
    data = Utils._rc4_decrypt_hex(vContext.MY_KEY, encrypted)
    print(data)


if __name__ == "__main__":
    print("test...")
    testEncrypt()
    testDecrypt()
