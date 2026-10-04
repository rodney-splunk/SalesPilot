import assert from 'node:assert/strict';
import {mkdtempSync,writeFileSync,readFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
const dir=mkdtempSync(join(tmpdir(),'salespilot-credential-bootstrap-'));
const previousInput=process.env.SALESPILOT_CREDENTIAL_INPUT, previousLocal=process.env.SALESPILOT_LOCAL_ONLY;
try {
 process.env.SALESPILOT_CREDENTIAL_INPUT='stdin';delete process.env.SALESPILOT_LOCAL_ONLY;
 writeFileSync(join(dir,'.circuit.json'),JSON.stringify({credential_store:'macos-keychain',client_id:'synthetic-client'}));
 writeFileSync(join(dir,'circuit.mjs'),readFileSync(new URL('./circuit.mjs',import.meta.url)));
 const load=suffix=>import(pathToFileURL(join(dir,'circuit.mjs')).href+'?'+suffix);
 const good=await load('good');
 const pending=good.circuitCredentials();
 assert.equal(good.credentialBootstrapLine('{broken'),false);
 assert.equal(good.credentialBootstrapLine(JSON.stringify({cmd:'provider-credentials',credentials:{client_secret:'synthetic-secret',app_key:'synthetic-key'}})),true);
 const creds=await pending;assert.equal(creds.client_secret,'synthetic-secret');assert.equal(creds.client_id,'synthetic-client');
 assert.equal(await good.circuitCredentials(),creds);
 assert.equal(good.acceptCircuitCredentials({credentials:{client_secret:'replacement',app_key:'replacement'}}),false);
 const rejected=await load('invalid');assert.equal(rejected.acceptCircuitCredentials({credentials:{}}),false);
 await assert.rejects(rejected.circuitCredentials(),/credentials unavailable/);
 const before=await load('before-waiter');assert.equal(before.acceptCircuitCredentials({credentials:{client_secret:'synthetic-secret',app_key:'synthetic-key'}}),true);
 assert.equal((await before.circuitCredentials()).app_key,'synthetic-key');
 process.env.SALESPILOT_LOCAL_ONLY='1';assert.equal(before.acceptCircuitCredentials({credentials:{}}),false);await assert.rejects(before.circuitCredentials(),/Local-only/);
 delete process.env.SALESPILOT_LOCAL_ONLY;delete process.env.SALESPILOT_CREDENTIAL_INPUT;
 const blocked=await load('disabled');assert.equal(blocked.acceptCircuitCredentials({credentials:{client_secret:'synthetic-secret',app_key:'synthetic-key'}}),false);
 console.log('PASS private credential bootstrap: no helper required, cached across requests, invalid/late/local-only/disabled input rejected');
}finally{
 if(previousInput===undefined)delete process.env.SALESPILOT_CREDENTIAL_INPUT;else process.env.SALESPILOT_CREDENTIAL_INPUT=previousInput;
 if(previousLocal===undefined)delete process.env.SALESPILOT_LOCAL_ONLY;else process.env.SALESPILOT_LOCAL_ONLY=previousLocal;
 rmSync(dir,{recursive:true,force:true});
}
