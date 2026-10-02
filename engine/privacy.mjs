// Current-process pseudonyms only. No persistent people registry and no claim of complete DLP.
const identities=new Map();
let contactSequence=0;
const escape=s=>s.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');
export function registerPrivateNames(values){for(const value of values||[]){const name=String(value||'').normalize('NFC').trim();if(name.length>=2&&!/^(?:Splunk|Cisco|Customer|Microphone|Call audio|Speaker \d+)$/i.test(name)&&!identities.has(name))identities.set(name,`[PERSON_${identities.size+1}]`);}}
export function privateText(input){let text=String(input||'').normalize('NFC');const replacements=new Map();
 for(const [name,token] of [...identities].sort((a,b)=>b[0].length-a[0].length)){const re=new RegExp(`(?<![\\p{L}\\p{N}])${escape(name)}(?![\\p{L}\\p{N}])`,'giu');if(re.test(text)){re.lastIndex=0;text=text.replace(re,token);replacements.set(token,name);}}
 const mask=(value,kind)=>{const token=`[${kind}_${++contactSequence}]`;replacements.set(token,value);return token;};
 text=text.replace(/[\p{L}\p{N}._%+-]+@[\p{L}\p{N}.-]+\.[\p{L}]{2,}/giu,v=>mask(v,'EMAIL'));
 text=text.replace(/(?<!\d)(?:\+\d{1,3}[ .-]?)?(?:\(\d{3}\)|\d{3})[ .-]\d{3}[ .-]\d{4}(?!\d)/g,v=>mask(v,'PHONE'));
 text=text.replace(/\+\d[\d(). -]{6,22}\d/g,v=>{const count=v.replace(/\D/g,'').length;return count>=7&&count<=15?mask(v,'PHONE'):v;});
 text=text.replace(/(?<!\d)\d{10,15}(?!\d)/g,v=>mask(v,'PHONE'));
 text=text.replace(/\b(?:Bearer\s+|(?:api[_ -]?key|client[_ -]?secret|password)\s*[:=]\s*)[A-Za-z0-9_./+\-=]{8,}/gi,'[SECRET REMOVED]');
 return {text,restore:output=>{let result=String(output||'');for(const [token,value] of replacements)result=result.split(token).join(value);return result;}};
}
export function publicQuery(query){return privateText(query).text.replace(/\[(?:PERSON|EMAIL|PHONE)_\d+\]/g,' ').replace(/\[SECRET REMOVED\]/g,' ').replace(/\s+/g,' ').trim();}
