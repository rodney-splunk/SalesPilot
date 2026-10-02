// sfdc.mjs — minimal MCP stdio client for the local Salesforce MCP server, so the app/engine can
// pull account intel without a Salesforce CLI. Speaks JSON-RPC (newline-delimited) to server.js.
//
//   node sfdc.mjs "University of Miami"      # test: account + opportunities

import { spawn } from "node:child_process";

const HOME = process.env.HOME;
const SERVER = `${HOME}/.config/ghost/mcp-servers/dist/servers/salesforce/server.js`;
const CONFIG = `${HOME}/.config/ghost/mcp/sessions/salesforce.yaml`;
const NODE = "/opt/homebrew/bin/node";

// Call one tool on the salesforce MCP server; resolves the tool's text content.
export function sfdcCall(toolName, args, timeoutMs = 25000) {
  return new Promise((resolve, reject) => {
    const proc = spawn(NODE, [SERVER, "--config", CONFIG], { stdio: ["pipe", "pipe", "pipe"] });
    let buf = "";
    let done = false;
    // The MCP server is a child node process. SIGTERM alone left it alive often enough that the
    // PARENT never exited: prep finished, prep.txt was written, and the app sat there forever
    // waiting for a termination that never came. Tear the child down hard and drop every handle
    // that could keep our event loop alive.
    const reap = () => {
      try { proc.stdin.destroy(); } catch {}
      try { proc.stdout.destroy(); } catch {}
      try { proc.stderr.destroy(); } catch {}
      try { proc.kill("SIGKILL"); } catch {}
      try { proc.unref(); } catch {}
    };
    const finish = (fn, val) => { if (!done) { done = true; clearTimeout(timer); reap(); fn(val); } };
    const timer = setTimeout(() => finish(reject, new Error("salesforce MCP timeout")), timeoutMs);
    const send = (obj) => { try { proc.stdin.write(JSON.stringify(obj) + "\n"); } catch {} };

    proc.stdout.on("data", (d) => {
      buf += d.toString();
      let idx;
      while ((idx = buf.indexOf("\n")) >= 0) {
        const line = buf.slice(0, idx).trim();
        buf = buf.slice(idx + 1);
        if (!line) continue;
        let msg;
        try { msg = JSON.parse(line); } catch { continue; }
        if (msg.id === 1) {
          if (msg.error) return finish(reject, new Error(msg.error.message || "initialize failed"));
          send({ jsonrpc: "2.0", method: "notifications/initialized" });
          send({ jsonrpc: "2.0", id: 2, method: "tools/call", params: { name: toolName, arguments: args } });
        } else if (msg.id === 2) {
          if (msg.error) return finish(reject, new Error(msg.error.message || "tool call failed"));
          const text = (msg.result?.content || []).map((c) => c.text).filter(Boolean).join("\n");
          finish(resolve, text);
        }
      }
    });
    proc.on("error", (e) => finish(reject, e));
    send({ jsonrpc: "2.0", id: 1, method: "initialize",
      params: { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "salespilot", version: "1.0" } } });
  });
}

// Search an SObject and return parsed results (best-effort).
export async function sfdcSearch(query, object, limit = 5) {
  const text = await sfdcCall("salesforce_search_records", { query, object_api_name: object, limit });
  try { return JSON.parse(text).results || []; } catch { return []; }
}

// Human-readable account + opportunity lines for prep.
export async function sfdcPrepLines(account) {
  const lines = [];
  const accts = await sfdcSearch(account, "Account", 3);
  for (const a of accts) {
    const f = a.fields || {};
    lines.push(`Account: ${a.name} — owner ${f.Owner?.Name || "?"}, ${[f.BillingState, f.BillingCountry].filter(Boolean).join(" ")}, ${f.Website || ""} (${f.RecordType?.Name || "account"})`);
  }
  try {
    const opps = await sfdcSearch(account, "Opportunity", 5);
    for (const o of opps) {
      const f = o.fields || {};
      const amt = f.Amount ? `$${f.Amount}` : "";
      lines.push(`Opportunity: ${o.name} — stage ${f.StageName || "?"} ${amt} close ${f.CloseDate || "?"}`);
    }
  } catch {}
  return lines;
}

// Log the call as an SE Activity Event on the account (real write).
export async function logEvent({ account, subject, description }) {
  let whatId = null;
  if (account) {
    try { const a = await sfdcSearch(account, "Account", 1); whatId = a[0]?.id || null; } catch {}
  }
  const now = new Date();
  const end = new Date(now.getTime() + 30 * 60000);
  const args = {
    subject: (subject || "Call recap").slice(0, 255),
    start_datetime: now.toISOString(),
    end_datetime: end.toISOString(),
    description: (description || "").slice(0, 30000),
    dry_run: false,
    confirm_create: true,
  };
  if (whatId) args.what_id = whatId;
  return await sfdcCall("salesforce_create_event", args, 30000);
}


// Only act as a CLI when run directly. Imported, this file must not read the HOST program's argv
// or call process.exit: ghost-prep.mjs imports it, and this block was reading ghost-prep's flags as
// a Salesforce query and then killing the whole prep on failure.
import { realpathSync } from "node:fs";
import { fileURLToPath } from "node:url";
const isMainModule = (() => {
  try { return realpathSync(process.argv[1] || "") === realpathSync(fileURLToPath(import.meta.url)); }
  catch { return false; }
})();

const mode = isMainModule ? process.argv[2] : undefined;
if (mode === "log") {
  logEvent({ account: process.argv[3] || "", subject: process.argv[4] || "Call recap", description: process.argv[5] || "" })
    .then((t) => console.log(t))
    .catch((e) => { console.error(`SFDC log error: ${e.message}`); process.exit(2); });
} else if (mode) {
  sfdcPrepLines(process.argv.slice(2).join(" "))
    .then((lines) => console.log(lines.length ? lines.join("\n") : "(no SFDC results)"))
    .catch((e) => { console.error(`SFDC error: ${e.message}`); process.exit(2); });
}
