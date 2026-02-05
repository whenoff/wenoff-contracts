// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {WenOff} from "../src/WenOff.sol";

contract ReentrantClaimer {
    WenOff wenOff;
    uint256 roundId;

    constructor(WenOff _w) {
        wenOff = _w;
    }

    function setRound(uint256 _roundId) external {
        roundId = _roundId;
    }

    function claim() external {
        wenOff.claim(roundId);
    }

    receive() external payable {
        wenOff.claim(roundId);
    }
}

contract WenOffTest is Test {
    WenOff public wenOff;

    address constant PROTOCOL = address(1);
    address constant ECOSYSTEM = address(2);
    uint256 constant FEE_ONE = 0.001 ether;
    uint256 constant FEE_TWO = 0.002 ether;
    uint256 constant FEE_THREE = 0.01 ether;

    address alice = address(0xa11ce);
    address bob = address(0xb0b);
    address carol = address(0xc0c);

    function setUp() public {
        wenOff = new WenOff(FEE_ONE, FEE_TWO, FEE_THREE, PROTOCOL, ECOSYSTEM);
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        vm.deal(carol, 10 ether);
    }

    // ─── 1) LIGHT OFF initial state ─────────────────────────────────────────

    function test_InitialState_IsOff() public view {
        assertEq(uint256(wenOff.roundState()), uint256(WenOff.RoundState.OFF));
        assertEq(wenOff.currentRoundId(), 0);
        assertEq(wenOff.roundDeadline(), 0);
        assertEq(wenOff.roundLeader(), address(0));
        assertEq(wenOff.roundPot(), 0);
    }

    // ─── 2) lightOn() starts round, leader, deadline ~ now+10min, pool=0 ──────

    function test_LightOn_StartsRound_SetsLeader_Deadline_PoolZero() public {
        vm.expectEmit(true, true, true, true);
        emit LightOn(1, alice, block.timestamp + 10 minutes, WenOff.LampId.ONE);

        vm.prank(alice);
        wenOff.lightOn(WenOff.LampId.ONE);

        assertEq(uint256(wenOff.roundState()), uint256(WenOff.RoundState.ACTIVE));
        assertEq(wenOff.currentRoundId(), 1);
        assertEq(wenOff.roundLeader(), alice);
        assertEq(wenOff.roundDeadline(), block.timestamp + 10 minutes);
        assertEq(wenOff.roundPot(), 0);
        assertEq(uint256(wenOff.roundLamp()), uint256(WenOff.LampId.ONE));
    }

    function test_LightOn_RevertsWhenNotOff() public {
        vm.prank(alice);
        wenOff.lightOn(WenOff.LampId.ONE);

        vm.expectRevert(abi.encodeWithSelector(WenOff.WrongState.selector, WenOff.RoundState.ACTIVE));
        vm.prank(bob);
        wenOff.lightOn(WenOff.LampId.TWO);
    }

    // ─── 3) No paid entries: after deadline, finalize → NO_WINNER, no rewards ─

    function test_NoPaidEntries_Finalize_NoWinner_NoRewards() public {
        vm.prank(alice);
        wenOff.lightOn(WenOff.LampId.ONE);

        vm.warp(block.timestamp + 10 minutes + 1);

        vm.expectEmit(true, true, true, true);
        emit Finalized(1, address(0), WenOff.EndReason.NO_WINNER, 0);

        wenOff.finalize();

        assertEq(uint256(wenOff.roundState()), uint256(WenOff.RoundState.OFF));
        assertEq(wenOff.roundWinner(1), address(0));
        assertEq(uint256(wenOff.roundEndReason(1)), uint256(WenOff.EndReason.NO_WINNER));
        assertEq(wenOff.roundPotAtFinalize(1), 0);
        assertTrue(wenOff.roundFinalized(1));
        assertEq(wenOff.getClaimable(1, alice), 0);
    }

    function test_NoPaidEntries_ClaimRevertsNoClaimable() public {
        vm.prank(alice);
        wenOff.lightOn(WenOff.LampId.ONE);
        vm.warp(block.timestamp + 10 minutes + 1);
        wenOff.finalize();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(WenOff.NoClaimableAmount.selector, 1, alice));
        wenOff.claim(1);
    }

    // ─── 4) With paid entries: enter() resets timer, leader, increases pool ──

    function test_Enter_ResetsTimer_UpdatesLeader_IncreasesPool() public {
        vm.prank(alice);
        wenOff.lightOn(WenOff.LampId.ONE);

        uint256 t = block.timestamp + 5 minutes;
        vm.warp(t);

        vm.prank(bob);
        wenOff.enter{value: FEE_ONE}();

        assertEq(wenOff.roundLeader(), bob);
        assertEq(wenOff.roundDeadline(), t + 10 minutes);
        assertEq(wenOff.roundPot(), FEE_ONE);

        vm.warp(t + 2 minutes);
        vm.prank(carol);
        wenOff.enter{value: FEE_ONE}();

        assertEq(wenOff.roundLeader(), carol);
        assertEq(wenOff.roundDeadline(), t + 2 minutes + 10 minutes);
        assertEq(wenOff.roundPot(), 2 * FEE_ONE);
    }

    function test_Enter_RevertsWrongFee() public {
        vm.prank(alice);
        wenOff.lightOn(WenOff.LampId.ONE);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(WenOff.InvalidEntryFee.selector, FEE_THREE, FEE_ONE));
        wenOff.enter{value: FEE_THREE}();
    }

    function test_Enter_RevertsAfterDeadline() public {
        vm.prank(alice);
        wenOff.lightOn(WenOff.LampId.ONE);
        vm.warp(block.timestamp + 10 minutes + 1);

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(bytes4(keccak256("DeadlineNotPassed(uint256)")), wenOff.roundDeadline())
        );
        wenOff.enter{value: FEE_ONE}();
    }

    function test_ResetTimer_AliasForEnter() public {
        vm.prank(alice);
        wenOff.lightOn(WenOff.LampId.TWO);

        vm.prank(bob);
        wenOff.resetTimer{value: FEE_TWO}();

        assertEq(wenOff.roundLeader(), bob);
        assertEq(wenOff.roundPot(), FEE_TWO);
    }

    // ─── 5) finalize() after deadline closes round, winner, top20 snapshot ────

    function test_Finalize_WithPaidEntries_ClosesRound_Winner_Top20Snapshot() public {
        vm.prank(alice);
        wenOff.lightOn(WenOff.LampId.ONE);

        vm.prank(bob);
        wenOff.enter{value: FEE_ONE}();
        vm.prank(carol);
        wenOff.enter{value: FEE_ONE}();

        vm.warp(block.timestamp + 10 minutes + 1);
        wenOff.finalize();

        assertEq(uint256(wenOff.roundState()), uint256(WenOff.RoundState.OFF));
        assertEq(wenOff.roundWinner(1), carol);
        assertEq(uint256(wenOff.roundEndReason(1)), uint256(WenOff.EndReason.TIMER_EXPIRED));
        assertEq(wenOff.roundPotAtFinalize(1), 2 * FEE_ONE);

        address[20] memory top20 = wenOff.getTop20(1);
        assertEq(top20[0], alice);
        assertEq(top20[1], bob);
        assertEq(top20[2], carol);
        assertEq(top20[3], address(0));
    }

    function test_Finalize_RevertsBeforeDeadline() public {
        vm.prank(alice);
        wenOff.lightOn(WenOff.LampId.ONE);
        vm.prank(bob);
        wenOff.enter{value: FEE_ONE}();

        vm.warp(block.timestamp + 5 minutes);
        vm.expectRevert(abi.encodeWithSelector(WenOff.DeadlineNotPassed.selector, wenOff.roundDeadline()));
        wenOff.finalize();
    }

    // ─── 6) claim(): winner, top20, protocol, ecosystem, double claim reverts ─

    function test_Claim_Winner_ClaimsOnce() public {
        vm.prank(alice);
        wenOff.lightOn(WenOff.LampId.ONE);
        vm.prank(bob);
        wenOff.enter{value: FEE_ONE}();
        vm.prank(carol);
        wenOff.enter{value: FEE_ONE}();
        vm.warp(block.timestamp + 10 minutes + 1);
        wenOff.finalize();

        uint256 pot = 2 * FEE_ONE;
        uint256 winnerShare = (pot * 6000) / 10000;

        uint256 carolBefore = carol.balance;
        vm.prank(carol);
        wenOff.claim(1);
        assertEq(carol.balance - carolBefore, winnerShare);

        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(WenOff.AlreadyClaimed.selector, 1, carol));
        wenOff.claim(1);
    }

    function test_Claim_Top20_ClaimsOnce() public {
        vm.prank(alice);
        wenOff.lightOn(WenOff.LampId.ONE);
        vm.prank(bob);
        wenOff.enter{value: FEE_ONE}();
        vm.warp(block.timestamp + 10 minutes + 1);
        wenOff.finalize();

        uint256 aliceClaimable = wenOff.getClaimable(1, alice);
        assertGt(aliceClaimable, 0);

        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        wenOff.claim(1);
        assertEq(alice.balance - aliceBefore, aliceClaimable);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(WenOff.AlreadyClaimed.selector, 1, alice));
        wenOff.claim(1);
    }

    function test_Claim_Protocol_Claims() public {
        vm.prank(alice);
        wenOff.lightOn(WenOff.LampId.ONE);
        vm.prank(bob);
        wenOff.enter{value: FEE_ONE}();
        vm.warp(block.timestamp + 10 minutes + 1);
        wenOff.finalize();

        uint256 protocolShare = (FEE_ONE * 1000) / 10000;
        uint256 protocolBefore = PROTOCOL.balance;
        vm.prank(PROTOCOL);
        wenOff.claim(1);
        assertEq(PROTOCOL.balance - protocolBefore, protocolShare);
    }

    function test_Claim_Ecosystem_Claims() public {
        vm.prank(alice);
        wenOff.lightOn(WenOff.LampId.ONE);
        vm.prank(bob);
        wenOff.enter{value: FEE_ONE}();
        vm.warp(block.timestamp + 10 minutes + 1);
        wenOff.finalize();

        uint256 ecosystemShare = (FEE_ONE * 500) / 10000;
        uint256 ecosystemBefore = ECOSYSTEM.balance;
        vm.prank(ECOSYSTEM);
        wenOff.claim(1);
        assertEq(ECOSYSTEM.balance - ecosystemBefore, ecosystemShare);
    }

    function test_Claim_DoubleClaim_Reverts() public {
        vm.prank(alice);
        wenOff.lightOn(WenOff.LampId.ONE);
        vm.prank(bob);
        wenOff.enter{value: FEE_ONE}();
        vm.warp(block.timestamp + 10 minutes + 1);
        wenOff.finalize();

        vm.prank(bob);
        wenOff.claim(1);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(WenOff.AlreadyClaimed.selector, 1, bob));
        wenOff.claim(1);
    }

    function test_Claim_RevertsWhenRoundNotFinalized() public {
        vm.prank(alice);
        wenOff.lightOn(WenOff.LampId.ONE);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(WenOff.RoundNotFinalized.selector, 1));
        wenOff.claim(1);
    }

    // ─── 7) Reentrancy safety ───────────────────────────────────────────────

    function test_Reentrancy_ClaimRevertsOnReenter() public {
        ReentrantClaimer reentrer = new ReentrantClaimer(wenOff);
        vm.deal(address(reentrer), 1 ether);

        vm.prank(alice);
        wenOff.lightOn(WenOff.LampId.ONE);
        vm.prank(address(reentrer));
        wenOff.enter{value: FEE_ONE}();
        vm.warp(block.timestamp + 10 minutes + 1);
        wenOff.finalize();

        reentrer.setRound(1);
        uint256 expectedAmount = (FEE_ONE * 6000) / 10000; // winner share (60% of pot)
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("TransferFailed(address,uint256)")),
                address(reentrer),
                expectedAmount
            )
        );
        reentrer.claim();
    }

    // ─── 8) Lamp cannot be changed mid-round ─────────────────────────────────

    function test_Lamp_FeeIsFixedForRound_EnterUsesRoundLamp() public {
        vm.prank(alice);
        wenOff.lightOn(WenOff.LampId.ONE);

        vm.prank(bob);
        wenOff.enter{value: FEE_ONE}();

        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(WenOff.InvalidEntryFee.selector, FEE_TWO, FEE_ONE));
        wenOff.enter{value: FEE_TWO}();

        vm.prank(carol);
        wenOff.enter{value: FEE_ONE}();
        assertEq(wenOff.roundLeader(), carol);
    }

    function test_Lamp_NextRoundCanUseDifferentLamp() public {
        vm.prank(alice);
        wenOff.lightOn(WenOff.LampId.ONE);
        vm.warp(block.timestamp + 10 minutes + 1);
        wenOff.finalize();

        vm.prank(bob);
        wenOff.lightOn(WenOff.LampId.THREE);
        assertEq(uint256(wenOff.roundLamp()), uint256(WenOff.LampId.THREE));
        assertEq(wenOff.entryFeeWei(WenOff.LampId.THREE), FEE_THREE);

        vm.prank(carol);
        wenOff.enter{value: FEE_THREE}();
        assertEq(wenOff.roundPot(), FEE_THREE);
    }

    // ─── Event declarations for expectEmit ───────────────────────────────────

    event LightOn(uint256 indexed roundId, address indexed starter, uint256 deadline, WenOff.LampId lamp);
    event Finalized(uint256 indexed roundId, address winner, WenOff.EndReason reason, uint256 pot);
}
