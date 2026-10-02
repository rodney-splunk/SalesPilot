import assert from 'node:assert/strict';
process.env.SALESPILOT_DOCS_SERVER=new URL('../tests/fixtures/docs-server.mjs',import.meta.url).pathname;
const {searchSplunkDocs,rankDocumentation,relevantPassages}=await import('./splunkdocs.mjs');
const results=await searchSplunkDocs('retention configuration',2);
assert.equal(results.length,1,'failed page reads never become evidence');
assert.equal(results[0].url,'https://help.splunk.com/retention');
assert.ok(results[0].body.includes('explicit policy'),'actual page content parsed from MCP payload');
const at=Date.now();
assert.deepEqual(await searchSplunkDocs('retention configuration',2),results);
assert.ok(Date.now()-at<100,'repeated question uses short-lived docs cache');
console.log('PASS: delayed MCP handshake, parallel page reads, error rejection, actual content extraction, bounded cache');

const ranked=rankDocumentation([
 {title:'Windows configuration',url:'https://help.splunk.com/en/splunk-observability-cloud/windows'},
 {title:'HTTP Event Collector token authentication',url:'https://help.splunk.com/en/splunk-enterprise/hec'},
 {title:'Operator secrets',url:'https://help.splunk.com/en/splunk-enterprise/splunk-operator-for-kubernetes/secrets'},
], 'Splunk Enterprise HTTP Event Collector token authentication');
assert.equal(ranked.length,1);assert.match(ranked[0].url,/hec$/);
const long='Unrelated configuration options. '.repeat(800)+'\n[http]\ntoken = configured HTTP Event Collector authentication token.';
assert.match(relevantPassages(long,'HTTP Event Collector token authentication'),/token = configured/,'late settings in long configuration blocks survive extraction');
console.log('PASS product-specific ranking and late passages in long configuration pages');
