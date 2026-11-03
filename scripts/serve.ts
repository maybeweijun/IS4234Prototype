import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { readFile } from "node:fs/promises";
import { id as hashText } from "ethers";
import { createPrototype, importEvidence, readSample, exportReview, errorMessage, type Actor } from "./lib/prototype.js";

const ctx = await createPrototype();
const port = Number(process.env.PORT ?? 4234);
if (!Number.isInteger(port) || port < 1024 || port > 65535) throw new Error("PORT must be an integer from 1024 to 65535");
const requestLog: { at: string; actor: string; command: string; outcome: string }[] = [];
const samples = new Set(["lab-pass", "field-adverse", "field-improved", "field-inconclusive"]);
let serial: Promise<unknown> = Promise.resolve();

function send(res: ServerResponse, code: number, value: unknown, type = "application/json") {
  res.writeHead(code, { "Content-Type": `${type}; charset=utf-8`, "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff",
    "Content-Security-Policy": "default-src 'self'; script-src 'self'; style-src 'self'; object-src 'none'; frame-ancestors 'none'" });
  res.end(type === "application/json" ? JSON.stringify(value) : value);
}
async function body(req: IncomingMessage): Promise<Record<string, unknown>> {
  const chunks: Buffer[] = [];
  let length = 0;
  for await (const chunk of req) {
    length += Buffer.byteLength(chunk);
    if (length > 65536) throw new Error("Request exceeds 64 KiB");
    chunks.push(Buffer.from(chunk));
  }
  const data = JSON.parse(Buffer.concat(chunks).toString("utf8"));
  if (!data || typeof data !== "object" || Array.isArray(data)) throw new Error("Expected request object");
  return data;
}
function requiredText(v: unknown): string {
  if (typeof v !== "string" || v.trim().length < 10 || v.length > 2000) throw new Error("Provide a meaningful rationale of 10-2,000 characters");
  return v.trim();
}
async function perform(data: Record<string, unknown>) {
  const actor = data.actor as Actor;
  if (!Object.hasOwn(ctx.actors, actor)) throw new Error("Unknown workspace role");
  const contract = ctx.registry.connect(ctx.actors[actor]);
  const now = await ctx.networkHelpers.time.latest();
  const days = Number(data.days ?? 7);
  if (!Number.isInteger(days) || days < 1 || days > 30) throw new Error("Approval duration must be 1-30 days");
  const expiry = BigInt(now + days * 86400);
  const actionId = Number(data.actionId);
  let tx;
  switch (data.command) {
    case "import": return { transactions: await importEvidence(ctx, actor, data.evidence) };
    case "approve-limited": tx = await contract.approveLimited(ctx.candidateId, ctx.remember(requiredText(data.rationale), "Limited decision rationale"), expiry); break;
    case "approve-expansion": tx = await contract.approveExpansion(ctx.candidateId, ctx.remember(requiredText(data.rationale), "Expansion decision rationale"), expiry); break;
    case "concern": tx = await contract.reportConcern(ctx.candidateId, ctx.remember(requiredText(data.rationale), "Adverse signal")); break;
    case "close":
      if (!Number.isSafeInteger(actionId) || actionId < 1) throw new Error("Select an action ID");
      tx = await contract.closeAction(actionId, ctx.remember(requiredText(data.resolution), "Action resolution evidence"), ctx.remember(requiredText(data.rationale), "Action closure rationale")); break;
    case "escalate":
      if (!Number.isSafeInteger(actionId) || actionId < 1) throw new Error("Select an action ID");
      tx = await contract.escalateOverdue(actionId); break;
    case "advance-time":
      if (actor !== "SafetyLead") throw new Error("Use SafetyLead for this development-only time control");
      await ctx.networkHelpers.time.increase(8 * 86400);
      return { developmentOnly: true, message: "Simulated EVM advanced eight days; no transaction is sent automatically" };
    case "revise": {
      const build = requiredText(data.build);
      const rationale = ctx.remember(requiredText(data.rationale), "Build revision rationale");
      const buildDigest = ctx.remember(build, "Build label");
      tx = await contract.reviseBuild(ctx.candidateId, buildDigest, rationale);
      await tx.wait();
      ctx.currentBuild = build;
      return { transaction: tx.hash };
    }
    default: throw new Error("Unknown command");
  }
  await tx.wait();
  return { transaction: tx.hash };
}
const staticFiles: Record<string, [string, string]> = {
  "/": ["index.html", "text/html"], "/app.js": ["app.js", "text/javascript"], "/style.css": ["style.css", "text/css"],
};
const server = createServer(async (req, res) => {
  try {
    const host = req.headers.host;
    if (host !== `127.0.0.1:${port}` && host !== `localhost:${port}`) return send(res, 403, { error: "Local host only" });
    const url = new URL(req.url ?? "/", `http://${host}`);
    if (req.method === "GET" && staticFiles[url.pathname]) {
      const [file, type] = staticFiles[url.pathname];
      return send(res, 200, await readFile(new URL(`../web/${file}`, import.meta.url), "utf8"), type);
    }
    if (req.method === "GET" && (url.pathname === "/api/state" || url.pathname === "/api/export")) {
      await serial;
      const report = await exportReview(ctx);
      if (url.pathname === "/api/export") res.setHeader("Content-Disposition", "attachment; filename=safeguard-review.json");
      return send(res, 200, { ...report, requestLog, requestLogNotice: "Off-chain demonstration log; rejected estimates are not confirmed blockchain events" });
    }
    if (req.method === "GET" && url.pathname === "/api/sample") {
      const name = url.searchParams.get("name") ?? "";
      if (!samples.has(name)) return send(res, 404, { error: "Unknown sample" });
      return send(res, 200, await readSample(name));
    }
    if (req.method === "POST" && url.pathname === "/api/action") {
      if (req.headers["x-demo-request"] !== "1") return send(res, 403, { error: "Missing local demonstration header" });
      if (req.headers.origin && req.headers.origin !== `http://${host}`) return send(res, 403, { error: "Cross-origin requests are disabled" });
      const data = await body(req);
      const task = serial.then(async () => {
        try {
          const result = await perform(data);
          requestLog.push({ at: new Date().toISOString(), actor: String(data.actor), command: String(data.command), outcome: "Confirmed / completed" });
          return result;
        } catch (error) {
          requestLog.push({ at: new Date().toISOString(), actor: String(data.actor), command: String(data.command), outcome: `Rejected: ${errorMessage(error).slice(0, 400)}` });
          throw error;
        }
      });
      serial = task.catch(() => undefined);
      try { return send(res, 200, await task); }
      catch (error) { return send(res, 400, { error: errorMessage(error).slice(0, 600), hint: "Refresh shows confirmed state. Imports use one transaction per record; earlier records may already be committed." }); }
    }
    return send(res, 404, { error: "Not found" });
  } catch (error) { send(res, 400, { error: errorMessage(error).slice(0, 600) }); }
});
server.listen(port, "127.0.0.1", () => {
  console.log(`\nAutosteer Safeguard Assurance: http://127.0.0.1:${port}`);
  console.log(`Contract: ${ctx.registry.target}; chain: Hardhat simulated EVM`);
  console.log("Synthetic prototype signers only. Role selection is not a login. Restart clears the session. Ctrl+C to stop.\n");
});
for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.on(signal, () => server.close(() => void ctx.connection.close().then(() => process.exit(0))));
}
