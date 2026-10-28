import sys,os,struct
MAGIC=0x5A6F12E1
for f in sys.argv[1:]:
    sz=os.path.getsize(f); n=min(sz,1<<20)
    with open(f,'rb') as fh: fh.seek(sz-n); t=fh.read()
    le=struct.pack('<I',MAGIC); be=struct.pack('>I',MAGIC)
    print('==',os.path.basename(f),'size',sz)
    print(' LE hits (offset from EOF):',[n-i for i in range(len(t)) if t.startswith(le,i)][:5])
    print(' BE hits:',[n-i for i in range(len(t)) if t.startswith(be,i)][:5])
    print(' last 64 bytes:',t[-64:].hex())
    j=t.rfind(le)
    if j>=0:
        # v8+ layout: guid(16) enc(1) magic(4) ver(4) off(8) size(8) hash(20) [comp names 32*N]
        g=t[j-17:j-1]; enc=t[j-1]; ver,off,isz=struct.unpack('<IQQ',t[j+4:j+24])
        tail=n-(j+44)
        print(' keyGuid',g.hex(),'encryptedIndex',enc,'version',ver,'indexOffset',off,'indexSize',isz,'bytesAfterHash',tail)
        names=t[j+44:j+44+tail]
        print(' compression names:',[names[k:k+32].split(b'\0')[0] for k in range(0,len(names),32)])
