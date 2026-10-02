// Carry only short continuations of the sole established voice on this channel.
// Never turn proximity into evidence on a multi-person or overlapping channel.
export function continuationCluster(turn,previous,knownClusters,reason){
 if(!['short','no_audio'].includes(reason)||!previous||turn.me!==previous.me||knownClusters.size!==1||previous.clusterId==null||!knownClusters.has(previous.clusterId)||['ambiguous','mixed'].includes(previous.speakerStatus))return null;
 if(!Number.isFinite(turn.startedAt)||!Number.isFinite(previous.endedAt))return null;
 const gap=turn.startedAt-previous.endedAt;if(gap<0||gap>1.5)return null;
 if(!/^(?:(?:yes|yeah|yep|no|right|okay|ok|exactly|correct|sure|thanks|thank you|all right)[,.!\s]*)+$/i.test(turn.text))return null;
 return previous.clusterId;
}
