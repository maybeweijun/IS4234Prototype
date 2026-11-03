import { readFile } from "node:fs/promises";
import { network } from "hardhat";
import { id as hashText, keccak256, toUtf8Bytes } from "ethers";

export const STAGES = ["Draft", "Limited", "Expanded", "Reopened"];
export const STATUSES = ["Missing", "Stale", "Inconclusive", "Failed", "Eligible for reviewer assessment"];
export const REASONS = [
  "All configured checks satisfied", "Required evidence missing", "Evidence belongs to a different build revision",
  "Fewer than 30 trials", "Success rate below 95%", "Evidence not accepted by validation owner",
  "Fewer than 1,000 engaged miles in a cohort", "Incomplete data", "Cohorts not comparable",
  "Safeguards inactive", "Serious concern requires review", "Event rate increased",
];
export const SCENARIOS = ["Driver attention", "Mode confusion", "Operating boundary"];

// Fixed field order is part of the hash specification; do not use arbitrary JSON key order.
export type LabRecord = { configuration: string; scenario: number; trials: number; successes: number; accepted: boolean; source: string };
export type FieldRecord = { configuration: string; baselineEvents: number; baselineMiles: number; postEvents: number; postMiles: number; complete: boolean; comparable: boolean; safeguardsEnabled: boolean; seriousEvent: boolean; source: string };
export type Evidence = { kind: "lab"; synthetic: true; build: string; records: LabRecord[] } | { kind: "field"; synthetic: true; build: string; records: FieldRecord[] };
export type Preimage = { digest: string; canonical: string; purpose: string };

export async function readSample(name: string): Promise<unknown> {
  return JSON.parse(await readFile(new URL(`../../data/${name}.json`, import.meta.url), "utf8"));
}

export function validateEvidence(value: unknown): Evidence {
  if (!value || typeof value !== "object") throw new Error("Expected a JSON object");
  const d = value as Record<string, unknown>;
  const text = (x: unknown): x is string => typeof x === "string" && x.trim().length > 0 && x.length <= 500;
  const integer = (x: unknown): x is number => typeof x === "number" && Number.isSafeInteger(x) && x >= 0;
  if ((d.kind !== "lab" && d.kind !== "field") || d.synthetic !== true || !text(d.build)
    || !Array.isArray(d.records) || d.records.length === 0 || d.records.length > 24) throw new Error("Invalid evidence envelope; kind, synthetic:true, build and 1-24 records required");
  const seen = new Set<string>();
  for (const item of d.records) {
    if (!item || typeof item !== "object") throw new Error("Invalid evidence record");
    const r = item as Record<string, unknown>;
    if (!text(r.configuration) || !text(r.source)) throw new Error("Configuration and source are required");
    if (d.kind === "lab") {
      if (!integer(r.scenario) || r.scenario > 2 || !integer(r.trials) || r.trials > 4294967295
        || !integer(r.successes) || r.successes > r.trials || typeof r.accepted !== "boolean") throw new Error("Invalid lab scenario, uint32 counts or accepted flag");
    } else {
      for (const key of ["baselineEvents", "baselineMiles", "postEvents", "postMiles"]) {
        if (!integer(r[key])) throw new Error(`${key} must be a nonnegative safe integer`);
      }
      for (const key of ["complete", "comparable", "safeguardsEnabled", "seriousEvent"]) {
        if (typeof r[key] !== "boolean") throw new Error(`${key} must be true or false`);
      }
    }
    const key = `${r.configuration}:${d.kind === "lab" ? r.scenario : "field"}`;
    if (seen.has(key)) throw new Error("Duplicate record within import");
    seen.add(key);
  }
  return value as Evidence;
}

export function canonicalEvidence(kind: "lab" | "field", build: string, r: LabRecord | FieldRecord): string {
  if (kind === "lab") {
    const d = r as LabRecord;
    return JSON.stringify({ schema: "safeguard-evidence-v1", synthetic: true, kind, build, configuration: d.configuration,
      scenario: d.scenario, trials: d.trials, successes: d.successes, accepted: d.accepted, source: d.source });
  }
  const d = r as FieldRecord;
  return JSON.stringify({ schema: "safeguard-evidence-v1", synthetic: true, kind, build, configuration: d.configuration,
    baselineEvents: d.baselineEvents, baselineMiles: d.baselineMiles, postEvents: d.postEvents, postMiles: d.postMiles,
    complete: d.complete, comparable: d.comparable, safeguardsEnabled: d.safeguardsEnabled, seriousEvent: d.seriousEvent, source: d.source });
}

export async function createPrototype() {
  // Always an isolated simulated EVM: the prototype signer service never targets a public network.
  const connection = await network.create({ network: "hardhatMainnet" });
  const { ethers, networkHelpers } = connection;
  const [lead, engineer, reviewer, analyst, observer, secondReviewer] = await ethers.getSigners();
  const actors = { SafetyLead: lead, Engineer: engineer, Reviewer: reviewer, Analyst: analyst, Observer: observer, SecondReviewer: secondReviewer };
  const registry = await ethers.deployContract("SafeguardAssurance", [lead.address]);
  await registry.waitForDeployment();
  for (const [actor, role] of [[engineer, 1], [reviewer, 2], [analyst, 3], [secondReviewer, 2]] as const) {
    await (await registry.setRole(actor.address, role)).wait();
  }
  const candidate = await readSample("candidate") as { label: string; build: string; scope: string; configurations: string[] };
  const preimages: Preimage[] = [];
  function remember(canonical: string, purpose: string): string {
    const digest = keccak256(toUtf8Bytes(canonical));
    preimages.push({ digest, canonical, purpose });
    return digest;
  }
  remember(candidate.build, "Build label (synthetic; replace with binary artifact hash in production)");
  remember(candidate.scope, "Scope and safety claim");
  for (const config of candidate.configurations) remember(config, "Configuration label");
  await (await registry.connect(engineer).createCandidate(hashText(candidate.build), hashText(candidate.scope), candidate.configurations.map(hashText))).wait();
  const candidateId = await registry.candidateCount();
  const deployedAt = (await registry.deploymentTransaction()!.wait())!.blockNumber;
  return { connection, ethers, networkHelpers, actors, registry, candidate, candidateId, preimages, remember, deployedAt, currentBuild: candidate.build };
}
export type Prototype = Awaited<ReturnType<typeof createPrototype>>;
export type Actor = keyof Prototype["actors"];

export async function importEvidence(ctx: Prototype, actor: Actor, value: unknown) {
  const data = validateEvidence(value);
  // Preflight the whole import before transactions. A submitted batch still uses one tx per record.
  if (data.build !== ctx.currentBuild) throw new Error("Wrong build: evidence cannot satisfy the current candidate");
  for (const r of data.records) {
    if (!ctx.candidate.configurations.includes(r.configuration)) throw new Error(`Out-of-scope configuration: ${r.configuration}`);
  }
  const client = ctx.registry.connect(ctx.actors[actor]);
  const txs: string[] = [];
  for (const r of data.records) {
    const digest = ctx.remember(canonicalEvidence(data.kind, data.build, r), "Evidence record");
    const tx = data.kind === "lab"
      ? await client.recordLab(ctx.candidateId, hashText(r.configuration), (r as LabRecord).scenario, hashText(data.build), {
        trials: (r as LabRecord).trials, successes: (r as LabRecord).successes, accepted: (r as LabRecord).accepted, digest,
      })
      : await client.recordField(ctx.candidateId, hashText(r.configuration), hashText(data.build), {
        baselineEvents: (r as FieldRecord).baselineEvents, baselineMiles: (r as FieldRecord).baselineMiles,
        postEvents: (r as FieldRecord).postEvents, postMiles: (r as FieldRecord).postMiles,
        complete: (r as FieldRecord).complete, comparable: (r as FieldRecord).comparable,
        safeguardsEnabled: (r as FieldRecord).safeguardsEnabled, seriousEvent: (r as FieldRecord).seriousEvent, digest,
      });
    await tx.wait();
    txs.push(tx.hash);
  }
  return txs;
}

export function errorMessage(error: unknown): string {
  const e = error as { shortMessage?: string; message?: string };
  return e.shortMessage ?? e.message ?? String(error);
}

export async function exportReview(ctx: Prototype) {
  const { registry, candidateId: id, ethers } = ctx;
  const c = await registry.getCandidate(id);
  const gateJSON = (g: Awaited<ReturnType<typeof registry.labGate>>) => ({ status: STATUSES[Number(g.status)], reason: REASONS[Number(g.reason)], configuration: g.configuration, scenario: Number(g.scenario) });
  const configurations = [];
  for (const config of ctx.candidate.configurations) {
    const configId = hashText(config);
    const labs = [];
    for (let scenario = 0; scenario < 3; scenario++) {
      const lab = await registry.getLab(id, configId, scenario);
      labs.push({ scenario: SCENARIOS[scenario], gate: gateJSON(await registry.labCheck(id, configId, scenario)),
        buildRevision: lab.buildRevision, submitter: lab.submitter, trials: lab.data.trials, successes: lab.data.successes, accepted: lab.data.accepted, digest: lab.data.digest });
    }
    const field = await registry.getField(id, configId);
    configurations.push({ label: config, id: configId, labs, field: {
      gate: gateJSON(await registry.fieldCheck(id, configId)), buildRevision: field.buildRevision, submitter: field.submitter,
      baselineEvents: field.data.baselineEvents, baselineMiles: field.data.baselineMiles,
      postEvents: field.data.postEvents, postMiles: field.data.postMiles, complete: field.data.complete,
      comparable: field.data.comparable, safeguardsEnabled: field.data.safeguardsEnabled,
      seriousEvent: field.data.seriousEvent, digest: field.data.digest,
    } });
  }
  const decisions = [];
  for (let i = 0n; i < await registry.decisionCount(id); i++) {
    const d = await registry.getDecision(id, i);
    decisions.push({ index: i, stage: STAGES[Number(d.stage)], buildRevision: d.buildRevision, evidenceRevision: d.evidenceRevision,
      decidedAt: d.decidedAt, validUntil: d.validUntil, reviewer: d.reviewer, snapshotHash: d.snapshotHash, rationaleHash: d.rationaleHash });
  }
  const actions = [];
  for (let i = 1n; i <= await registry.actionCount(); i++) {
    const a = await registry.getAction(i);
    if (a.candidateId !== id) continue;
    actions.push({ id: i, owner: a.owner, reporter: a.reporter, openedAt: a.openedAt, dueAt: a.dueAt, reason: REASONS[Number(a.reason)],
      evidenceHash: a.evidenceHash, escalated: a.escalated, overdue: await registry.isOverdue(i), closed: a.closed,
      closedBy: a.closedBy, resolutionHash: a.resolutionHash, closureRationaleHash: a.closureRationaleHash });
  }
  // Raw receipt logs retain every historical input and decision, not just latest mapping values.
  const logs = await ethers.provider.getLogs({ address: await registry.getAddress(), fromBlock: ctx.deployedAt, toBlock: "latest" });
  const block = (await ethers.provider.getBlock("latest"))!;
  const artifact = {
    schema: "safeguard-review-v1", synthetic: true, disclaimer: "Workflow evidence only. Not vehicle validation, NHTSA approval or proof of safety.",
    chainId: (await ethers.provider.getNetwork()).chainId, contract: await registry.getAddress(), blockNumber: block.number, chainTime: block.timestamp,
    candidateId: id, label: ctx.candidate.label, build: ctx.currentBuild, buildHash: c.buildHash, scope: ctx.candidate.scope,
    scopeHash: c.scopeHash, buildRevision: c.buildRevision, evidenceRevision: c.evidenceRevision, stage: STAGES[Number(c.stage)],
    openActions: c.openActions, ruleHash: await registry.RULE_HASH(), snapshotHash: await registry.snapshotHash(id),
    limitedAuthorized: await registry.isDeploymentAuthorized(id, 1), expansionAuthorized: await registry.isDeploymentAuthorized(id, 2),
    labGate: gateJSON(await registry.labGate(id)), fieldGate: gateJSON(await registry.fieldGate(id)),
    actors: Object.fromEntries(Object.entries(ctx.actors).map(([role, actor]) => [role, actor.address])),
    configurations, decisions, actions, preimages: ctx.preimages,
    logs: logs.map(l => ({ blockNumber: l.blockNumber, blockHash: l.blockHash, transactionHash: l.transactionHash, index: l.index,
      topics: l.topics, data: l.data, event: registry.interface.parseLog({ topics: [...l.topics], data: l.data })?.name })),
  };
  return JSON.parse(JSON.stringify(artifact, (_, v) => typeof v === "bigint" ? v.toString() : v));
}
