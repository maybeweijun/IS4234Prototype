import { mkdir, writeFile } from "node:fs/promises";
import assert from "node:assert/strict";
import { id as hashText, ZeroHash } from "ethers";
import { createPrototype, importEvidence, readSample, exportReview, errorMessage } from "./lib/prototype.js";

const ctx = await createPrototype();
const { registry, actors, candidateId: id, networkHelpers } = ctx;
const steps: { step: string; outcome: string; detail?: string }[] = [];
async function blocked(step: string, fn: () => Promise<unknown>) {
  let message = "";
  try { await fn(); } catch (error) { message = errorMessage(error); }
  assert.ok(message, `${step} unexpectedly succeeded`);
  steps.push({ step, outcome: "Blocked as expected", detail: message });
  console.log(`[BLOCKED] ${step}`);
}
const rationale = ctx.remember("Synthetic reviewer rationale: configured evidence inspected; limited residual uncertainty accepted for prototype simulation only.", "Decision rationale");
const expiry = async () => BigInt(await networkHelpers.time.latest()) + 86400n;

await blocked("Missing evidence cannot obtain approval", async () => registry.connect(actors.Reviewer).approveLimited(id, rationale, await expiry()));
await importEvidence(ctx, "Engineer", await readSample("lab-pass"));
await blocked("Submitter cannot self-approve", async () => registry.connect(actors.Engineer).approveLimited(id, rationale, await expiry()));
await blocked("Reviewer must provide rationale", async () => registry.connect(actors.Reviewer).approveLimited(id, ZeroHash, await expiry()));
await (await registry.connect(actors.Reviewer).approveLimited(id, rationale, await expiry())).wait();
assert.equal(await registry.isDeploymentAuthorized(id, 1), true);
steps.push({ step: "Independent limited deployment decision", outcome: "Authorized for exact snapshot" });
await importEvidence(ctx, "Analyst", await readSample("field-adverse"));
assert.equal(await registry.isDeploymentAuthorized(id, 1), false);
assert.equal((await registry.getCandidate(id)).openActions, 1n);
steps.push({ step: "8/4000 baseline versus 12/4000 post-update", outcome: "Rate 2.0 -> 3.0; review reopened, owner and due date assigned" });
await blocked("Open corrective action blocks expansion", async () => registry.connect(actors.Reviewer).approveExpansion(id, rationale, await expiry()));
await networkHelpers.time.increase(8 * 86400);
await (await registry.connect(actors.Observer).escalateOverdue(1)).wait();
assert.equal((await registry.getAction(1)).escalated, true);
steps.push({ step: "Overdue action", outcome: "Escalation transaction emitted for safety lead" });
await importEvidence(ctx, "Analyst", await readSample("field-improved"));
assert.equal((await registry.getAction(1)).closed, false);
steps.push({ step: "Improved field evidence", outcome: "Eligible evidence; action remains open" });
const resolution = ctx.remember("Synthetic resolution: corrected monitoring study, comparable cohorts and enabled safeguards reviewed.", "Action resolution");
await (await registry.connect(actors.Reviewer).closeAction(1, resolution, rationale)).wait();
assert.equal(await registry.isDeploymentAuthorized(id, 2), false);
steps.push({ step: "Independent action closure", outcome: "Closed; separate release decision still required" });
await (await registry.connect(actors.Reviewer).approveExpansion(id, rationale, await expiry())).wait();
assert.equal(await registry.isDeploymentAuthorized(id, 2), true);
steps.push({ step: "Separate expansion decision", outcome: "Authorized for current snapshot" });
await mkdir("output/demo", { recursive: true });
await writeFile("output/demo/review-expanded.json", JSON.stringify(await exportReview(ctx), null, 2) + "\n");
ctx.currentBuild = "autosteer-2026.2";
const buildDigest = ctx.remember(ctx.currentBuild, "Build label");
await (await registry.connect(actors.Engineer).reviseBuild(id, buildDigest, rationale)).wait();
assert.equal(await registry.isDeploymentAuthorized(id, 2), false);
assert.equal((await registry.labGate(id)).status, 1n);
assert.equal(await registry.decisionCount(id), 2n);
steps.push({ step: "New software build", outcome: "Earlier evidence stale; authorization invalidated; both decisions preserved" });
const report = await exportReview(ctx);
await writeFile("output/demo/review-reopened.json", JSON.stringify(report, null, 2) + "\n");
await writeFile("output/demo/walkthrough.json", JSON.stringify({ synthetic: true, contract: report.contract, steps }, null, 2) + "\n");
for (const s of steps) console.log(`${s.outcome}: ${s.step}`);
console.log("\nReview packages written to output/demo/. All data are synthetic.");
await ctx.connection.close();
