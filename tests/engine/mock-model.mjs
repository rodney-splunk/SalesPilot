// Test-only transport. Exercises the real engine with a deliberately slow model and no network.
globalThis.fetch = async (_url, options = {}) => {
  const request = JSON.parse(options.body || '{}');
  const system = request.messages?.[0]?.content || '';
  if (/summarizing a live sales discovery call/i.test(system)) return Response.json({message:{content:JSON.stringify({recap:"Synthetic analysts collect firewall logs for investigations. No next step was agreed.",next_steps:[]})}});
  if (/summariz/i.test(system)) return Response.json({message:{content:'A fixture conversation is in progress.'}});
  if (/people|introduced themselves/i.test(system) && !/top-performing/.test(system)) return Response.json({message:{content:'{"people":[]}'}});
  await new Promise(resolve => setTimeout(resolve, 1200));
  const coverage = Object.fromEntries(['metrics','economic_buyer','decision_criteria','decision_process','paper_process','identify_pain','champion','competition'].map(id => [id,'open']));
  return Response.json({message:{content:JSON.stringify({coverage,next_questions:[{anchor:'legacy SIEM',text:'How do your analysts investigate alerts in the legacy SIEM?',targets:'identify_pain',why:'Understand current investigation'}]})}});
};
