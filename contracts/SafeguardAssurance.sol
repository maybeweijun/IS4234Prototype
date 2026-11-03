// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/// @title Autosteer Safeguard Assurance Registry
/// @notice Prototype GRC workflow. Eligibility is not a safety or regulatory certification.
/// @dev No vehicle control, tokens, payments, upgrade proxy, or confidential documents.
contract SafeguardAssurance {
    enum Role { None, Engineer, Reviewer, Analyst, SafetyLead }
    enum Stage { Draft, Limited, Expanded, Reopened }
    enum GateStatus { Missing, Stale, Inconclusive, Failed, Eligible }
    enum Reason {
        None, MissingEvidence, WrongBuild, InsufficientTrials, LowSuccess,
        UnacceptedEvidence, InsufficientExposure, IncompleteData,
        IncomparableCohorts, InactiveSafeguards, SeriousEvent, RateIncrease
    }

    uint8 public constant SCENARIO_COUNT = 3;
    uint8 public constant MAX_CONFIGURATIONS = 8;
    uint32 public constant MIN_TRIALS = 30;
    uint32 public constant MIN_SUCCESS_PERCENT = 95;
    uint64 public constant MIN_MILES = 1000;
    uint64 public constant ACTION_WINDOW = 7 days;
    uint64 public constant MAX_APPROVAL_AGE = 30 days;
    bytes32 public constant RULE_HASH = keccak256("SAFEGUARD-v1:3-scenarios;30-trials;95-percent;1000-miles;no-rate-increase;7d-action;30d-approval");

    struct Candidate {
        address engineer;
        bytes32 buildHash;
        bytes32 scopeHash;
        uint64 buildRevision;
        uint64 evidenceRevision;
        uint64 openActions;
        Stage stage;
        bool limitedEver;
    }
    struct LabInput {
        uint32 trials;
        uint32 successes;
        bool accepted;
        bytes32 digest;
    }
    struct LabEvidence {
        uint64 buildRevision;
        address submitter;
        LabInput data;
    }
    struct FieldInput {
        uint64 baselineEvents;
        uint64 baselineMiles;
        uint64 postEvents;
        uint64 postMiles;
        bool complete;
        bool comparable;
        bool safeguardsEnabled;
        bool seriousEvent;
        bytes32 digest;
    }
    struct FieldEvidence {
        uint64 buildRevision;
        address submitter;
        FieldInput data;
    }
    struct Gate {
        GateStatus status;
        Reason reason;
        bytes32 configuration;
        uint8 scenario;
    }
    struct Decision {
        Stage stage;
        uint64 buildRevision;
        uint64 evidenceRevision;
        uint64 decidedAt;
        uint64 validUntil;
        address reviewer;
        bytes32 snapshotHash;
        bytes32 rationaleHash;
    }
    struct Action {
        uint256 candidateId;
        address owner;
        address reporter;
        uint64 openedAt;
        uint64 dueAt;
        Reason reason;
        bytes32 evidenceHash;
        bool escalated;
        bool closed;
        address closedBy;
        bytes32 resolutionHash;
        bytes32 closureRationaleHash;
    }

    address public immutable safetyLead;
    uint256 public candidateCount;
    uint256 public actionCount;
    mapping(address => Role) public roles;
    mapping(uint256 => Candidate) private candidates;
    mapping(uint256 => bytes32[]) private configurations;
    mapping(uint256 => mapping(bytes32 => bool)) private inScope;
    mapping(uint256 => mapping(bytes32 => mapping(uint8 => LabEvidence))) private labs;
    mapping(uint256 => mapping(bytes32 => FieldEvidence)) private fields;
    // Persists across role changes: a data contributor cannot later review the same candidate.
    mapping(uint256 => mapping(address => bool)) public contributors;
    mapping(uint256 => Decision[]) private decisions;
    mapping(uint256 => Action) private actions;

    error Unauthorized();
    error InvalidInput();
    error UnknownCandidate();
    error UnknownAction();
    error WrongBuild();
    error OutOfScope();
    error SeparationOfDuties();
    error GateBlocked(GateStatus status, Reason reason, bytes32 configuration, uint8 scenario);
    error OpenActions(uint64 count);
    error InvalidStage();
    error NotOverdue();
    error AlreadyClosed();
    error AlreadyEscalated();

    event RoleAssigned(address indexed account, Role role, address indexed actor);
    event CandidateCreated(uint256 indexed id, address indexed engineer, bytes32 buildHash, bytes32 scopeHash, bytes32[] configurations);
    event BuildRevised(uint256 indexed id, bytes32 buildHash, uint64 buildRevision, bytes32 rationaleHash);
    event ReviewReopened(uint256 indexed id, uint64 evidenceRevision);
    event LabRecorded(uint256 indexed id, bytes32 indexed configuration, uint8 indexed scenario, LabEvidence evidence);
    event FieldRecorded(uint256 indexed id, bytes32 indexed configuration, FieldEvidence evidence, Gate gate);
    event DecisionRecorded(uint256 indexed id, uint256 indexed decisionIndex, Decision decision);
    event ActionOpened(uint256 indexed actionId, uint256 indexed candidateId, address indexed owner, address reporter, uint64 dueAt, Reason reason, bytes32 evidenceHash);
    event ActionEscalated(uint256 indexed actionId, address indexed safetyLead, address indexed caller);
    event ActionClosed(uint256 indexed actionId, address indexed reviewer, bytes32 resolutionHash, bytes32 rationaleHash);

    constructor(address lead) {
        if (lead == address(0)) revert InvalidInput();
        safetyLead = lead;
        roles[lead] = Role.SafetyLead;
        emit RoleAssigned(lead, Role.SafetyLead, msg.sender);
    }

    modifier onlyRole(Role role) {
        if (roles[msg.sender] != role) revert Unauthorized();
        _;
    }

    /// @notice One active role per address. Human independence still requires organisational controls.
    function setRole(address account, Role role) external {
        if (msg.sender != safetyLead) revert Unauthorized();
        if (account == address(0) || account == safetyLead || role == Role.SafetyLead) revert InvalidInput();
        roles[account] = role;
        emit RoleAssigned(account, role, msg.sender);
    }

    /// @notice Scope and required scenarios are fixed before evidence is examined.
    function createCandidate(bytes32 buildHash, bytes32 scopeHash, bytes32[] calldata configs)
        external onlyRole(Role.Engineer) returns (uint256 id)
    {
        if (buildHash == bytes32(0) || scopeHash == bytes32(0) || configs.length == 0 || configs.length > MAX_CONFIGURATIONS) revert InvalidInput();
        id = ++candidateCount;
        for (uint256 i; i < configs.length; ++i) {
            if (configs[i] == bytes32(0) || inScope[id][configs[i]]) revert InvalidInput();
            inScope[id][configs[i]] = true;
            configurations[id].push(configs[i]);
        }
        candidates[id] = Candidate(msg.sender, buildHash, scopeHash, 1, 1, 0, Stage.Draft, false);
        contributors[id][msg.sender] = true;
        emit CandidateCreated(id, msg.sender, buildHash, scopeHash, configs);
    }

    function reviseBuild(uint256 id, bytes32 buildHash, bytes32 rationaleHash) external onlyRole(Role.Engineer) {
        Candidate storage c = _candidate(id);
        if (msg.sender != c.engineer) revert Unauthorized();
        if (buildHash == bytes32(0) || buildHash == c.buildHash || rationaleHash == bytes32(0)) revert InvalidInput();
        c.buildHash = buildHash;
        ++c.buildRevision;
        c.limitedEver = false;
        _changed(id, c);
        emit BuildRevised(id, buildHash, c.buildRevision, rationaleHash);
    }

    function recordLab(uint256 id, bytes32 configuration, uint8 scenario, bytes32 buildHash, LabInput calldata data)
        external onlyRole(Role.Engineer)
    {
        Candidate storage c = _candidate(id);
        if (msg.sender != c.engineer) revert Unauthorized();
        _checkScope(id, configuration);
        if (scenario >= SCENARIO_COUNT || data.digest == bytes32(0) || data.successes > data.trials) revert InvalidInput();
        if (buildHash != c.buildHash) revert WrongBuild();
        labs[id][configuration][scenario] = LabEvidence(c.buildRevision, msg.sender, data);
        _changed(id, c);
        emit LabRecorded(id, configuration, scenario, labs[id][configuration][scenario]);
    }

    /// @notice Data are analyst attestations, not cryptographically proven telemetry.
    function recordField(uint256 id, bytes32 configuration, bytes32 buildHash, FieldInput calldata data)
        external onlyRole(Role.Analyst)
    {
        Candidate storage c = _candidate(id);
        _checkScope(id, configuration);
        if (!c.limitedEver) revert InvalidStage();
        if (buildHash != c.buildHash) revert WrongBuild();
        if (data.digest == bytes32(0)) revert InvalidInput();
        fields[id][configuration] = FieldEvidence(c.buildRevision, msg.sender, data);
        contributors[id][msg.sender] = true;
        _changed(id, c);
        Gate memory gate = fieldCheck(id, configuration);
        emit FieldRecorded(id, configuration, fields[id][configuration], gate);
        if (gate.status != GateStatus.Eligible) _openAction(id, c, gate.reason, data.digest);
    }

    function labCheck(uint256 id, bytes32 configuration, uint8 scenario) public view returns (Gate memory) {
        Candidate storage c = _candidate(id);
        _checkScope(id, configuration);
        if (scenario >= SCENARIO_COUNT) revert InvalidInput();
        LabEvidence storage e = labs[id][configuration][scenario];
        if (e.buildRevision == 0) return Gate(GateStatus.Missing, Reason.MissingEvidence, configuration, scenario);
        if (e.buildRevision != c.buildRevision) return Gate(GateStatus.Stale, Reason.WrongBuild, configuration, scenario);
        if (!e.data.accepted) return Gate(GateStatus.Inconclusive, Reason.UnacceptedEvidence, configuration, scenario);
        if (e.data.trials < MIN_TRIALS) return Gate(GateStatus.Inconclusive, Reason.InsufficientTrials, configuration, scenario);
        if (uint256(e.data.successes) * 100 < uint256(e.data.trials) * MIN_SUCCESS_PERCENT)
            return Gate(GateStatus.Failed, Reason.LowSuccess, configuration, scenario);
        return Gate(GateStatus.Eligible, Reason.None, configuration, scenario);
    }

    function labGate(uint256 id) public view returns (Gate memory) {
        _candidate(id);
        for (uint256 i; i < configurations[id].length; ++i) {
            for (uint8 s; s < SCENARIO_COUNT; ++s) {
                Gate memory gate = labCheck(id, configurations[id][i], s);
                if (gate.status != GateStatus.Eligible) return gate;
            }
        }
        return Gate(GateStatus.Eligible, Reason.None, bytes32(0), 0);
    }

    function fieldCheck(uint256 id, bytes32 configuration) public view returns (Gate memory) {
        Candidate storage c = _candidate(id);
        _checkScope(id, configuration);
        FieldEvidence storage e = fields[id][configuration];
        Gate memory gate = Gate(GateStatus.Eligible, Reason.None, configuration, 0);
        if (e.buildRevision == 0) return Gate(GateStatus.Missing, Reason.MissingEvidence, configuration, 0);
        if (e.buildRevision != c.buildRevision) return Gate(GateStatus.Stale, Reason.WrongBuild, configuration, 0);
        FieldInput storage d = e.data;
        // Credible serious concerns take priority even when exposure/comparability are poor.
        if (d.seriousEvent) return Gate(GateStatus.Failed, Reason.SeriousEvent, configuration, 0);
        if (!d.safeguardsEnabled) return Gate(GateStatus.Failed, Reason.InactiveSafeguards, configuration, 0);
        if (!d.complete) return Gate(GateStatus.Inconclusive, Reason.IncompleteData, configuration, 0);
        if (!d.comparable) return Gate(GateStatus.Inconclusive, Reason.IncomparableCohorts, configuration, 0);
        if (d.baselineMiles < MIN_MILES || d.postMiles < MIN_MILES)
            return Gate(GateStatus.Inconclusive, Reason.InsufficientExposure, configuration, 0);
        // Compare exact rational rates, avoiding division, rounding and uint64 overflow.
        if (uint256(d.postEvents) * d.baselineMiles > uint256(d.baselineEvents) * d.postMiles)
            return Gate(GateStatus.Failed, Reason.RateIncrease, configuration, 0);
        return gate;
    }

    function fieldGate(uint256 id) public view returns (Gate memory) {
        _candidate(id);
        for (uint256 i; i < configurations[id].length; ++i) {
            Gate memory gate = fieldCheck(id, configurations[id][i]);
            if (gate.status != GateStatus.Eligible) return gate;
        }
        return Gate(GateStatus.Eligible, Reason.None, bytes32(0), 0);
    }

    function approveLimited(uint256 id, bytes32 rationaleHash, uint64 validUntil) external onlyRole(Role.Reviewer) {
        Candidate storage c = _candidate(id);
        if (c.stage == Stage.Expanded) revert InvalidStage();
        _reviewer(id, c);
        _requireEligible(labGate(id));
        c.limitedEver = true;
        _decide(id, c, Stage.Limited, rationaleHash, validUntil);
    }

    function approveExpansion(uint256 id, bytes32 rationaleHash, uint64 validUntil) external onlyRole(Role.Reviewer) {
        Candidate storage c = _candidate(id);
        _reviewer(id, c);
        if (!c.limitedEver) revert InvalidStage();
        _requireEligible(labGate(id));
        _requireEligible(fieldGate(id));
        _decide(id, c, Stage.Expanded, rationaleHash, validUntil);
    }

    /// @notice Protected escalation does not require the engineer's permission.
    function reportConcern(uint256 id, bytes32 evidenceHash) external returns (uint256) {
        Role r = roles[msg.sender];
        if (r != Role.Analyst && r != Role.Reviewer && r != Role.SafetyLead) revert Unauthorized();
        Candidate storage c = _candidate(id);
        if (evidenceHash == bytes32(0)) revert InvalidInput();
        _changed(id, c);
        return _openAction(id, c, Reason.SeriousEvent, evidenceHash);
    }

    /// @notice Anyone may materialise the escalation event; time never sends transactions itself.
    function escalateOverdue(uint256 actionId) external {
        Action storage a = _action(actionId);
        if (a.closed) revert AlreadyClosed();
        if (a.escalated) revert AlreadyEscalated();
        if (block.timestamp <= a.dueAt) revert NotOverdue();
        a.escalated = true;
        emit ActionEscalated(actionId, safetyLead, msg.sender);
    }

    /// @notice Resolution is an attributable human judgment. Closure never grants deployment authority.
    function closeAction(uint256 actionId, bytes32 resolutionHash, bytes32 rationaleHash) external onlyRole(Role.Reviewer) {
        Action storage a = _action(actionId);
        if (a.closed) revert AlreadyClosed();
        if (contributors[a.candidateId][msg.sender] || msg.sender == a.owner || msg.sender == a.reporter) revert SeparationOfDuties();
        if (resolutionHash == bytes32(0) || rationaleHash == bytes32(0)) revert InvalidInput();
        a.closed = true;
        a.closedBy = msg.sender;
        a.resolutionHash = resolutionHash;
        a.closureRationaleHash = rationaleHash;
        Candidate storage c = candidates[a.candidateId];
        --c.openActions;
        _changed(a.candidateId, c);
        emit ActionClosed(actionId, msg.sender, resolutionHash, rationaleHash);
    }

    /// @notice A release pipeline must check this exact build, scope and stage before deployment.
    /// @dev Caller supplies id/stage; pipeline must independently match its artifact to getCandidate(id).
    function isDeploymentAuthorized(uint256 id, Stage requiredStage) external view returns (bool) {
        Candidate storage c = _candidate(id);
        if (requiredStage != Stage.Limited && requiredStage != Stage.Expanded) return false;
        uint256 n = decisions[id].length;
        if (n == 0 || c.openActions != 0 || (c.stage != Stage.Limited && c.stage != Stage.Expanded)) return false;
        Decision storage d = decisions[id][n - 1];
        return (requiredStage == Stage.Limited || c.stage == Stage.Expanded)
            && d.evidenceRevision == c.evidenceRevision && d.buildRevision == c.buildRevision
            && block.timestamp < d.validUntil && roles[d.reviewer] == Role.Reviewer;
    }

    function snapshotHash(uint256 id) public view returns (bytes32) {
        Candidate storage c = _candidate(id);
        return keccak256(abi.encode(block.chainid, address(this), id, c.buildHash, c.scopeHash,
            c.buildRevision, c.evidenceRevision, configurations[id], RULE_HASH));
    }

    function getCandidate(uint256 id) external view returns (Candidate memory) { return _candidate(id); }
    function getConfigurations(uint256 id) external view returns (bytes32[] memory) { _candidate(id); return configurations[id]; }
    function getLab(uint256 id, bytes32 config, uint8 scenario) external view returns (LabEvidence memory) {
        _candidate(id); _checkScope(id, config); if (scenario >= SCENARIO_COUNT) revert InvalidInput(); return labs[id][config][scenario];
    }
    function getField(uint256 id, bytes32 config) external view returns (FieldEvidence memory) {
        _candidate(id); _checkScope(id, config); return fields[id][config];
    }
    function decisionCount(uint256 id) external view returns (uint256) { _candidate(id); return decisions[id].length; }
    function getDecision(uint256 id, uint256 index) external view returns (Decision memory) { _candidate(id); return decisions[id][index]; }
    function getAction(uint256 actionId) external view returns (Action memory) { return _action(actionId); }
    function isOverdue(uint256 actionId) external view returns (bool) {
        Action storage a = _action(actionId); return !a.closed && block.timestamp > a.dueAt;
    }

    function _candidate(uint256 id) private view returns (Candidate storage c) {
        c = candidates[id]; if (c.engineer == address(0)) revert UnknownCandidate();
    }
    function _action(uint256 id) private view returns (Action storage a) {
        a = actions[id]; if (a.owner == address(0)) revert UnknownAction();
    }
    function _checkScope(uint256 id, bytes32 config) private view { if (!inScope[id][config]) revert OutOfScope(); }
    function _requireEligible(Gate memory g) private pure {
        if (g.status != GateStatus.Eligible) revert GateBlocked(g.status, g.reason, g.configuration, g.scenario);
    }
    function _reviewer(uint256 id, Candidate storage c) private view {
        if (contributors[id][msg.sender]) revert SeparationOfDuties();
        if (c.openActions != 0) revert OpenActions(c.openActions);
    }
    function _changed(uint256 id, Candidate storage c) private {
        ++c.evidenceRevision;
        if (c.stage != Stage.Draft) {
            c.stage = Stage.Reopened;
            emit ReviewReopened(id, c.evidenceRevision);
        }
    }
    function _decide(uint256 id, Candidate storage c, Stage stage, bytes32 rationaleHash, uint64 validUntil) private {
        if (rationaleHash == bytes32(0) || validUntil <= block.timestamp || validUntil > block.timestamp + MAX_APPROVAL_AGE) revert InvalidInput();
        c.stage = stage;
        Decision memory d = Decision(stage, c.buildRevision, c.evidenceRevision, uint64(block.timestamp), validUntil, msg.sender, snapshotHash(id), rationaleHash);
        decisions[id].push(d);
        emit DecisionRecorded(id, decisions[id].length - 1, d);
    }
    function _openAction(uint256 id, Candidate storage c, Reason reason, bytes32 evidenceHash) private returns (uint256 actionId) {
        actionId = ++actionCount;
        uint64 dueAt = uint64(block.timestamp) + ACTION_WINDOW;
        actions[actionId] = Action(id, c.engineer, msg.sender, uint64(block.timestamp), dueAt, reason, evidenceHash, false, false, address(0), bytes32(0), bytes32(0));
        ++c.openActions;
        emit ActionOpened(actionId, id, c.engineer, msg.sender, dueAt, reason, evidenceHash);
    }
}
