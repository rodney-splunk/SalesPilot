// circuit.mjs — Cisco CIRCUIT (Azure OpenAI gateway) provider support.
// Manages the OAuth2 client-credentials token (fetch + cache + refresh). Credentials live in
// macOS Keychain. Public endpoint/client configuration stays in engine/.circuit.json.
import { readFileSync } from "fs";
import {execFile} from "node:child_process";
import {promisify} from "node:util";
const run=promisify(execFile);

const CONFIG_PATH = new URL("./.circuit.json", import.meta.url).pathname;
let cfg = null;
export function circuitConfig() {
  if (cfg) return cfg;
  if(process.env.SALESPILOT_OFFLINE==="1"&&process.env.COACH_LOCAL==="1")return cfg={};
  try { cfg = JSON.parse(readFileSync(CONFIG_PATH, "utf8")); } catch { cfg = {}; }
  return cfg;
}

let credentialRequest=null, credentialCache=null;
export async function circuitCredentials() {
  if(process.env.SALESPILOT_LOCAL_ONLY==='1')throw Error("Local-only processing blocks Cisco credentials and inference");
  const config=circuitConfig();
  if(config.credential_store!=='macos-keychain')return config;
  if(credentialCache)return credentialCache;
  if(!credentialRequest)credentialRequest=(async()=>{
    try {
      const reader=process.env.SALESPILOT_CREDENTIAL_READER;
      const {stdout}=await run(reader || '/usr/bin/security',reader ? ['provider-credentials'] : ['find-generic-password','-s','com.salespilot.circuit','-a','credentials','-w'],{timeout:5000,maxBuffer:65536});
      const secret=JSON.parse(stdout);
      if(typeof secret.client_secret!=='string'||typeof secret.app_key!=='string')throw Error();
      return credentialCache={...config,client_secret:secret.client_secret,app_key:secret.app_key};
    } catch { throw Error('Cisco credentials unavailable; unlock the Mac and check Keychain access.'); }
    finally { credentialRequest=null; }
  })();
  return credentialRequest;
}

let cachedToken = null, tokenExp = 0;

/// Returns a valid Bearer access token, fetching a new one only when the cached one is near expiry.
let tokenRequest = null;
export function circuitToken() {
  if(process.env.SALESPILOT_LOCAL_ONLY==='1')return Promise.reject(Error("Local-only processing blocks Cisco authentication"));
  if(cachedToken && Date.now()<tokenExp-60000)return Promise.resolve(cachedToken);
  if(!tokenRequest)tokenRequest=fetchToken().finally(()=>{tokenRequest=null;});
  return tokenRequest;
}
async function fetchToken() {
  const c = await circuitCredentials();
  if (!c.client_id || !c.client_secret) throw new Error("CIRCUIT credentials unavailable; check macOS Keychain access");
  const now = Date.now();
  if (cachedToken && now < tokenExp - 60000) return cachedToken;  // reuse until 60s before expiry
  const tokenURL=new URL(c.token_url || "https://id.cisco.com/oauth2/default/v1/token");
  if(tokenURL.protocol!=="https:"||tokenURL.hostname!=="id.cisco.com"||tokenURL.username||tokenURL.password)throw Error("Unapproved Cisco authentication endpoint");
  const basic = Buffer.from(`${c.client_id}:${c.client_secret}`).toString("base64");
  const res = await fetch(c.token_url || "https://id.cisco.com/oauth2/default/v1/token", {
    signal: AbortSignal.timeout(7000), redirect:"error",
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded", Authorization: `Basic ${basic}` },
    body: "grant_type=client_credentials",
  });
  if (!res.ok) throw new Error(`CIRCUIT authentication failed (${res.status})`);
  const j = await res.json();
  if (typeof j.access_token !== "string" || !j.access_token) throw new Error("CIRCUIT returned no access token");
  cachedToken = j.access_token;
  tokenExp = now + (Number(j.expires_in) || 3600) * 1000;
  return cachedToken;
}
