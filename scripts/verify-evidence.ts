import { readFile } from "node:fs/promises";
import assert from "node:assert/strict";
import { keccak256, toUtf8Bytes, AbiCoder, Interface } from "ethers";

const path = process.env.REVIEW_FILE ?? "output/demo/review-expanded.json";
const report = JSON.parse(await readFile(path, "utf8"));
assert.equal(report.schema, "safeguard-review-v1");
assert.ok(Array.isArray(report.preimages) && report.preimages.length > 0);
for (const record of report.preimages) {
  assert.equal(keccak256(toUtf8Bytes(record.canonical)), record.digest, `Fingerprint mismatch: ${record.purpose}`);
}
const digests = new Set(report.preimages.map((r: { digest: string }) => r.digest));
const snapshot = keccak256(AbiCoder.defaultAbiCoder().encode(
  ["uint256", "address", "uint256", "bytes32", "bytes32", "uint64", "uint64", "bytes32[]", "bytes32"],
  [report.chainId, report.contract, report.candidateId, report.buildHash, report.scopeHash, report.buildRevision,
    report.evidenceRevision, report.configurations.map((c: { id: string }) => c.id), report.ruleHash],
));
assert.equal(snapshot, report.snapshotHash, "Snapshot does not match the exported candidate and policy");
for (const config of report.configurations) {
  for (const lab of config.labs) if (lab.buildRevision !== "0") assert.ok(digests.has(lab.digest), "Missing lab preimage");
  if (config.field.buildRevision !== "0") assert.ok(digests.has(config.field.digest), "Missing field preimage");
}
const artifact = JSON.parse(await readFile("artifacts/contracts/SafeguardAssurance.sol/SafeguardAssurance.json", "utf8"));
const iface = new Interface(artifact.abi);
for (const log of report.logs) {
  const parsed = iface.parseLog({ topics: log.topics, data: log.data });
  assert.ok(parsed, "Unrecognised event in package");
  if (parsed.name === "LabRecorded" || parsed.name === "FieldRecorded") {
    assert.ok(digests.has(parsed.args.evidence.data.digest), "Historical evidence preimage missing");
  }
}
console.log(`Verified ${report.preimages.length} content fingerprints and current evidence preimages in ${path}.`);
console.log("Candidate snapshot and historical evidence preimages verified against included logs.");
console.log("This checks package integrity only. Verify transaction inclusion and chain provenance separately; it does not prove truthful evidence.");
