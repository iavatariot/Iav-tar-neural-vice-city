import sys,os,struct,collections,json
f=sys.argv[1]; out=sys.argv[2] if len(sys.argv)>2 else None
fh=open(f,'rb'); sz=os.path.getsize(f)
fh.seek(sz-221); foot=fh.read(221)
assert struct.unpack_from('<I',foot,17)[0]==0x5A6F12E1
encidx=foot[16]; ver,ioff,isz=struct.unpack_from('<IQQ',foot,21)
cnames=[foot[61+k:61+k+32].split(b'\0')[0].decode() for k in range(0,160,32)]
def rd(off,n): fh.seek(off); return fh.read(n)
class R:
    def __init__(s,b): s.b=b; s.p=0
    def u(s,fmt):
        v=struct.unpack_from('<'+fmt,s.b,s.p); s.p+=struct.calcsize('<'+fmt); return v if len(v)>1 else v[0]
    def fs(s):
        n=s.u('i')
        if n==0: return ''
        if n>0: v=s.b[s.p:s.p+n-1].decode('latin1'); s.p+=n; return v
        n=-n; v=s.b[s.p:s.p+2*(n-1)].decode('utf-16le'); s.p+=2*n; return v
r=R(rd(ioff,isz))
mount=r.fs(); num=r.u('i'); seed=r.u('Q')
if r.u('I'): r.u('qq'); r.p+=20
hfd=r.u('I'); fdo=fds=None
if hfd: fdo,fds=r.u('qq'); r.p+=20
esz=r.u('i'); enc=r.b[r.p:r.p+esz]; r.p+=esz
nfiles=r.u('i')
def dec(o):
    e=R(enc); e.p=o; v=e.u('I')
    bs=(v&0x3f)
    bs = e.u('I') if bs==0x3f else bs<<11
    nblk=(v>>6)&0xffff; crypt=(v>>22)&1; cm=(v>>23)&0x3f
    off=e.u('I') if v&(1<<31) else e.u('Q')
    usz=e.u('I') if v&(1<<30) else e.u('Q')
    csz=(e.u('I') if v&(1<<29) else e.u('Q')) if cm else usz
    return dict(off=off,usz=usz,csz=csz,cm=cm,crypt=crypt,nblk=nblk)
files={}
if hfd:
    d=R(rd(fdo,fds)); nd=d.u('i')
    for _ in range(nd):
        dn=d.fs(); nf=d.u('i')
        for _ in range(nf):
            fn=d.fs(); eo=d.u('i'); files[dn+fn]=eo
stats=collections.Counter(); crypt=0; ext=collections.Counter(); tot_u=0
for p,eo in files.items():
    if eo<0: stats['nonencoded']+=1; continue
    e=dec(eo); stats[cnames[e['cm']-1] if e['cm'] else 'None']+=1; crypt+=e['crypt']; tot_u+=e['usz']
    ext[os.path.splitext(p)[1].lower()]+=1
print(json.dumps(dict(file=os.path.basename(f),version=ver,encryptedIndex=encidx,mount=mount,entries=num,listed=len(files),nonEncodedFiles=nfiles,encryptedEntries=crypt,compression=stats,uncompressedGB=round(tot_u/2**30,2),topExt=ext.most_common(12)),indent=0))
if out:
    with open(out,'w') as o:
        for p in sorted(files): o.write(mount+p+'\n')

# --- extraction helper: python3 pakidx.py PAK OUTLIST extract <relpath> <dest>
import zlib
def entry_header_size(cm,nblk):
    # FPakEntry header in data: off(8) csz(8) usz(8) cm(4) hash(20) [nblk(4) + 16*nblk] encrypted(1) blocksize(4)
    return 8+8+8+4+20+((4+16*nblk) if cm else 0)+1+4
if len(sys.argv)>4 and sys.argv[3]=='extract':
    rel=sys.argv[4]; key=rel[len(mount):] if rel.startswith(mount) else rel
    e=dec(files[key])
    e2=R(enc); e2.p=files[key]; v=e2.u('I')
    bs=(v&0x3f); bs=e2.u('I') if bs==0x3f else bs<<11
    e2.u('I') if v&(1<<31) else e2.u('Q'); e2.u('I') if v&(1<<30) else e2.u('Q')
    if e['cm']: e2.u('I') if v&(1<<29) else e2.u('Q')
    hs=entry_header_size(e['cm'],e['nblk'])
    method=cnames[e['cm']-1] if e['cm'] else 'None'
    if not e['cm']:
        data=rd(e['off']+hs,e['usz'])
    else:
        # blocks: if nblk==1 single block of csz; else sizes listed
        if e['nblk']==1: sizes=[e['csz']]
        else: sizes=[e2.u('I') for _ in range(e['nblk'])]
        if method!='Zlib': print('COMPRESSION',method,'- not decodable here'); sys.exit(2)
        pos=e['off']+hs; out=b''
        for s in sizes: out+=zlib.decompress(rd(pos,s)); pos+=s
        data=out
    open(sys.argv[5],'wb').write(data); print('ok',method,len(data))
