// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {SafeguardAssurance as SA} from "./SafeguardAssurance.sol";

contract SafeguardAssuranceTest is Test {
    SA registry;
    address engineer = address(0x1001);
    address reviewer = address(0x2002);
    address analyst = address(0x3003);
    address stranger = address(0x4004);
    bytes32 constant BUILD = keccak256("synthetic-build-1");
    bytes32 constant CONFIG = keccak256("HW3-enabled");
    bytes32 constant OTHER = keccak256("HW4-enabled");
    bytes32 constant DIGEST = keccak256("synthetic-evidence");
    uint256 id;

    function setUp() public {
        registry = new SA(address(this));
        registry.setRole(engineer, SA.Role.Engineer);
        registry.setRole(reviewer, SA.Role.Reviewer);
        registry.setRole(analyst, SA.Role.Analyst);
        bytes32[] memory configs = new bytes32[](2);
        configs[0] = CONFIG;
        configs[1] = OTHER;
        vm.prank(engineer);
        id = registry.createCandidate(BUILD, keccak256("scope"), configs);
    }

    function _lab(bytes32 config, uint8 scenario, uint32 trials, uint32 successes, bool accepted) private {
        vm.prank(engineer);
        registry.recordLab(id, config, scenario, BUILD, SA.LabInput(trials, successes, accepted, DIGEST));
    }
    function _allLabs() private {
        for (uint8 s; s < 3; ++s) {
            _lab(CONFIG, s, 40, 39, true);
            _lab(OTHER, s, 40, 39, true);
        }
    }
    function _limited() private {
        _allLabs();
        vm.prank(reviewer);
        registry.approveLimited(id, DIGEST, uint64(block.timestamp + 1 days));
    }
    function _goodField() private pure returns (SA.FieldInput memory) {
        return SA.FieldInput(8, 4000, 6, 4000, true, true, true, false, DIGEST);
    }
    function _field(bytes32 config, SA.FieldInput memory data) private {
        vm.prank(analyst);
        registry.recordField(id, config, BUILD, data);
    }
    function _expanded() private {
        _limited();
        _field(CONFIG, _goodField());
        _field(OTHER, _goodField());
        vm.prank(reviewer);
        registry.approveExpansion(id, DIGEST, uint64(block.timestamp + 1 days));
    }
    function _concern() private returns (uint256 actionId) {
        vm.prank(analyst);
        return registry.reportConcern(id, DIGEST);
    }
    function _assertGate(SA.Gate memory gate, SA.GateStatus status, SA.Reason reason) private pure {
        assertEq(uint256(gate.status), uint256(status));
        assertEq(uint256(gate.reason), uint256(reason));
    }

    function test_MissingEvidenceIdentifiesConfigurationAndScenario() public view {
        SA.Gate memory gate = registry.labGate(id);
        _assertGate(gate, SA.GateStatus.Missing, SA.Reason.MissingEvidence);
        assertEq(gate.configuration, CONFIG);
        assertEq(gate.scenario, 0);
    }
    function test_AllConfigurationsAreRequired() public {
        for (uint8 s; s < 3; ++s) _lab(CONFIG, s, 40, 39, true);
        assertEq(registry.labGate(id).configuration, OTHER);
    }
    function test_MissingLabBlocksApproval() public {
        vm.prank(reviewer);
        vm.expectRevert(abi.encodeWithSelector(SA.GateBlocked.selector, SA.GateStatus.Missing, SA.Reason.MissingEvidence, CONFIG, uint8(0)));
        registry.approveLimited(id, DIGEST, uint64(block.timestamp + 1 days));
    }
    function test_LowTrialCountIsInconclusive() public {
        _lab(CONFIG, 0, 29, 29, true);
        _assertGate(registry.labCheck(id, CONFIG, 0), SA.GateStatus.Inconclusive, SA.Reason.InsufficientTrials);
    }
    function test_UnacceptedLabIsInconclusive() public {
        _lab(CONFIG, 0, 40, 40, false);
        _assertGate(registry.labCheck(id, CONFIG, 0), SA.GateStatus.Inconclusive, SA.Reason.UnacceptedEvidence);
    }
    function test_FailedLabIsDistinctFromMissing() public {
        _lab(CONFIG, 0, 40, 37, true);
        _assertGate(registry.labCheck(id, CONFIG, 0), SA.GateStatus.Failed, SA.Reason.LowSuccess);
    }
    function test_ExactSuccessBoundaryPasses() public {
        _lab(CONFIG, 0, 100, 95, true);
        _assertGate(registry.labCheck(id, CONFIG, 0), SA.GateStatus.Eligible, SA.Reason.None);
    }
    function test_InvalidCountsRevert() public {
        vm.prank(engineer);
        vm.expectRevert(SA.InvalidInput.selector);
        registry.recordLab(id, CONFIG, 0, BUILD, SA.LabInput(30, 31, true, DIGEST));
    }
    function test_OldBuildImportReverts() public {
        vm.prank(engineer);
        vm.expectRevert(SA.WrongBuild.selector);
        registry.recordLab(id, CONFIG, 0, keccak256("old"), SA.LabInput(40, 39, true, DIGEST));
    }
    function test_UnknownConfigurationReverts() public {
        vm.expectRevert(SA.OutOfScope.selector);
        registry.labCheck(id, keccak256("not-in-scope"), 0);
    }
    function test_UnknownScenarioReverts() public {
        vm.expectRevert(SA.InvalidInput.selector);
        registry.labCheck(id, CONFIG, 3);
    }
    function test_UnauthorizedWriterReverts() public {
        vm.prank(stranger);
        vm.expectRevert(SA.Unauthorized.selector);
        registry.recordLab(id, CONFIG, 0, BUILD, SA.LabInput(40, 39, true, DIGEST));
    }
    function test_OnlyAssignedEngineerCanWrite() public {
        registry.setRole(stranger, SA.Role.Engineer);
        vm.prank(stranger);
        vm.expectRevert(SA.Unauthorized.selector);
        registry.recordLab(id, CONFIG, 0, BUILD, SA.LabInput(40, 39, true, DIGEST));
    }
    function test_EngineerCannotSelfApproveEvenAfterRoleChange() public {
        _allLabs();
        registry.setRole(engineer, SA.Role.Reviewer);
        vm.prank(engineer);
        vm.expectRevert(SA.SeparationOfDuties.selector);
        registry.approveLimited(id, DIGEST, uint64(block.timestamp + 1 days));
    }
    function test_RationaleIsRequired() public {
        _allLabs();
        vm.prank(reviewer);
        vm.expectRevert(SA.InvalidInput.selector);
        registry.approveLimited(id, bytes32(0), uint64(block.timestamp + 1 days));
    }
    function test_ApprovalMustBeTimeLimited() public {
        _allLabs();
        vm.prank(reviewer);
        vm.expectRevert(SA.InvalidInput.selector);
        registry.approveLimited(id, DIGEST, uint64(block.timestamp + 31 days));
    }
    function test_ApprovalExpiresAtBoundary() public {
        _limited();
        assertTrue(registry.isDeploymentAuthorized(id, SA.Stage.Limited));
        vm.warp(registry.getDecision(id, 0).validUntil);
        assertFalse(registry.isDeploymentAuthorized(id, SA.Stage.Limited));
    }
    function test_RevokingReviewerRemovesCurrentAuthority() public {
        _limited();
        registry.setRole(reviewer, SA.Role.None);
        assertFalse(registry.isDeploymentAuthorized(id, SA.Stage.Limited));
        assertEq(registry.decisionCount(id), 1);
    }
    function test_LimitedApprovalDoesNotAuthorizeExpansion() public {
        _limited();
        assertFalse(registry.isDeploymentAuthorized(id, SA.Stage.Expanded));
    }
    function test_LabRevisionReopensAndPreservesDecision() public {
        _limited();
        bytes32 oldSnapshot = registry.getDecision(id, 0).snapshotHash;
        _lab(CONFIG, 0, 40, 40, true);
        assertEq(uint256(registry.getCandidate(id).stage), uint256(SA.Stage.Reopened));
        assertFalse(registry.isDeploymentAuthorized(id, SA.Stage.Limited));
        assertEq(registry.getDecision(id, 0).snapshotHash, oldSnapshot);
        assertTrue(registry.snapshotHash(id) != oldSnapshot);
    }
    function test_BuildRevisionMakesOldEvidenceStale() public {
        _limited();
        vm.prank(engineer);
        registry.reviseBuild(id, keccak256("build-2"), DIGEST);
        _assertGate(registry.labCheck(id, CONFIG, 0), SA.GateStatus.Stale, SA.Reason.WrongBuild);
        assertFalse(registry.isDeploymentAuthorized(id, SA.Stage.Limited));
        assertFalse(registry.getCandidate(id).limitedEver);
    }
    function test_ReturnToOldBuildHashDoesNotReviveEvidence() public {
        _limited();
        vm.startPrank(engineer);
        registry.reviseBuild(id, keccak256("build-2"), DIGEST);
        registry.reviseBuild(id, BUILD, DIGEST);
        vm.stopPrank();
        _assertGate(registry.labCheck(id, CONFIG, 0), SA.GateStatus.Stale, SA.Reason.WrongBuild);
    }
    function test_FieldNeedsPriorLimitedDecision() public {
        vm.prank(analyst);
        vm.expectRevert(SA.InvalidStage.selector);
        registry.recordField(id, CONFIG, BUILD, _goodField());
    }
    function test_RateDeteriorationCreatesOwnedDatedAction() public {
        _limited();
        SA.FieldInput memory data = _goodField();
        data.postEvents = 12;
        _field(CONFIG, data);
        _assertGate(registry.fieldCheck(id, CONFIG), SA.GateStatus.Failed, SA.Reason.RateIncrease);
        SA.Action memory action = registry.getAction(1);
        assertEq(action.owner, engineer);
        assertEq(action.reporter, analyst);
        assertEq(action.dueAt, block.timestamp + 7 days);
        assertEq(registry.getCandidate(id).openActions, 1);
        assertFalse(registry.isDeploymentAuthorized(id, SA.Stage.Limited));
    }
    function test_InsufficientExposureCreatesInconclusiveAction() public {
        _limited();
        SA.FieldInput memory data = _goodField();
        data.postMiles = 999;
        _field(CONFIG, data);
        _assertGate(registry.fieldCheck(id, CONFIG), SA.GateStatus.Inconclusive, SA.Reason.InsufficientExposure);
        assertEq(registry.actionCount(), 1);
    }
    function test_IncomparableCohortsAreNotRateFailure() public {
        _limited();
        SA.FieldInput memory data = _goodField();
        data.comparable = false;
        data.postEvents = 12;
        _field(CONFIG, data);
        _assertGate(registry.fieldCheck(id, CONFIG), SA.GateStatus.Inconclusive, SA.Reason.IncomparableCohorts);
    }
    function test_IncompleteDataAreNotPass() public {
        _limited();
        SA.FieldInput memory data = _goodField();
        data.complete = false;
        _field(CONFIG, data);
        _assertGate(registry.fieldCheck(id, CONFIG), SA.GateStatus.Inconclusive, SA.Reason.IncompleteData);
    }
    function test_InactiveSafeguardsFail() public {
        _limited();
        SA.FieldInput memory data = _goodField();
        data.safeguardsEnabled = false;
        _field(CONFIG, data);
        _assertGate(registry.fieldCheck(id, CONFIG), SA.GateStatus.Failed, SA.Reason.InactiveSafeguards);
    }
    function test_SeriousEventOverridesPoorComparabilityAndZeroExposure() public {
        _limited();
        SA.FieldInput memory data = _goodField();
        data.seriousEvent = true;
        data.comparable = false;
        data.postMiles = 0;
        _field(CONFIG, data);
        _assertGate(registry.fieldCheck(id, CONFIG), SA.GateStatus.Failed, SA.Reason.SeriousEvent);
    }
    function test_ExactRateEqualityPasses() public {
        _limited();
        SA.FieldInput memory data = _goodField();
        data.postEvents = 4;
        data.postMiles = 2000;
        _field(CONFIG, data);
        _assertGate(registry.fieldCheck(id, CONFIG), SA.GateStatus.Eligible, SA.Reason.None);
    }
    function test_ZeroBaselineDoesNotMaskPostEvents() public {
        _limited();
        SA.FieldInput memory data = _goodField();
        data.baselineEvents = 0;
        data.postEvents = 1;
        _field(CONFIG, data);
        _assertGate(registry.fieldCheck(id, CONFIG), SA.GateStatus.Failed, SA.Reason.RateIncrease);
    }
    function test_SmallRateIncreaseCannotBeRoundedAway() public {
        _limited();
        SA.FieldInput memory data = _goodField();
        data.baselineEvents = 1;
        data.baselineMiles = 10000000;
        data.postEvents = 2;
        data.postMiles = 10000000;
        _field(CONFIG, data);
        _assertGate(registry.fieldCheck(id, CONFIG), SA.GateStatus.Failed, SA.Reason.RateIncrease);
    }
    function testFuzz_FieldRateComparison(uint64 baselineEvents, uint64 postEvents, uint64 baselineMiles, uint64 postMiles) public {
        _limited();
        baselineMiles = uint64(bound(baselineMiles, 1000, type(uint64).max));
        postMiles = uint64(bound(postMiles, 1000, type(uint64).max));
        SA.FieldInput memory data = SA.FieldInput(baselineEvents, baselineMiles, postEvents, postMiles, true, true, true, false, DIGEST);
        _field(CONFIG, data);
        bool worse = uint256(postEvents) * baselineMiles > uint256(baselineEvents) * postMiles;
        assertEq(uint256(registry.fieldCheck(id, CONFIG).status), uint256(worse ? SA.GateStatus.Failed : SA.GateStatus.Eligible));
    }
    function test_ImprovedEvidenceDoesNotAutoCloseAction() public {
        _limited();
        SA.FieldInput memory data = _goodField();
        data.postEvents = 12;
        _field(CONFIG, data);
        _field(CONFIG, _goodField());
        assertFalse(registry.getAction(1).closed);
        assertEq(registry.getCandidate(id).openActions, 1);
        vm.prank(reviewer);
        vm.expectRevert(abi.encodeWithSelector(SA.OpenActions.selector, uint64(1)));
        registry.approveExpansion(id, DIGEST, uint64(block.timestamp + 1 days));
    }
    function test_ClosingActionStillRequiresSeparateDecision() public {
        _expanded();
        uint256 actionId = _concern();
        vm.prank(reviewer);
        registry.closeAction(actionId, DIGEST, DIGEST);
        assertFalse(registry.isDeploymentAuthorized(id, SA.Stage.Expanded));
        vm.prank(reviewer);
        registry.approveExpansion(id, DIGEST, uint64(block.timestamp + 1 days));
        assertTrue(registry.isDeploymentAuthorized(id, SA.Stage.Expanded));
        assertEq(registry.decisionCount(id), 3);
    }
    function test_ClosingActionCannotBypassFailedGate() public {
        _limited();
        SA.FieldInput memory data = _goodField();
        data.postEvents = 12;
        _field(CONFIG, data);
        _field(OTHER, _goodField());
        vm.prank(reviewer);
        registry.closeAction(1, DIGEST, DIGEST);
        vm.prank(reviewer);
        vm.expectRevert(abi.encodeWithSelector(SA.GateBlocked.selector, SA.GateStatus.Failed, SA.Reason.RateIncrease, CONFIG, uint8(0)));
        registry.approveExpansion(id, DIGEST, uint64(block.timestamp + 1 days));
    }
    function test_SignalReporterCannotCloseOwnConcern() public {
        vm.prank(reviewer);
        uint256 actionId = registry.reportConcern(id, DIGEST);
        vm.prank(reviewer);
        vm.expectRevert(SA.SeparationOfDuties.selector);
        registry.closeAction(actionId, DIGEST, DIGEST);
    }
    function test_AnalystCannotBecomeOwnIndependentReviewer() public {
        _limited();
        _field(CONFIG, _goodField());
        registry.setRole(analyst, SA.Role.Reviewer);
        vm.prank(analyst);
        vm.expectRevert(SA.SeparationOfDuties.selector);
        registry.approveLimited(id, DIGEST, uint64(block.timestamp + 1 days));
    }
    function test_EscalationOnlyAfterDeadlineAndOnce() public {
        uint256 actionId = _concern();
        uint64 due = registry.getAction(actionId).dueAt;
        vm.warp(due);
        assertFalse(registry.isOverdue(actionId));
        vm.expectRevert(SA.NotOverdue.selector);
        registry.escalateOverdue(actionId);
        vm.warp(due + 1);
        assertTrue(registry.isOverdue(actionId));
        vm.prank(stranger);
        registry.escalateOverdue(actionId);
        assertTrue(registry.getAction(actionId).escalated);
        vm.expectRevert(SA.AlreadyEscalated.selector);
        registry.escalateOverdue(actionId);
    }
    function test_ClosedActionCannotEscalateOrCloseTwice() public {
        uint256 actionId = _concern();
        vm.prank(reviewer);
        registry.closeAction(actionId, DIGEST, DIGEST);
        vm.expectRevert(SA.AlreadyClosed.selector);
        registry.escalateOverdue(actionId);
        vm.prank(reviewer);
        vm.expectRevert(SA.AlreadyClosed.selector);
        registry.closeAction(actionId, DIGEST, DIGEST);
    }
    function test_MissingFieldBlocksExpansion() public {
        _limited();
        vm.prank(reviewer);
        vm.expectRevert(abi.encodeWithSelector(SA.GateBlocked.selector, SA.GateStatus.Missing, SA.Reason.MissingEvidence, CONFIG, uint8(0)));
        registry.approveExpansion(id, DIGEST, uint64(block.timestamp + 1 days));
    }
    function test_ExpandedDecisionCanBeReadAndReconstructed() public {
        _expanded();
        SA.Decision memory d = registry.getDecision(id, 1);
        assertEq(d.reviewer, reviewer);
        assertEq(d.snapshotHash, registry.snapshotHash(id));
        assertEq(d.rationaleHash, DIGEST);
        assertTrue(registry.isDeploymentAuthorized(id, SA.Stage.Limited));
        assertTrue(registry.isDeploymentAuthorized(id, SA.Stage.Expanded));
    }
    function test_UnknownIdentifiersRevert() public {
        vm.expectRevert(SA.UnknownCandidate.selector);
        registry.labGate(999);
        vm.expectRevert(SA.UnknownAction.selector);
        registry.getAction(999);
    }
    function test_OnlySafetyLeadManagesRoles() public {
        vm.prank(engineer);
        vm.expectRevert(SA.Unauthorized.selector);
        registry.setRole(stranger, SA.Role.Reviewer);
        vm.expectRevert(SA.InvalidInput.selector);
        registry.setRole(stranger, SA.Role.SafetyLead);
    }
    function test_CandidateCannotHaveDuplicateOrEmptyScope() public {
        bytes32[] memory configs = new bytes32[](2);
        configs[0] = CONFIG;
        configs[1] = CONFIG;
        vm.prank(engineer);
        vm.expectRevert(SA.InvalidInput.selector);
        registry.createCandidate(BUILD, DIGEST, configs);
        vm.prank(engineer);
        vm.expectRevert(SA.InvalidInput.selector);
        registry.createCandidate(BUILD, bytes32(0), configs);
    }
}
