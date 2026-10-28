import sys,struct,hashlib
# Versione PE: chiave UTF-16 VS_VERSION_INFO + firma 0xFEEF04BD (dwStrucVersion 0x10000).
for f in sys.argv[1:]:
    b=open(f,'rb').read()
    key='VS_VERSION_INFO'.encode('utf-16le'); i=0; v='?'
    while True:
        i=b.find(key,i)
        if i<0: break
        j=b.find(struct.pack('<I',0xFEEF04BD),i,i+96)
        if j>0 and struct.unpack('<I',b[j+4:j+8])[0]==0x10000:
            ms,ls=struct.unpack('<II',b[j+8:j+16]); v=f"{ms>>16}.{ms&0xffff}.{ls>>16}.{ls&0xffff}"; break
        i+=1
    pe=struct.unpack('<I',b[0x3c:0x40])[0]; magic=struct.unpack('<H',b[pe+24:pe+26])[0]
    dd=pe+24+(112 if magic==0x20b else 96)
    secoff,secsz=struct.unpack('<II',b[dd+32:dd+40])
    print(f.split('/')[-1], 'ver',v, 'authenticode' if secsz else 'UNSIGNED', 'sha256',hashlib.sha256(b).hexdigest())
