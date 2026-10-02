import assert from 'node:assert/strict';
import {mkdtempSync,writeFileSync,mkdirSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
const dir=mkdtempSync(join(tmpdir(),'salespilot-rag-'));
process.env.SALESPILOT_DOCS_DIR=join(dir,'docs');
process.env.SALESPILOT_RAG_INDEX=join(dir,'index.json');
mkdirSync(process.env.SALESPILOT_DOCS_DIR);
writeFileSync(join(process.env.SALESPILOT_DOCS_DIR,'retention.txt'),'The reference policy permits retaining logs for 30 days. Configure retention explicitly.');
writeFileSync(join(process.env.SALESPILOT_DOCS_DIR,'tiny.txt'),'SOC 2 Type II.');
globalThis.fetch=async()=>{throw Error('Embedding service unavailable');};
const {index,search,indexIfStale}=await import('./rag.mjs');
try {
 const indexed=await index();
 assert.equal(indexed.files,2);assert.equal(indexed.chunks,2,'short factual references are indexed');
 const hits=await search('retaining logs');
 assert.equal(hits[0]?.file,'retention.txt','local references work without embeddings');
 assert.equal((await search('kubernetes autoscaling')).length,0,'unrelated questions do not retrieve generic passages');
 rmSync(join(process.env.SALESPILOT_DOCS_DIR,'retention.txt'));
 assert.equal((await indexIfStale()).reindexed,true);
 assert.equal((await search('retaining logs')).length,0,'removed documents stop being cited');
 console.log('PASS local retrieval without embeddings, short references, relevance filtering, deleted-source refresh');
} finally {rmSync(dir,{recursive:true,force:true});}
