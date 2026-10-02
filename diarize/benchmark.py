#!/usr/bin/env python3
"""Local annotated benchmark. No network; no voice/name catalog. Labels are test ground truth only."""
import argparse,json,os,subprocess,time,wave,random
from pathlib import Path
import numpy as np
p=argparse.ArgumentParser();p.add_argument('manifest');p.add_argument('--output',required=True);args=p.parse_args()
manifest=json.loads(Path(args.manifest).read_text());base=Path(args.manifest).parent
reports={}
for engine,flags in [('whole-turn',['--legacy']),('window-aware',[])]:
 proc=subprocess.Popen([str(Path(__file__).parent/'.venv/bin/python'),str(Path(__file__).parent/'embed.py'),*flags],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True)
 confusion=extra=missed_mixed=unsafe_mixed=0;unnamed=0.;latencies=[];results=[];mapping={};found=set();expected=set()
 try:
  for n,item in enumerate(manifest['clips']):
   path=base/item['wav'];tic=time.perf_counter();proc.stdin.write(json.dumps({'id':n,'wav':str(path)})+'\n');proc.stdin.flush();result=json.loads(proc.stdout.readline());elapsed=(time.perf_counter()-tic)*1000;latencies.append(elapsed)
   with wave.open(str(path)) as wav:duration=wav.getnframes()/wav.getframerate()
   label=item.get('speaker');cluster=result.get('cluster')
   if label is not None:expected.add(label)
   if cluster is not None:
    found.add(cluster)
    if item.get('seed'):mapping[cluster]=label
    elif label is not None and mapping.get(cluster)!=label:confusion+=1
   elif label is not None:unnamed+=duration
   if item.get('mixed') and result.get('reason')!='mixed':missed_mixed+=1
   if item.get('mixed') and cluster is not None:unsafe_mixed+=1
   results.append({'case':item['case'],'expected':label,'cluster':cluster,'reason':result.get('reason'),'milliseconds':round(elapsed,1),'durationSeconds':round(duration,3)})
  sorted_ms=sorted(latencies);at=lambda f:round(sorted_ms[min(len(sorted_ms)-1,int(np.ceil(len(sorted_ms)*f))-1)],1)
  reports[engine]={'speakerConfusions':confusion,'extraSpeakers':max(0,len(found)-len(expected)),'missingSpeakers':max(0,len(expected)-len(set(mapping.values()))),'unnamedSeconds':round(unnamed,3),'unflaggedMixedTurns':missed_mixed,'unsafeMixedAssignments':unsafe_mixed,'p50Ms':at(.5),'p95Ms':at(.95),'cases':results}
 finally:proc.stdin.close();proc.terminate();proc.wait(timeout=5)
Path(args.output).write_text(json.dumps({'datasetKind':manifest.get('kind','annotated-local'),'scope':'Speaker assignments; separate ASR/name-spelling benchmark required','engines':reports},indent=2));print(json.dumps({k:{a:b for a,b in v.items() if a!='cases'} for k,v in reports.items()},indent=2))
