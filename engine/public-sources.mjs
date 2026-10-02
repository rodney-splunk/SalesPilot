import {relevantPassages} from './splunkdocs.mjs';
const cache=new Map();
const approved=new Set(['www.splunk.com']);
export async function publicPricingSources(query) {
 if(process.env.SALESPILOT_LOCAL_ONLY==='1')return [];
 if(!/\b(?:expensive|cheaper|price|pricing|cost|quote|fees?)\b/i.test(query))return [];
 const key=query.toLowerCase().trim();const cached=cache.get(key);if(cached && Date.now()-cached.at<300000)return cached.results;
 const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),5000);
 try {
  const res=await fetch('https://www.splunk.com/en_us/products/pricing.html',{signal:controller.signal});
  if(!res.ok || !approved.has(new URL(res.url||'https://www.splunk.com').hostname) || !/text\/html/i.test(res.headers.get('content-type')||''))return [];
  const html=await res.text();if(html.length>2000000)return [];
  const text=(html.match(/<main\b[^>]*>([\s\S]*?)<\/main>/i)?.[1]||html)
   .replace(/<(script|style|nav|footer)\b[^>]*>[\s\S]*?<\/\1>/gi,' ')
   .replace(/<\/(?:p|div|h[1-6]|li|section)>/gi,'\n\n').replace(/<[^>]+>/g,' ')
   .replace(/&nbsp;|&#160;/g,' ').replace(/&amp;/g,'&').replace(/&quot;/g,'"').replace(/\s+/g,' ').trim();
  const results=text?[{title:'Official Splunk pricing',url:'https://www.splunk.com/en_us/products/pricing.html',body:relevantPassages(text,query)}]:[];
  if(results.length){if(cache.size>=40)cache.delete(cache.keys().next().value);cache.set(key,{at:Date.now(),results});}return results;
 }catch{return [];}finally{clearTimeout(timer);}
}
