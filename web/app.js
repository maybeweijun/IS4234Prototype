const $ = (id) => document.getElementById(id);
let state;
let busy = false;
const purposes = { Engineer: "Own validation evidence and candidate build changes", Reviewer: "Review evidence, decide release eligibility and close actions", Analyst: "Submit field comparisons and report safety concerns", SafetyLead: "Oversee unresolved risks, deadlines and escalations", SecondReviewer: "Provide independent review when the first reviewer has a conflict", Observer: "Inspect and export the assurance record without changing it" };
const workspaceNames = { Engineer: "Engineering workspace", Reviewer: "Independent safety review", Analyst: "Field monitoring workspace", SafetyLead: "Safety oversight", SecondReviewer: "Independent safety review", Observer: "Audit and assurance" };
const actionHelp = {
  Engineer: "These investigations are assigned to you. Investigate the concern and submit revised evidence; an independent reviewer must assess and close it.",
  Reviewer: "Assess resolution evidence and record an independent closure rationale. Closing an action does not approve a release; the decision in section 03 is separate.",
  SecondReviewer: "Assess resolution evidence independently. You can close a concern reported by the primary reviewer if you have no contributor conflict.",
  Analyst: "Monitor the concerns your evidence creates. Improved field results do not automatically close an investigation; closure belongs to an independent reviewer.",
  SafetyLead: "Monitor ownership and deadlines, then escalate overdue actions. You oversee follow-up; independent reviewers retain responsibility for closure and release judgments.",
  Observer: "Read the owner, deadline and disposition of each investigation. This view provides traceability without investigation or approval controls.",
};
const escape = (v) => String(v).replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const short = (v) => `${String(v).slice(0, 14)}…${String(v).slice(-8)}`;
const date = (v) => new Date(Number(v) * 1000).toLocaleString();
const badge = (value) => `<span class="pill ${value.startsWith("Eligible") ? "good" : ["Failed", "Stale", "Reopened"].includes(value) ? "bad" : ""}">${escape(value)}</span>`;
function actor() {
  const role = $("actor").value;
  $("actor-purpose").textContent = purposes[role];
  $("actor-address").textContent = state?.actors[role] ?? "";
  $("workspace-title").textContent = workspaceNames[role];
  $("workspace-description").textContent = purposes[role] + ". Only the sections relevant to this responsibility are shown.";
  document.querySelectorAll("[data-roles]").forEach(element => { element.hidden = !element.dataset.roles.split(" ").includes(role); });
  document.querySelectorAll(".adaptive-grid").forEach(grid => {
    const visible = [...grid.children].filter(element => !element.hidden).length;
    grid.hidden = visible === 0;
    grid.classList.toggle("single-column", visible === 1);
  });
  const kind = role === "Engineer" ? "lab" : "field";
  const options = [...$("sample").options];
  for (const option of options) { option.hidden = option.dataset.kind !== kind; option.disabled = option.hidden; }
  if ((role === "Engineer" || role === "Analyst") && $("sample").selectedOptions[0].disabled) {
    $("sample").value = options.find(option => !option.disabled).value;
    loadSample().catch(error => message(error.message, true));
  }
  $("ingestion-eyebrow").textContent = role === "Engineer" ? "02 / LABORATORY VALIDATION" : "02 / FIELD MONITORING";
  $("ingestion-title").textContent = role === "Engineer" ? "Submit validation evidence" : "Submit a field comparison";
  $("ingestion-help").textContent = role === "Engineer"
    ? "Record how each safeguard performed in the required test scenarios and configurations. Missing, failed or outdated results prevent independent approval."
    : "Compare baseline and post-update event rates, exposure and data quality for each configuration. Field evidence requires an earlier limited decision for the current build; adverse or inconclusive results create actions.";
  $("coverage-title").textContent = role === "Analyst" ? "Field comparison results" : role === "Engineer" ? "Required validation coverage" : "Validation and field evidence";
  $("coverage-help").textContent = role === "Engineer"
    ? "Confirm that every required scenario has accepted, current-build evidence for each configuration. Each row explains any gap that blocks review."
    : role === "Analyst" ? "Inspect changes in event rates alongside exposure and quality. Missing data stays unknown; eligibility is not proof of effectiveness."
    : "Examine laboratory coverage and post-update field comparisons together before assessing a decision. The explanations distinguish missing evidence, failure and uncertainty.";
  $("actions-help").textContent = actionHelp[role];
  $("actions-title").textContent = role === "Engineer" ? "Your assigned investigations" : role === "SafetyLead" ? "Ownership, deadlines and escalation" : "Investigations and follow-up";
  if (state) {
    const limitedBefore = state.decisions.some(d => d.stage === "Limited" && d.buildRevision === state.buildRevision);
    const labsReady = state.labGate.status.startsWith("Eligible");
    const fieldsReady = state.fieldGate.status.startsWith("Eligible");
    const open = Number(state.openActions) > 0;
    const next = role === "Engineer" ? open ? "Investigate your assigned concern and provide revised evidence for independent assessment." : state.expansionAuthorized ? "The current build has expansion authority. Monitor assigned concerns and record material build changes." : !labsReady ? "Submit current validation results for every required scenario and configuration." : "Validation coverage is complete. The independent reviewer can assess a limited decision."
      : role === "Analyst" ? !limitedBefore ? "Wait for a limited decision for this build before submitting field evidence." : "Submit a comparable field record and explain any credible adverse signal."
      : role === "SafetyLead" ? open ? "Inspect unresolved actions and escalate any overdue investigation." : "Monitor evidence gaps and current authority; raise any significant safety concern."
      : role === "Observer" ? "Inspect the history and confirmed events, then export a review package."
      : open ? "Assess resolution evidence and independently close concerns before a new release decision." : state.expansionAuthorized ? "The current expansion decision is valid. Monitor new evidence and any emerging concerns." : !labsReady ? "Inspect the evidence gaps. A release decision is blocked until validation is eligible." : limitedBefore && fieldsReady ? "Review the complete evidence and record a separate expansion judgment." : "Assess the validation evidence and record a time-limited decision if justified.";
    $("next-step").textContent = next;
  }
}
function render(s) {
  state = s;
  actor();
  $("candidate-title").textContent = s.build;
  $("scope").textContent = s.scope;
  $("stage").textContent = s.stage;
  $("meta").innerHTML = `<span>Build revision <strong>${escape(s.buildRevision)}</strong></span><span>Evidence revision <strong>${escape(s.evidenceRevision)}</strong></span><span>Chain time ${escape(date(s.chainTime))}</span><span title="${escape(s.contract)}">Contract ${escape(short(s.contract))}</span><span title="${escape(s.snapshotHash)}">Snapshot ${escape(short(s.snapshotHash))}</span>`;
  const stats = [
    ["Laboratory gate", s.labGate.status, s.labGate.reason],
    ["Field gate", s.fieldGate.status, s.fieldGate.reason],
    ["Open actions", s.openActions, "Independent closure and a new decision are required"],
    ["Deployment authority", s.expansionAuthorized ? "Expansion authorized" : s.limitedAuthorized ? "Limited only" : "No current authority", "Exact candidate snapshot, scope and time window"],
  ];
  $("stats").innerHTML = stats.map(([title, value, detail]) => `<article class="stat"><small>${escape(title)}</small><strong>${escape(value)}</strong><p>${escape(detail)}</p></article>`).join("");
  $("labs").innerHTML = s.configurations.flatMap(c => c.labs.map(l => `<tr><td>${escape(c.label)}</td><td>${escape(l.scenario)}</td><td>${l.buildRevision === "0" ? "No result" : `${escape(l.successes)} / ${escape(l.trials)}`}</td><td>${badge(l.gate.status)}</td><td>${escape(l.gate.reason)}</td></tr>`)).join("");
  const rate = (events, miles) => Number(miles) > 0 ? (Number(events) / Number(miles) * 1000).toFixed(3) : "Unknown";
  $("fields").innerHTML = s.configurations.map(c => `<article class="field-card"><h3>${escape(c.label)} / field comparison</h3>${badge(c.field.gate.status)}<div class="rates">${rate(c.field.baselineEvents, c.field.baselineMiles)} → ${rate(c.field.postEvents, c.field.postMiles)} <span>events / 1,000 engaged miles</span></div><p>${escape(c.field.gate.reason)}</p><p>Exposure: ${escape(c.field.baselineMiles)} baseline / ${escape(c.field.postMiles)} post-update miles</p></article>`).join("");
  $("actions").innerHTML = s.actions.length ? s.actions.map(a => `<article class="action"><strong>Action ${escape(a.id)} · ${a.closed ? "Closed" : a.overdue ? "Overdue" : "Open"}${a.escalated ? " · Escalated" : ""}</strong><p>${escape(a.reason)}<br>Owner: ${escape(short(a.owner))}<br>Due: ${escape(date(a.dueAt))}</p></article>`).join("") : '<p class="empty">No corrective actions recorded. Adverse or inconclusive field evidence creates one automatically.</p>';
  $("decisions").innerHTML = s.decisions.length ? s.decisions.map(d => `<article class="decision"><strong>${escape(d.stage)} / decision ${Number(d.index) + 1}</strong><p>Build revision ${escape(d.buildRevision)}, evidence revision ${escape(d.evidenceRevision)}<br>Reviewer: ${escape(short(d.reviewer))}<br>Valid until ${escape(date(d.validUntil))}</p><p class="fingerprint">Snapshot ${escape(d.snapshotHash)}</p></article>`).join("") : '<p class="empty">No release decisions yet. <strong>Evidence eligibility requires an independent reviewer judgment.</strong></p>';
  $("events").innerHTML = s.logs.slice().reverse().map(l => `<tr><td>${escape(l.blockNumber)}</td><td>${escape(l.event)}</td><td class="fingerprint" title="${escape(l.transactionHash)}">${escape(l.transactionHash)}</td></tr>`).join("");
  $("requests").innerHTML = s.requestLog.slice().reverse().map(r => `<p>${escape(r.actor)} / ${escape(r.command)}: ${escape(r.outcome)}</p>`).join("") || '<p class="caption">No requests yet.</p>';
}
async function refresh() {
  const response = await fetch("/api/state");
  if (!response.ok) throw new Error("Cannot read local chain state");
  render(await response.json());
}
async function loadSample() {
  const response = await fetch(`/api/sample?name=${encodeURIComponent($("sample").value)}`);
  if (!response.ok) throw new Error("Cannot load example");
  $("evidence").value = JSON.stringify(await response.json(), null, 2);
}
function message(text, error = false) { $("feedback").textContent = text; $("feedback").className = error ? "error" : ""; }
function explainError(text) {
  if (text.includes("GateBlocked")) return "Approval blocked: required evidence is missing, outdated, failed or inconclusive. Review the explanations in section 04.";
  if (text.includes("OpenActions")) return "Approval blocked: unresolved corrective actions require independent closure before a new release decision.";
  if (text.includes("SeparationOfDuties")) return "Independent review required: the reviewer cannot be a candidate data contributor or close a concern they reported.";
  if (text.includes("Unauthorized")) return "This action is not permitted for the selected role.";
  if (text.includes("NotOverdue")) return "This action is not overdue yet. Escalation becomes available after its due date.";
  if (text.includes("InvalidStage")) return "This step is unavailable at the current stage. Field monitoring requires a limited decision for the current build.";
  if (text.includes("AlreadyClosed")) return "This corrective action is already closed.";
  if (text.includes("AlreadyEscalated")) return "This corrective action has already been escalated.";
  return text;
}
async function command(command) {
  if (busy) return;
  busy = true;
  document.querySelectorAll("button").forEach(b => b.disabled = true);
  message("Submitting to the local EVM. Waiting for confirmed state…");
  try {
    let rationale = $("rationale").value;
    if (command === "close") rationale = $("closure-rationale").value;
    if (command === "revise") rationale = $("build-rationale").value;
    if (command === "concern" && ["Analyst", "SafetyLead"].includes($("actor").value)) rationale = $("concern-description").value;
    const payload = { command, actor: $("actor").value, rationale, resolution: $("resolution").value, actionId: $("action-id").value, build: $("build").value, days: Number($("days").value) };
    if (command === "import") payload.evidence = JSON.parse($("evidence").value);
    const response = await fetch("/api/action", { method: "POST", headers: { "Content-Type": "application/json", "X-Demo-Request": "1" }, body: JSON.stringify(payload) });
    const result = await response.json();
    if (!response.ok) throw new Error(result.error);
    message(result.transaction ? `Transaction confirmed: ${result.transaction}` : result.transactions ? `${result.transactions.length} evidence transactions confirmed.` : result.message);
  } catch (error) { message(`Request rejected: ${explainError(error.message)}`, true); }
  finally {
    try { await refresh(); } catch (error) { message(error.message, true); }
    busy = false;
    document.querySelectorAll("button").forEach(b => b.disabled = false);
  }
}
$("actor").addEventListener("change", () => { sessionStorage.setItem("safeguard-role", $("actor").value); actor(); message(`${workspaceNames[$("actor").value]} selected. Review the recommended next step above.`); });
$("refresh").addEventListener("click", () => refresh().catch(e => message(e.message, true)));
$("load-sample").addEventListener("click", () => loadSample().catch(e => message(e.message, true)));
$("import").addEventListener("click", () => command("import"));
document.querySelectorAll("[data-command]").forEach(b => b.addEventListener("click", () => command(b.dataset.command)));
const savedRole = sessionStorage.getItem("safeguard-role");
if (Object.hasOwn(purposes, savedRole)) $("actor").value = savedRole;
actor();
Promise.all([refresh(), loadSample()]).then(() => message("Workspace connected. Review the recommended next step for your role.")).catch(e => message(e.message, true));
