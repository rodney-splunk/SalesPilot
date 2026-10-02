// Energy activity is a conservative timing gate, never speaker identity evidence.
export class AudioActivity {
 constructor(){this.channels=new Map();}
 update(event,now=Date.now()/1000){
  if(!['you','customer'].includes(event.speaker)||typeof event.active!=='boolean'||!Number.isFinite(event.at)||!Number.isFinite(event.voicedAt)||event.at>now+5||event.at<now-10||event.voicedAt>event.at+.1)return false;
  const old=this.channels.get(event.speaker);if(old&&event.at<=old.at)return false;
  this.channels.set(event.speaker,{at:event.at,voicedAt:Math.max(old?.voicedAt||0,event.voicedAt),active:event.active});return true;
 }
 blocked(turn,now=Date.now()/1000){
  if(!turn && this.channels.size)return true;
  for(const channel of this.channels.values()){
   if(channel.active&&now-channel.at<3)return true;
   if(turn && now-channel.at<1.5 && (!Number.isFinite(turn.endedAt)||channel.voicedAt>turn.endedAt+.15))return true;
  }
  return false;
 }
}
