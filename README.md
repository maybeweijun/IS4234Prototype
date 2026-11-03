# Safeguard

**Blockchain-based assurance for accountable Autosteer release decisions.**

Safeguard connects validation evidence, field monitoring, independent approvals and corrective actions to a specific software build. Built with Solidity, Hardhat 3 and ethers.js, it provides focused workspaces for engineering, safety and assurance teams.

## Tesla's GRC problem

The report examines **Tesla's December 2023 Autosteer recall (23V838)**. Its central problem is how Tesla should assess safeguards against **foreseeable driver misuse** and use that evidence for **accountable release and corrective-action decisions**.

Installing an OTA remedy does not establish that safeguards remain enabled, keep drivers attentive or reduce risk. The assurance process needs current evidence across software versions and vehicle configurations, independent scrutiny, clear ownership of residual risk and follow-up when post-update concerns emerge.

## How Safeguard addresses it

- **Evidence coverage:** requires accepted, current results for driver attention, mode confusion and operating boundaries across the release's configurations.
- **Independent decisions:** reviewers record a rationale and validity period before limited deployment or expansion is authorised.
- **Reassessment:** software or evidence revisions invalidate earlier authority while preserving the original judgment.
- **Owned follow-up:** adverse or inconclusive field results create actions with deadlines, escalation and independent closure.
- **Traceability:** signed transactions and evidence fingerprints preserve what supported each decision.

These controls block unsupported approvals **within the assurance workflow**. A production release pipeline would enforce the decision before distributing software.

## Run locally

Requires **Node.js 24** and npm.

```sh
npm ci
npm run build
npm start
```

Open **[http://127.0.0.1:4234](http://127.0.0.1:4234)**. Keep the terminal running; `Ctrl+C` stops it. Each start creates a fresh local chain, so export records before stopping.

## User roles

| Role | Main responsibility |
| --- | --- |
| Engineer | Submit laboratory evidence, investigate concerns and revise builds. |
| Field analyst | Submit field comparisons and report safety concerns. |
| Safety reviewer | Assess evidence, approve releases and close actions independently. |
| Safety lead | Oversee ownership, deadlines and escalation. |
| Auditor / observer | Inspect and export the assurance record. |

Each role sees relevant controls. A second reviewer supports cases where the primary reviewer has a conflict.

## Verify and explore

```sh
npm test                   # 56 automated tests
npm run demo               # Complete scripted decision cycle
npm run verify:evidence    # Exported fingerprint and snapshot checks
```

See the [user guide](./docs/user-guide.html), [solution design](./docs/solution.html), [UML diagrams](./docs/uml/) and [presenter guide](./docs/presenter-guide.html).

## Prototype limits

The application uses synthetic records and selectable test identities on a resettable local EVM. It does not control vehicles or deliver OTA updates.

Blockchain cannot establish whether submitted evidence is truthful. Production use needs authenticated identities, protected evidence storage, independently governed infrastructure and release enforcement. Passing the configured rules means **eligible for reviewer assessment**, not proof of safety or regulatory approval.
