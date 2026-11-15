#!/usr/bin/env python3
"""Lists English text in lib/ that has no French in lib/fr.dart yet.

Run: python3 tools/i18n_scan.py   (prints file:line and the English, as a fr.dart key)
It guesses which strings are shown on screen, so some lines are code, not words: skip those."""
import re, sys, os
root=sys.argv[1] if len(sys.argv) > 1 else 'lib'
out=[]
def lits(src):
    i=0;n=len(src)
    res=[]  # (start,end,value)
    while i<n:
        c=src[i]
        if src.startswith('//',i):
            j=src.find('\n',i); i=n if j<0 else j; continue
        if src.startswith('/*',i):
            j=src.find('*/',i); i=n if j<0 else j+2; continue
        if c in "'\"":
            raw = i>0 and src[i-1]=='r'
            q=c
            if src.startswith(q*3,i):
                j=src.find(q*3,i+3); res.append((i,j+3,None)); i=j+3; continue
            j=i+1; buf=''; depth=0
            while j<n:
                ch=src[j]
                if ch=='\\' and not raw: buf+=src[j:j+2]; j+=2; continue
                if ch=='$' and not raw and src[j+1:j+2]=='{':
                    # skip interpolation braces
                    k=j+2; d=1
                    while k<n and d:
                        if src[k]=='{': d+=1
                        elif src[k]=='}': d-=1
                        elif src[k] in "'\"":
                            qq=src[k]; k+=1
                            while k<n and src[k]!=qq:
                                if src[k]=='\\': k+=1
                                k+=1
                        k+=1
                    buf+='\x00'+src[j:k]+'\x01'; j=k; continue
                if ch==q: break
                buf+=ch; j+=1
            res.append((i,j+1,buf)); i=j+1; continue
        i+=1
    return res
for dp,_,fs in os.walk(root):
    for f in fs:
        if not f.endswith('.dart'): continue
        p=os.path.join(dp,f); s=open(p).read()
        L=lits(s)
        # join adjacent
        k=0
        while k<len(L):
            st,en,v=L[k]
            if v is None: k+=1; continue
            parts=[v]; e=en
            while k+1<len(L) and L[k+1][2] is not None and s[e:L[k+1][0]].strip()=='' :
                k+=1; parts.append(L[k][2]); e=L[k][1]
            out.append((p,s[:st].count('\n')+1,''.join(parts)))
            k+=1
bad_ctx = None
bad_val = re.compile(r"^(https?:|/|\.|\w+://|[a-z0-9_.\-]+$|[A-Z_0-9]+$|#|\$)")
def norm(v):
    v = re.sub(r'\x00.*?\x01', '{}', v, flags=re.S)
    v = re.sub(r'\$[A-Za-z_]\w*', '{}', v)
    return v.replace("\\'", "'").replace('\\"', '"').replace('\\n', '\n').replace('\\$', '$').replace('\\\\', '\\')
have = set()
fr = open(os.path.join(root, 'fr.dart')).read()
for m in re.finditer(r"^  '((?:[^'\\]|\\.)*)': ", fr, re.M):
    have.add(m.group(1).replace("\\'", "'").replace('\\n', '\n').replace('\\$', '$').replace('\\\\', '\\'))
seen = set()
for p, ln, v in out:
    if p.endswith(('fr.dart', 'i18n.dart')): continue
    t = norm(v)
    if t in have or t in seen: continue
    if not re.search(r'[A-Za-z]{2}', t) or bad_val.search(t): continue
    if ' ' not in t.strip() and not re.match(r'^[A-Z][a-z]+', t): continue
    if re.search(r'\b(pm |am start|dumpsys|settings (put|get)|cmd |appops|logcat|svc |input keyevent)', t): continue
    seen.add(t)
    print(f"{p}:{ln}\t{t!r}")
