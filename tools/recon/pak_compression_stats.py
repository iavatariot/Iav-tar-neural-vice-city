import sys,collections
exec(open(sys.argv[2]).read().split('# --- extraction helper')[0].replace("f=sys.argv[1]; out=sys.argv[2] if len(sys.argv)>2 else None","f=sys.argv[1]; out=None").replace("print(json.dumps","(lambda *a,**k:None)(json.dumps"))
c=collections.Counter(); ex={}
for p,eo in files.items():
    e=dec(eo); k=(p.rsplit('.',1)[-1], cnames[e['cm']-1] if e['cm'] else 'None'); c[k]+=1; ex.setdefault(k,p)
for k,v in c.most_common(): print(k,v,ex[k])
