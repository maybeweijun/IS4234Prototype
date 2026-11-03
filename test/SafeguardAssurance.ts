import assert from "node:assert/strict";
import { expect } from "chai";
import { id as hashText, keccak256, toUtf8Bytes, ZeroHash, AbiCoder } from "ethers";
import { createPrototype, importEvidence, readSample, exportReview, canonicalEvidence, validateEvidence } from "../scripts/lib/prototype.js";

describe("SafeguardAssurance: JSON and signed user workflows", function () {
  it("executes the report's complete adverse-signal, closure and separate decision cycle", async function () {
    const ctx = await createPrototype();
    try {
      const { registry, candidateId: id, actors, networkHelpers } = ctx;
      await expect(registry.connect(actors.Reviewer).approveLimited(id, hashText("review"), BigInt(await networkHelpers.time.latest()) + 86400n))
        .to.be.revertedWithCustomError(registry, "GateBlocked");
      const labTxs = await importEvidence(ctx, "Engineer", await readSample("lab-pass"));
      assert.equal(labTxs.length, 6);
      await expect(registry.connect(actors.Engineer).approveLimited(id, hashText("self"), BigInt(await networkHelpers.time.latest()) + 86400n))
        .to.be.revertedWithCustomError(registry, "Unauthorized");
      await expect(registry.connect(actors.Reviewer).approveLimited(id, ZeroHash, BigInt(await networkHelpers.time.latest()) + 86400n))
        .to.be.revertedWithCustomError(registry, "InvalidInput");
      await (await registry.connect(actors.Reviewer).approveLimited(id, hashText("limited rationale"), BigInt(await networkHelpers.time.latest()) + 86400n)).wait();
      await importEvidence(ctx, "Analyst", await readSample("field-adverse"));
      assert.equal(await registry.isDeploymentAuthorized(id, 1), false);
      assert.equal((await registry.getAction(1)).owner, actors.Engineer.address);
      await networkHelpers.time.increase(8 * 86400);
      await expect(registry.connect(actors.Observer).escalateOverdue(1)).to.emit(registry, "ActionEscalated");
      await importEvidence(ctx, "Analyst", await readSample("field-improved"));
      assert.equal((await registry.getAction(1)).closed, false);
      await (await registry.connect(actors.Reviewer).closeAction(1, hashText("resolution"), hashText("closure judgment"))).wait();
      assert.equal(await registry.isDeploymentAuthorized(id, 2), false);
      await (await registry.connect(actors.Reviewer).approveExpansion(id, hashText("expansion judgment"), BigInt(await networkHelpers.time.latest()) + 86400n)).wait();
      assert.equal(await registry.isDeploymentAuthorized(id, 2), true);
      const report = await exportReview(ctx);
      assert.equal(report.decisions.length, 2);
      assert.ok(report.logs.some((l: { event: string }) => l.event === "ActionEscalated"));
      // The independently reconstructed snapshot binds chain, contract, candidate, build, scope, revisions and policy.
      const digest = keccak256(AbiCoder.defaultAbiCoder().encode(
        ["uint256", "address", "uint256", "bytes32", "bytes32", "uint64", "uint64", "bytes32[]", "bytes32"],
        [report.chainId, report.contract, report.candidateId, report.buildHash, report.scopeHash, report.buildRevision,
          report.evidenceRevision, report.configurations.map((c: { id: string }) => c.id), report.ruleHash],
      ));
      assert.equal(digest, report.snapshotHash);
    } finally { await ctx.connection.close(); }
  });

  it("replays superseded lab inputs from logs while retaining original approval snapshots", async function () {
    const ctx = await createPrototype();
    try {
      await importEvidence(ctx, "Engineer", await readSample("lab-pass"));
      const expiry = BigInt(await ctx.networkHelpers.time.latest()) + 86400n;
      await (await ctx.registry.connect(ctx.actors.Reviewer).approveLimited(ctx.candidateId, hashText("review"), expiry)).wait();
      const old = await ctx.registry.snapshotHash(ctx.candidateId);
      const data = validateEvidence(await readSample("lab-pass"));
      if (data.kind !== "lab") throw new Error("Expected lab");
      const revised = { ...data, records: [{ ...data.records[0], successes: 40, source: "revision-two" }] };
      await importEvidence(ctx, "Engineer", revised);
      const events = await ctx.registry.queryFilter(ctx.registry.filters.LabRecorded());
      assert.equal(events.length, 7);
      assert.equal(events[0].args.evidence.data.successes, 39n);
      assert.equal(events[6].args.evidence.data.successes, 40n);
      assert.equal((await ctx.registry.getDecision(ctx.candidateId, 0)).snapshotHash, old);
      assert.equal(await ctx.registry.isDeploymentAuthorized(ctx.candidateId, 1), false);
    } finally { await ctx.connection.close(); }
  });

  it("rejects malformed, duplicate, wrong-build and out-of-scope JSON before any record is submitted", async function () {
    const ctx = await createPrototype();
    try {
      const original = validateEvidence(await readSample("lab-pass"));
      if (original.kind !== "lab") throw new Error("Expected lab");
      assert.throws(() => validateEvidence({ ...original, records: [{ ...original.records[0], accepted: "true" }] }));
      assert.throws(() => validateEvidence({ ...original, records: [original.records[0], original.records[0]] }));
      assert.throws(() => validateEvidence({ ...original, records: [{ ...original.records[0], trials: 1.5 }] }));
      await assert.rejects(importEvidence(ctx, "Engineer", { ...original, build: "old-version" }), /Wrong build/);
      await assert.rejects(importEvidence(ctx, "Engineer", { ...original, records: [...original.records, { ...original.records[0], configuration: "unknown" }] }), /Out-of-scope/);
      assert.equal((await ctx.registry.getCandidate(ctx.candidateId)).evidenceRevision, 1n);
    } finally { await ctx.connection.close(); }
  });

  it("enforces write roles on chain even when a client chooses another actor", async function () {
    const ctx = await createPrototype();
    try {
      await assert.rejects(importEvidence(ctx, "Observer", await readSample("lab-pass")), /Unauthorized/);
      await assert.rejects(importEvidence(ctx, "Reviewer", await readSample("lab-pass")), /Unauthorized/);
      assert.equal((await ctx.registry.getCandidate(ctx.candidateId)).evidenceRevision, 1n);
    } finally { await ctx.connection.close(); }
  });

  it("fingerprints the complete canonical record and detects a changed result or source", async function () {
    const data = validateEvidence(await readSample("lab-pass"));
    if (data.kind !== "lab") throw new Error("Expected lab");
    const r = data.records[0];
    const canonical = canonicalEvidence("lab", data.build, r);
    const digest = keccak256(toUtf8Bytes(canonical));
    assert.notEqual(keccak256(toUtf8Bytes(canonicalEvidence("lab", data.build, { ...r, successes: 40 }))), digest);
    assert.notEqual(keccak256(toUtf8Bytes(canonicalEvidence("lab", data.build, { ...r, source: "different study" }))), digest);
    assert.notEqual(keccak256(toUtf8Bytes(canonicalEvidence("lab", "new-build", r))), digest);
  });

  it("exports an inconclusive result and owned action without claiming approval", async function () {
    const ctx = await createPrototype();
    try {
      await importEvidence(ctx, "Engineer", await readSample("lab-pass"));
      await (await ctx.registry.connect(ctx.actors.Reviewer).approveLimited(ctx.candidateId, hashText("review"), BigInt(await ctx.networkHelpers.time.latest()) + 86400n)).wait();
      await importEvidence(ctx, "Analyst", await readSample("field-inconclusive"));
      const report = await exportReview(ctx);
      assert.equal(report.fieldGate.status, "Inconclusive");
      assert.equal(report.expansionAuthorized, false);
      assert.equal(report.openActions, "1");
      for (const p of report.preimages) assert.equal(keccak256(toUtf8Bytes(p.canonical)), p.digest);
      assert.ok(report.logs.some((l: { event: string }) => l.event === "FieldRecorded"));
    } finally { await ctx.connection.close(); }
  });
});
