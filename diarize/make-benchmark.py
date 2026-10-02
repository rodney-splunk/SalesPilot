#!/usr/bin/env python3
import argparse,json,wave,shutil
from pathlib import Path
import numpy as np
p=argparse.ArgumentParser();p.add_argument('fixtures');p.add_argument('output');a=p.parse_args();src=Path(a.fixtures);out=Path(a.output);out.mkdir(parents=True,exist_ok=True);clips=[]
def read(n):
 with wave.open(str(src/f'{n}.wav')) as w:return np.frombuffer(w.readframes(w.getnframes()),dtype='<i2').astype(np.float32)/32768,w.getframerate()
def add(case,signal,sr,speaker=None,seed=False,mixed=False):
 name=f'{len(clips):02}-{case}.wav'
 with wave.open(str(out/name),'wb') as w:w.setnchannels(1);w.setsampwidth(2);w.setframerate(sr);w.writeframes((np.clip(signal,-1,1)*32767).astype('<i2').tobytes())
 clips.append({'case':case,'wav':name,'speaker':speaker,'seed':seed,'mixed':mixed})
for i in range(4):signal,sr=read(i);add('introduction-'+str(i),signal,sr,str(i),True)
for i in range(4):
 signal,sr=read(i+4);add('repeat-'+str(i),signal,sr,str(i));add('quiet-'+str(i),signal*.25,sr,str(i));noise=np.random.default_rng(42+i).normal(0,.003,len(signal));add('room-noise-'+str(i),signal+noise,sr,str(i))
x,sr=read(5);y,_=read(6);add('sequential-speakers',np.concatenate([x,y]),sr,mixed=True);add('late-speaker-change',np.concatenate([x,x,y]),sr,mixed=True)
length=min(len(x),len(y));add('genuine-overlap',(x[:length]+y[:length])*.5,sr,mixed=True)
add('short-acknowledgment',x[:int(sr*.6)],sr,'1');add('silence',np.zeros(sr*3),sr)
(out/'manifest.json').write_text(json.dumps({'kind':'synthetic annotated stress audio; not natural-call certification','clips':clips},indent=2));print(out/'manifest.json')
