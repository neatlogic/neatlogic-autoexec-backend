def _rc4(key, data):
    x = 0
    box = list(range(256))
    for i in range(256):
        x = (x + box[i] + ord(key[i % len(key)])) % 256
        box[i], box[x] = box[x], box[i]
    x = y = 0
    out = bytearray()
    for by in data:
        x = (x + 1) % 256
        y = (y + box[x]) % 256
        box[x], box[y] = box[y], box[x]
        out.append(by ^ box[(box[x] + box[y]) % 256])
    return bytes(out)


key = 'kikd86ksdf8k'
data = b'my data is data and fff uuu'

en = _rc4(key, data)
print(en)
plaint = _rc4(key, en)

print(plaint)
