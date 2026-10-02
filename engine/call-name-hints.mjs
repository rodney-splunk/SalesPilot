export function addressedName(text){const m=String(text).match(/\b(?:speak|talk|meet|meeting)\s+with you(?:\s+today)?\s*,\s*([\p{Lu}][\p{L}’'-]+(?:\s+[\p{Lu}][\p{L}’'-]+)?)(?=[.!?,])/u);return m?.[1]||null;}
export function statedRole(text){const m=String(text).match(/\b(?:i(?:'m| am)\s+(?:currently\s+)?|i\s+)(leading|managing|heading|lead|manage|head)\s+((?:the\s+)?(?:SOC|security|IT|engineering|operations)[\w -]{0,35}?)(?=\s+(?:of|with|at|for)|[,.!?]|$)/i);return m?`${m[1]} ${m[2]}`.trim():null;}
export function normalizeRepGreeting(text,repName,knownNames=[]){if(!/^Rodney\b/i.test(repName||''))return text;if(knownNames.some(n=>/^(?:Ronny|Grani|Rodni)\b/i.test(n)))return text;return String(text).replace(/\b(thank you|thanks|hi|hello|hey)[, ]+(Ronny|Grani|Rodni)(?=[,.!\s]|$)/ig,(_,greeting)=>`${greeting}, Rodney`);}

// Prep establishes spelling and expected attendance, never a voice assignment.
export function prepPeople(prep='') {
 const rows=[...String(prep).matchAll(/^\s*(?:people|attendees?|participants?|on the call|contacts?|name spellings?)\s*:\s*(.+)$/gim)].flatMap(m=>m[1].split(/[;\n]|,\s*(?=[\p{Lu}][\p{L}’'-]+\s+[\p{Lu}])/u));
 for(const m of String(prep).matchAll(/\b(?:customer|participant|attendee|contact|rep|host)(?:’s|'s)? name (?:is|:)\s*([\p{Lu}][\p{L}\p{M}’'-]+(?:\s+[\p{Lu}][\p{L}\p{M}’'-]+){1,2})(?=[,.!?;]|$)/gu))rows.push(m[1]);
 return rows.map(row=>{row=row.trim();const m=row.match(/^([\p{Lu}][\p{L}\p{M}’'-]+(?:\s+(?:(?:de|van|von|al|bin)\s+)?[\p{Lu}][\p{L}\p{M}’'-]+){0,3})(?=\s*[,(:—–-]|$)/u);if(!m)return null;const name=m[1];const role=row.slice(m[0].length).replace(/^[\s,(:—–-]+|[)]+$/g,'').trim();return {name,role,side:/\b(?:Splunk|Cisco|seller|SE)\b/i.test(role)?'seller':/\bcustomer\b/i.test(role)?'customer':'unknown',nameEvidence:'Call prep; voice not yet confirmed'};}).filter(Boolean).filter((p,i,a)=>a.findIndex(x=>x.name===p.name)===i).slice(0,12);
}
function nameDistance(a,b){const row=Array.from({length:b.length+1},(_,i)=>i);for(let i=1;i<=a.length;i++){let prev=row[0];row[0]=i;for(let j=1;j<=b.length;j++){const old=row[j];row[j]=Math.min(row[j]+1,row[j-1]+1,prev+(a[i-1]===b[j-1]?0:1));prev=old;}}return row[b.length];}
export function reconcilePreparedName(heard,people) {
 const exact=people.find(p=>p.name.toLowerCase()===String(heard).toLowerCase());if(exact)return exact.name;
 const parts=String(heard).split(/\s+/);
 if(parts.length===1){const matches=people.filter(p=>nameDistance(p.name.split(/\s+/)[0].toLowerCase(),parts[0].toLowerCase())<=1);return matches.length===1?matches[0].name:heard;}
 const matches=people.filter(p=>{const ep=p.name.split(/\s+/);return ep.length===parts.length&&ep.length>1&&ep.at(-1).toLowerCase()===parts.at(-1).toLowerCase()&&ep[0][0].toLowerCase()===parts[0][0].toLowerCase()&&nameDistance(ep[0].toLowerCase(),parts[0].toLowerCase())<=2;});
 return matches.length===1?matches[0].name:heard;
}
