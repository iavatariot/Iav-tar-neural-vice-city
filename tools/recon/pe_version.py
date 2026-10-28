import sys,struct,hashlib
for f in sys.argv[1:]:
    b=open(f,'rb').read()
    i=b.find(struct.pack('<I',0xFEEF04BD))
    v='?'
    if i>0:
        ms,ls=struct.unpack('<II',b[i+8:i+16]); v=f"{ms>>16}.{ms&0xffff}.{ls>>16}.{ls&0xffff}"
    pe=struct.unpack('<I',b[0x3c:0x40])[0]; magic=struct.unpack('<H',b[pe+24:pe+26])[0]
    dd=pe+24+(112 if magic==0x20b else 96)
    secoff,secsz=struct.unpack('<II',b[dd+4*8:dd+4*8+8])
    print(f.split('/')[-1], 'ver',v, 'authenticode' if secsz else 'UNSIGNED', 'sha256',hashlib.sha256(b).hexdigest())
