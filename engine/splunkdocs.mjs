import {publicQuery} from './privacy.mjs';
// Read actual official documentation, with a bounded MCP handshake and no search-snippet evidence.
import { spawn } from 'node:child_process';
const SERVER = process.env.SALESPILOT_DOCS_SERVER || `${process.env.HOME}/.config/ghost/mcp-servers/dist/servers/splunk-docs/server.js`;
const ALLOWED = new Set(['help.splunk.com', 'docs.splunk.com', 'dev.splunk.com', 'lantern.splunk.com']);
function officialURL(value) {
  try { const url = new URL(value); return url.protocol === 'https:' && ALLOWED.has(url.hostname); } catch { return false; }
}
function mcpCall(name, args, timeoutMs = 5000) {
  return new Promise(resolve => {
    const proc = spawn(process.execPath, [SERVER], { stdio: ['pipe', 'pipe', 'ignore'] });
    let done = false, buffer = '';
    const finish = value => {
      if (done) return;
      done = true; clearTimeout(timer);
      try { proc.stdin.end(); proc.kill(); } catch {}
      resolve(value);
    };
    const timer = setTimeout(() => finish(null), timeoutMs);
    const send = message => {
      if (done) return;
      try { proc.stdin.write(JSON.stringify(message) + '\n'); } catch { finish(null); }
    };
    proc.on('error', () => finish(null));
    proc.stdin.on('error', () => finish(null));
    proc.on('exit', () => finish(null));
    proc.stdout.on('data', chunk => {
      buffer += chunk;
      let index;
      while ((index = buffer.indexOf('\n')) >= 0) {
        const line = buffer.slice(0, index); buffer = buffer.slice(index + 1);
        let message; try { message = JSON.parse(line); } catch { continue; }
        if (message.id === 1) {
          if (message.error) { finish(null); continue; }
          send({ jsonrpc: '2.0', method: 'notifications/initialized' });
          send({ jsonrpc: '2.0', id: 2, method: 'tools/call', params: { name, arguments: args } });
        }
        if (message.id === 2) {
          if (message.error || message.result?.isError) { finish(null); continue; }
          const raw = (message.result?.content || []).filter(c => c.type === 'text').map(c => c.text).join('\n');
          let result; try { result = JSON.parse(raw); } catch { finish(null); continue; }
          finish(result?.error ? null : result);
        }
      }
    });
    send({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2024-11-05', capabilities: {}, clientInfo: { name: 'salespilot', version: '2' } } });
  });
}
export function relevantPassages(content, query, maxChars = 6500) {
  const ignored = new Set(['splunk','enterprise','cloud','product','context','can','could','does','how','what','the','our','your','for','this','that','with']);
  const expanded=query + (/ingest|data in/i.test(query)?' data inputs collect forwarder syslog HTTP Event Collector':'') + (/difference|versus/i.test(query)&&!/ingest/i.test(query)?' hosted managed service infrastructure deployment':'');
  const words = [...new Set(expanded.toLowerCase().match(/[a-z0-9]{3,}/g) || [])].filter(w => !ignored.has(w));
  const pieces = [];
  for (const paragraph of String(content || '').split(/\n\s*\n|(?=^##? )/m)) {
    // Configuration reference pages can contain a single enormous preformatted block.
    // Rank bounded overlapping sections so the relevant option is not lost at the end of it.
    if (paragraph.length <= 1100) pieces.push(paragraph);
    else for (let i=0;i<paragraph.length;i+=850) pieces.push(paragraph.slice(i,i+1000));
  }
  const hec = /\b(?:HEC|HTTP Event Collector)\b/i.test(query);
  const sections = pieces.map((text, index) => ({ text, index,
    score: words.reduce((score, w) => score + (text.toLowerCase().includes(w) ? 1 : 0), 0)
      + (hec && /HTTP Event Collector|\[http\]/i.test(text) ? 5 : 0)
      + (/difference|versus/i.test(query)&&!/ingest/i.test(query)&&/cloud.based service|customer.managed|centrally and uniformly|delivers the benefits/i.test(text)?12:0) }));
  const chosen = sections.sort((a,b) => b.score - a.score).slice(0, Math.max(1,Math.floor(maxChars/1100))).sort((a,b) => a.index - b.index);
  return chosen.map(x => x.text).join('\n\n').slice(0,maxChars);
}
const cache = new Map();
export function documentationQuery(query) {
  let text = String(query).replace(/\b(?:on this call(?: right now)?|on the call(?: right now)?)\b/gi, ' ').replace(/Product context:/gi, '').replace(/\b(?:can|could|does|do|is|are|will|would|we|you|our|your|the|a|an|please|tell me|need to know|whether|how|what)\b/gi, ' ').replace(/\s+/g, ' ').trim();
  if (/\b(?:HEC|HTTP Event Collector)\b/i.test(text)) {
    text = '"HTTP Event Collector" ' + text.replace(/\b(?:HEC|HTTP Event Collector|Splunk Enterprise|Splunk)\b/gi, '').trim();
  }
  return text || String(query);
}
export function rankDocumentation(results, query) {
  const words = [...new Set(documentationQuery(query).toLowerCase().match(/[a-z0-9]{3,}/g) || [])].filter(w => !['splunk','enterprise','cloud','product','context'].includes(w));
  const enterprise = /\bsplunk enterprise\b/i.test(query) && !/\bsplunk cloud\b/i.test(query);
  const hec = /\b(?:HEC|HTTP Event Collector)\b/i.test(query);
  return results.filter(r => officialURL(r.url)).filter(r => {
    const asksOnCall=/\bSplunk[ -]+On[ -]?Call\b|\b(?:on[ -]?call)\s+(?:product|dashboard|integration|routing)\b/i.test(query);
    if(!asksOnCall && /on[ -]?call/i.test(`${r.url} ${r.title || ''}`))return false;
    if (enterprise && /splunk-observability-cloud|splunk-cloud-platform/.test(r.url)) return false;
    if(!/observability/i.test(query) && /splunk-observability-cloud/i.test(r.url))return false;
    if(!/itsi|it service intelligence/i.test(query) && /splunk-it-service-intelligence/i.test(r.url))return false;
    if(!/authorize|roles|permission|configuration/i.test(query)&&/authorize\.conf|configuration-file-reference/i.test(r.url))return false;
    if(!/edge processor/i.test(query) && /edge-processor/i.test(r.url))return false;
    if(!/soar/i.test(query) && /splunk-soar/i.test(r.url))return false;
    if(!/enterprise security/i.test(query) && /splunk-enterprise-security(?:-|\/)/i.test(r.url))return false;
    if(!/upgrade|version|upcoming|change/i.test(query) && /upcoming_changes|release-notes/i.test(r.url))return false;
    if (!/kubernetes|operator/i.test(query) && /splunk-operator-for-kubernetes/.test(r.url)) return false;
    return true;
  }).map((r, index) => {
    const title = String(r.title || '').toLowerCase();
    const summary = `${r.url} ${r.description || ''}`.toLowerCase();
    const score = words.reduce((sum,w) => sum + (title.includes(w) ? 4 : 0) + (summary.includes(w) ? 1 : 0),0)
      + (hec && /http event collector|\bhec\b/i.test(title) ? 12 : 0);
    return {r,index,score};
  }).sort((a,b) => b.score-a.score || a.index-b.index).map(x => x.r);
}
export async function searchSplunkDocs(query, limit = 2) {
 if(process.env.SALESPILOT_LOCAL_ONLY==='1')return [];
  query=publicQuery(query);
  if(!query)return [];
  limit = Math.max(1, Math.min(4, limit));
  const key = `${limit}:${query.toLowerCase().trim()}`;
  const cached = cache.get(key);
  if (cached && Date.now() - cached.at < 5 * 60 * 1000) return cached.results;
  const comparison=/splunk enterprise/i.test(query)&&/splunk cloud/i.test(query);
  const ingestion=/ingest|data in|forwarder|syslog/i.test(query);
  const windowsSyslog=/windows/i.test(query)&&/syslog/i.test(query);
  const queries=comparison ? (ingestion ? ['Splunk Cloud Platform get data in forwarders HTTP Event Collector','Splunk Enterprise get data in forwarders syslog'] : ['Splunk Cloud Platform managed service overview','Splunk Enterprise deployment on premises overview']) : windowsSyslog ? ['Splunk Cloud Platform monitor Windows event log data','Splunk Cloud Platform syslog data forwarder'] : [documentationQuery(query)];
  const searches=await Promise.all(queries.map(q=>mcpCall('search_splunk_docs',{query:q,count:12})));
  const found={results:searches.flatMap(s=>s?.results||[])};
  if (!Array.isArray(found?.results)) return [];
  const ranked=rankDocumentation(found.results, query).filter((r,i,arr)=>arr.findIndex(x=>x.url===r.url)===i);
  const queryFirsts=searches.map(s=>rankDocumentation(s?.results||[],query)[0]).filter(Boolean);
  const preferred=comparison ? [ranked.find(r=>/splunk-cloud-platform|SplunkCloud/i.test(r.url)),ranked.find(r=>/splunk-enterprise|Documentation\/Splunk\//i.test(r.url))].filter(Boolean) : [];
  // Read authoritative topic anchors live; never substitute canned product claims.
  const anchors=comparison ? [{title:'Splunk Cloud Platform Service Details',url:'https://help.splunk.com/en/splunk-cloud-platform/get-started/service-terms-and-policies/10.6/information-about-the-service/splunk-cloud-platform-service-details'}] : windowsSyslog ? [{title:'Monitor Windows event log data with Splunk Cloud Platform',url:'https://help.splunk.com/en/splunk-cloud-platform/get-started/get-data-in/10.5.2605/get-windows-data/monitor-windows-event-log-data-with-splunk-cloud-platform'}] : ingestion && /splunk enterprise/i.test(query) ? [{title:'What data can I index?',url:'https://help.splunk.com/en/splunk-enterprise/get-started/get-data-in/9.2/introduction/what-data-can-i-index'}] : [];
  const selected=[...anchors,...preferred,...queryFirsts,...ranked].filter((r,i,arr)=>arr.findIndex(x=>x.url===r.url)===i).slice(0,limit);
  const results = await Promise.all(selected.map(async r => {
    const page = await mcpCall('read_splunk_doc', { url: r.url });
    if (!page?.content?.trim()) return null;
    return { title: page.title || r.title || '', url: r.url, body: relevantPassages(page.content, query) };
  }));
  const seenBodies = new Set();
  const readable = results.filter(Boolean).filter(r => {
    if (seenBodies.has(r.body)) return false;
    seenBodies.add(r.body); return true;
  });
  if (readable.length) {
    if (cache.size >= 40) cache.delete(cache.keys().next().value);
    cache.set(key,{at:Date.now(), results:readable});
  }
  return readable;
}
