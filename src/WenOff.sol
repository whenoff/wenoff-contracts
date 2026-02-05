// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title WenOff — onchain waiting game (Base)
/// @notice One active round; gas-only lightOn, paid enter; finalize after deadline; claim winner/ladder/protocol/ecosystem.
contract WenOff {
    // ─────────────────────────────────────────────────────────────────────────
    // Enums
    // ─────────────────────────────────────────────────────────────────────────

    enum LampId {
        ONE,
        TWO,
        THREE
    }

    enum RoundState {
        OFF,
        ACTIVE,
        FINALIZABLE
    }

    enum EndReason {
        NO_WINNER,
        TIMER_EXPIRED
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Custom errors
    // ─────────────────────────────────────────────────────────────────────────

    error WrongState(RoundState current);
    error DeadlineNotPassed(uint256 deadline);
    error InvalidEntryFee(uint256 sent, uint256 required);
    error RoundNotFinalized(uint256 roundId);
    error AlreadyClaimed(uint256 roundId, address claimant);
    error NoClaimableAmount(uint256 roundId, address claimant);
    error TransferFailed(address to, uint256 amount);
    error ReentrantCall();

    // ─────────────────────────────────────────────────────────────────────────
    // Constants
    // ─────────────────────────────────────────────────────────────────────────

    uint256 public constant ROUND_DURATION = 10 minutes;
    uint256 public constant WINNER_BPS = 6_000;   // 60%
    uint256 public constant LADDER_BPS = 2_500;   // 25%
    uint256 public constant PROTOCOL_BPS = 1_000; // 10%
    uint256 public constant ECOSYSTEM_BPS = 500;  // 5%
    uint256 public constant BPS = 10_000;

    // ─────────────────────────────────────────────────────────────────────────
    // Config (set once at construction)
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Entry fee in wei per lamp (ETH only)
    mapping(LampId => uint256) public entryFeeWei;
    address public protocolBeneficiary;
    address public ecosystemBeneficiary;

    // ─────────────────────────────────────────────────────────────────────────
    // Current round state (one active round at a time)
    // ─────────────────────────────────────────────────────────────────────────

    uint256 public currentRoundId;
    RoundState public roundState;
    uint256 public roundDeadline;
    address public roundLeader;
    LampId public roundLamp;
    uint256 public roundPot;

    /// @dev Ring buffer of last 20 entrants; index 0 = oldest of the 20, 19 = leader
    address[20] public entrantBuffer;
    uint256 public entrantCount;

    // ─────────────────────────────────────────────────────────────────────────
    // Per-round data after finalize (for claims)
    // ─────────────────────────────────────────────────────────────────────────

    mapping(uint256 => bool) public roundFinalized;
    mapping(uint256 => address) public roundWinner;
    mapping(uint256 => address[20]) public roundTop20;
    mapping(uint256 => uint256) public roundProtocolShare;
    mapping(uint256 => uint256) public roundEcosystemShare;
    mapping(uint256 => EndReason) public roundEndReason;
    mapping(uint256 => uint256) public roundPotAtFinalize;
    /// @dev claimable amount per round per address (winner + ladder); protocol/ecosystem use beneficiary
    mapping(uint256 => mapping(address => uint256)) public roundClaimable;
    mapping(uint256 => mapping(address => bool)) public hasClaimed;

    uint256 private _locked = 1;

    modifier nonReentrant() {
        if (_locked != 1) revert ReentrantCall();
        _locked = 2;
        _;
        _locked = 1;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    event LightOn(uint256 indexed roundId, address indexed starter, uint256 deadline, LampId lamp);
    event Entered(uint256 indexed roundId, address indexed entrant, uint256 newDeadline, uint256 feePaid);
    event Finalized(uint256 indexed roundId, address winner, EndReason reason, uint256 pot);
    event Claimed(uint256 indexed roundId, address indexed claimant, uint256 amount);
    event ProtocolFeeClaimed(uint256 indexed roundId, uint256 amount);
    event EcosystemClaimed(uint256 indexed roundId, uint256 amount);

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────────

    constructor(
        uint256 feeOneWei_,
        uint256 feeTwoWei_,
        uint256 feeThreeWei_,
        address protocolBeneficiary_,
        address ecosystemBeneficiary_
    ) {
        entryFeeWei[LampId.ONE] = feeOneWei_;
        entryFeeWei[LampId.TWO] = feeTwoWei_;
        entryFeeWei[LampId.THREE] = feeThreeWei_;
        protocolBeneficiary = protocolBeneficiary_;
        ecosystemBeneficiary = ecosystemBeneficiary_;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // State-changing: lightOn
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Start a new round (gas only). Deadline = now + 10 min; caller is initial leader.
    function lightOn(LampId lamp) external nonReentrant {
        if (roundState != RoundState.OFF) revert WrongState(roundState);

        currentRoundId++;
        roundState = RoundState.ACTIVE;
        roundDeadline = block.timestamp + ROUND_DURATION;
        roundLeader = msg.sender;
        roundLamp = lamp;
        roundPot = 0;
        entrantCount = 0;

        entrantBuffer[0] = msg.sender;
        entrantCount = 1;

        emit LightOn(currentRoundId, msg.sender, roundDeadline, lamp);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // State-changing: enter / resetTimer
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Pay entry fee, become leader, reset deadline to now + 10 min.
    function enter() external payable nonReentrant {
        _enter(msg.value);
    }

    /// @notice Alias for enter().
    function resetTimer() external payable nonReentrant {
        _enter(msg.value);
    }

    function _enter(uint256 value) internal {
        if (roundState != RoundState.ACTIVE) revert WrongState(roundState);
        if (block.timestamp >= roundDeadline) revert DeadlineNotPassed(roundDeadline);

        uint256 fee = entryFeeWei[roundLamp];
        if (value != fee) revert InvalidEntryFee(value, fee);

        roundDeadline = block.timestamp + ROUND_DURATION;
        roundLeader = msg.sender;
        roundPot += value;

        uint256 idx = entrantCount % 20;
        entrantBuffer[idx] = msg.sender;
        entrantCount++;

        emit Entered(currentRoundId, msg.sender, roundDeadline, fee);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // State-changing: finalize
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Close the round after deadline. If no paid entries (pot == 0), NO_WINNER and no rewards.
    function finalize() external nonReentrant {
        if (roundState != RoundState.ACTIVE) revert WrongState(roundState);
        if (block.timestamp < roundDeadline) revert DeadlineNotPassed(roundDeadline);

        uint256 pot = roundPot;
        roundPotAtFinalize[currentRoundId] = pot;
        EndReason reason = pot == 0 ? EndReason.NO_WINNER : EndReason.TIMER_EXPIRED;
        address winner = pot == 0 ? address(0) : roundLeader;

        roundFinalized[currentRoundId] = true;
        roundWinner[currentRoundId] = winner;
        roundEndReason[currentRoundId] = reason;

        if (pot > 0) {
            _snapshotTop20();
            uint256 protocolAmount = (pot * PROTOCOL_BPS) / BPS;
            uint256 ecosystemAmount = (pot * ECOSYSTEM_BPS) / BPS;
            roundProtocolShare[currentRoundId] = protocolAmount;
            roundEcosystemShare[currentRoundId] = ecosystemAmount;
            _setClaimableAmounts(pot);
        }

        roundState = RoundState.OFF;

        emit Finalized(currentRoundId, winner, reason, pot);
    }

    /// @dev Copy last 20 entrants into roundTop20 (index 0 = 20th place, 19 = leader).
    function _snapshotTop20() private {
        uint256 n = entrantCount;
        if (n <= 20) {
            for (uint256 i = 0; i < n; i++) {
                roundTop20[currentRoundId][i] = entrantBuffer[i];
            }
        } else {
            for (uint256 i = 0; i < 20; i++) {
                roundTop20[currentRoundId][i] = entrantBuffer[(n - 20 + i) % 20];
            }
        }
    }

    /// @dev Set roundClaimable for winner (60%) and ladder (25%). Ladder: positions 2..N by entry order (higher = more).
    function _setClaimableAmounts(uint256 pot) private {
        uint256 winnerAmount = (pot * WINNER_BPS) / BPS;
        uint256 ladderTotal = (pot * LADDER_BPS) / BPS;
        address[20] storage top20 = roundTop20[currentRoundId];
        address w = roundWinner[currentRoundId];

        roundClaimable[currentRoundId][w] = winnerAmount;

        uint256 n = 0;
        for (uint256 i = 0; i < 20; i++) {
            if (top20[i] == address(0)) break;
            n++;
        }
        if (n <= 1) return;
        uint256 ladderSlots = n - 1;
        uint256 sumWeight = (ladderSlots * (ladderSlots + 1)) / 2;
        if (sumWeight == 0) sumWeight = 1;
        for (uint256 i = 0; i < ladderSlots; i++) {
            address a = top20[i];
            uint256 weight = ladderSlots - i;
            uint256 share = (ladderTotal * weight) / sumWeight;
            roundClaimable[currentRoundId][a] += share;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // State-changing: claim
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Claim caller's share for a finalized round (winner, ladder, protocol, or ecosystem).
    function claim(uint256 roundId) external nonReentrant {
        if (!roundFinalized[roundId]) revert RoundNotFinalized(roundId);
        if (hasClaimed[roundId][msg.sender]) revert AlreadyClaimed(roundId, msg.sender);

        uint256 amount = roundClaimable[roundId][msg.sender];
        if (amount > 0) {
            hasClaimed[roundId][msg.sender] = true;
            emit Claimed(roundId, msg.sender, amount);
            _sendEth(msg.sender, amount);
            return;
        }

        if (msg.sender == protocolBeneficiary && roundProtocolShare[roundId] > 0) {
            amount = roundProtocolShare[roundId];
            roundProtocolShare[roundId] = 0;
            hasClaimed[roundId][msg.sender] = true;
            emit ProtocolFeeClaimed(roundId, amount);
            _sendEth(msg.sender, amount);
            return;
        }

        if (msg.sender == ecosystemBeneficiary && roundEcosystemShare[roundId] > 0) {
            amount = roundEcosystemShare[roundId];
            roundEcosystemShare[roundId] = 0;
            hasClaimed[roundId][msg.sender] = true;
            emit EcosystemClaimed(roundId, amount);
            _sendEth(msg.sender, amount);
            return;
        }

        revert NoClaimableAmount(roundId, msg.sender);
    }

    function _sendEth(address to, uint256 amount) private {
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed(to, amount);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // View helpers
    // ─────────────────────────────────────────────────────────────────────────

    function getRound(uint256 roundId) external view returns (
        uint256 id,
        RoundState state,
        LampId lamp,
        uint256 deadline,
        address leader,
        uint256 pot,
        EndReason endReason
    ) {
        id = roundId;
        endReason = roundEndReason[roundId];
        if (roundId == currentRoundId) {
            state = roundState;
            lamp = roundLamp;
            deadline = roundDeadline;
            leader = roundLeader;
            pot = roundPot;
        } else if (roundFinalized[roundId]) {
            state = RoundState.OFF;
            leader = roundWinner[roundId];
            pot = roundPotAtFinalize[roundId];
        }
    }

    function getRoundState() external view returns (RoundState state, uint256 roundId, uint256 deadline, address leader) {
        state = roundState;
        roundId = currentRoundId;
        deadline = roundDeadline;
        leader = roundLeader;
    }

    function getTop20(uint256 roundId) external view returns (address[20] memory) {
        return roundTop20[roundId];
    }

    function getClaimable(uint256 roundId, address account) external view returns (uint256) {
        if (!roundFinalized[roundId]) return 0;
        if (hasClaimed[roundId][account]) return 0;
        uint256 amount = roundClaimable[roundId][account];
        if (account == protocolBeneficiary) amount += roundProtocolShare[roundId];
        if (account == ecosystemBeneficiary) amount += roundEcosystemShare[roundId];
        return amount;
    }

    function getLampFee(LampId lamp) external view returns (address token, uint256 amount) {
        token = address(0);
        amount = entryFeeWei[lamp];
    }

    receive() external payable {
        revert InvalidEntryFee(msg.value, 0);
    }
}
