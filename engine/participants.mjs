// Self-introductions are evidence of identity; mentions of other people are not.
const bad = new Set(['thinking','ready','sorry','going','here','happy','glad','sure','fine','doing','just','not','looking','the','a','an','engineer','director','manager','responsible','splunk','cisco','cloud','enterprise','dashboard','data','security']);
export function participantIntro(text, mic = false) {
 const source=String(text||'').trim();
 if (/\b(?:you (?:would|basically) say|for example|my colleague|this is our|let me introduce|meet my)\b/i.test(source)) return null;
 if (/["“][^"”]*(?:my name|i am|i'm|this is)/i.test(source)) return null;
 const m=source.match(/\b(?:my name is|my name's|i am|i'm|this is)\s+(?:(?:actually|really)\s+)?([\p{Lu}][\p{L}\p{M}’'-]+)(?:\s+([\p{Lu}][\p{L}\p{M}’'-]+))?(?=[\s,.!?]|$)/iu)
  || source.match(/^(?:(?:Hi|Hello|Sure|And)[,.]?\s+)*([A-Z][a-z]+)(?:\s+([A-Z][a-z]+))?,\s*(?:the |a |an )?(?:Director|Manager|Engineer|Lead|VP|Head|SE)\b/);
 if(!m || bad.has(m[1].toLowerCase()) || m[1][0] !== m[1][0].toUpperCase())return null;
 const name=[m[1],m[2] && m[2][0] === m[2][0].toUpperCase() ? m[2] : null].filter(Boolean).join(' ');
 const affiliation=source.slice(m.index).match(/\b(?:from|with|at|representing)\s+(?:the\s+)?(Splunk|Cisco|customer(?: side)?|[A-Z][A-Za-z]*(?:\s+(?:Enterprises|Corporation|Inc|Company))?)\b/);
 const organization=affiliation?.[1]||'';
 const explicitSeller=/^(?:Splunk|Cisco)$/i.test(organization);
 const explicitCustomer=/^customer/i.test(organization)||/\b(?:on|from) the customer side\b/i.test(source);
 return {name,organization,side:explicitSeller?'seller':explicitCustomer||organization?'customer':mic?'seller':'unknown'};
}
