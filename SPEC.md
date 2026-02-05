# WEN OFF — Contract Spec

Implementable API and storage specification. Single contract, Base (EVM).

---

## Enums

```solidity
enum LampId { ONE, TWO, THREE }
```

- **ONE**: $1 or equivalent (e.g. USDC amount)
- **TWO**: 0.001 ETH
- **THREE**: 0.01 ETH

```solidity
enum RoundState { OFF, ACTIVE, FINALIZABLE, CLOSED }
```

- **OFF**: No round; ready for `lightOn`
- **ACTIVE**: Round running; deadline counting down
- **FINALIZABLE**: Deadline passed; anyone can `finalize`
- **CLOSED**: Finalized; claims enabled

```solidity
enum EndReason { NO_WINNER, TIMER_EXPIRED }
```

- **NO_WINNER**: Nobody else entered; starter alone until deadline
- **TIMER_EXPIRED**: At least one RESET TIMER; last leader wins

---

## Structs

```solidity
struct LampConfig {
    uint256 feeWei;     // for LampId.TWO, THREE: ETH amount in wei
    address feeToken;   // address(0) = native ETH; else ERC20
    uint256 feeAmount;  // for LampId.ONE: token amount (e.g. 1e6 USDC)
}
```

```solidity
struct RoundSummary {
    uint256 roundId;
    RoundState state;
    LampId lamp;
    uint256 deadline;
    address currentLeader;
    uint256 pot;
    EndReason endReason;  // meaningful only when state == CLOSED
}
```

---

## Storage

| Variable | Type | Purpose |
|----------|------|---------|
| `currentRoundId` | `uint256` | ID of active or last round |
| `roundState` | `RoundState` | Current state |
| `roundDeadline` | `uint256` | Unix timestamp; 0 when OFF |
| `roundLeader` | `address` | Current/last leader |
| `roundLamp` | `LampId` | Lamp used for this round (fixed at start) |
| `roundPot` | `uint256` | Total ETH/token collected this round |
| `lampConfig` | `mapping(LampId => LampConfig)` | Fee config per lamp |
| `nextRoundLamp` | `LampId` | Lamp for *next* round (can change when OFF) |
| `participants` | `address[]` or ordered structure | Top-20 tracking (by entry order; last = leader) |
| `claimed` | `mapping(uint256 roundId => mapping(address => bool))` | Claim tracking per round |
| `protocolShare` | `mapping(uint256 => uint256)` | Protocol 10% per round |
| `ecosystemShare` | `mapping(uint256 => uint256)` | Ecosystem 5% per round |

**Rule:** Lamp cannot change mid-round. `roundLamp` is set at `lightOn`; `nextRoundLamp` applies only when starting the next round.

---

## Functions

### State-Changing

| Function | Signature | Behavior |
|----------|-----------|----------|
| `lightOn` | `lightOn(LampId lamp)` | Requires `roundState == OFF`. Starts round with `deadline = now + 10 min`, `roundLeader = msg.sender`, `roundLamp = lamp`. Emits `LightOn`. |
| `enter` | `enter()` payable | Alias: `resetTimer()`. Requires `roundState == ACTIVE`, `block.timestamp < roundDeadline`, correct fee. Resets `roundDeadline = now + 10 min`, `roundLeader = msg.sender`, adds fee to `roundPot`. Emits `Entered`. |
| `finalize` | `finalize()` | Requires `roundState == FINALIZABLE`. Computes winner/ladder shares, sets `roundState = CLOSED`. Emits `Finalized` (with `EndReason`). |
| `claim` | `claim(uint256 roundId)` | Requires `roundState == CLOSED` for that round. Transfers caller's share (winner/ladder/protocol/ecosystem). Emits `Claimed`. |

### View Helpers

| Function | Signature | Returns |
|----------|-----------|---------|
| `getRound` | `getRound(uint256 roundId)` | `RoundSummary` |
| `getRoundState` | `getRoundState()` | `RoundState`, `roundId`, `deadline`, `leader` (current round) |
| `getTop20` | `getTop20(uint256 roundId)` | `address[20]` ordered (position 0 = 20th, 19 = 1st/leader) |
| `getClaimable` | `getClaimable(uint256 roundId, address account)` | `uint256` amount claimable |
| `getLampFee` | `getLampFee(LampId lamp)` | `(address token, uint256 amount)` for current config |

---

## Events

| Event | Params | Purpose |
|-------|--------|---------|
| `LightOn` | `uint256 roundId, address starter, uint256 deadline, LampId lamp` | Round started |
| `Entered` | `uint256 roundId, address entrant, uint256 newDeadline, uint256 feePaid` | Timer reset / new leader |
| `Finalized` | `uint256 roundId, address winner, EndReason reason, uint256 pot` | Round closed; `winner == address(0)` iff `reason == NO_WINNER` |
| `Claimed` | `uint256 roundId, address claimant, uint256 amount` | User claimed share |
| `ProtocolFeeClaimed` | `uint256 roundId, uint256 amount` | Protocol claimed |
| `EcosystemClaimed` | `uint256 roundId, uint256 amount` | Ecosystem claimed |

---

## Payout Split (Applied on `finalize`)

| Recipient | Share |
|-----------|-------|
| Winner | 60% |
| Top-20 ladder | 25% (position 1 > 2 > … > 20) |
| Protocol | 10% |
| Ecosystem | 5% |

Exact ladder distribution TBD (e.g. linear decay or fixed tiers).

---

## Rules Summary

- Lamp cannot change mid-round: `roundLamp` fixed at `lightOn`; `nextRoundLamp` only affects next round.
- One active round at a time.
- `lightOn` is gas-only; `enter` requires fee per `roundLamp`.
- Anyone can call `finalize` when `roundState == FINALIZABLE`.
