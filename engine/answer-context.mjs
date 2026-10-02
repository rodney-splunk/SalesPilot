import {competitors} from './competition.mjs';
export function layeredComparison(text,item,prior=[]){
 if(!item || item.kind!=='competition' || ['answered','deferred'].includes(item.status))return false;
 if(competitors(text).length)return false; // explicit named comparisons route normally
 const last=prior.at(-1);if(last?.questionId!==item.id)return false;
 return /\b(?:specifically|in terms of|what about|how about|i mean|more interested|concerned|for our|for us|our use case|especially|particularly|rather than|not .{0,25}but|we (?:use|ingest|collect|need|want)|our (?:environment|workflow|logs|sources|requirements)|tell me more|how (?:do|does|would) (?:they|that|those)|(?:what|how) .{0,25}(?:ingest\w*|collect\w*|retention))\b/i.test(text);
}
export function comparisonFollowup(query){
 const vendor=competitors(query)[0];
 query=String(query).split('Additional scope:').at(-1).replace(/\bnot (?:pricing|price|cost)\b/gi,'');
 if(/\b(?:ingest\w*|collect\w*|pipeline)\b/i.test(query))return 'Which sources would you need to bring in, and where does collection get difficult today?';
 if(/\b(?:price|pricing|cost|expensive|cheaper)\b/i.test(query))return 'What data volume, retention and operating effort should we include in a like-for-like comparison?';
 if(/\b(?:retention|retain)\b/i.test(query))return 'How long do you need that data available, and what investigations depend on it?';
 return vendor?.probe || (/\b(?:compare|difference|differ|versus)\b/i.test(query) ? 'Which part of your current workflow would you want that comparison to help you decide?' : 'Which part of that would you like us to focus on for your environment?');
}
// Complete records stay in call memory; a short quiet interval only gates publication.
export async function waitForAnswerContext({current,blocked,lastChanged,signal,quietMs=1200}){
 while(current() && (blocked() || Date.now()-lastChanged()<quietMs)){
  await new Promise((resolve,reject)=>{if(signal.aborted)return reject(signal.reason);const stop=()=>{clearTimeout(timer);reject(signal.reason)};const timer=setTimeout(()=>{signal.removeEventListener('abort',stop);resolve()},100);signal.addEventListener('abort',stop,{once:true});});
 }
 return current();
}
