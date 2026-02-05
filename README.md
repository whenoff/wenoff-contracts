# WEN OFF

Onchain waiting game smart contracts for **Base** (EVM). Single contract, no backend, no database—UI reads all state from chain.

→ **[SPEC.md](./SPEC.md)** — Contract API, storage, and events (implementable spec).

---

## What is WEN OFF?

WEN OFF is an onchain game where players compete to stay in the lead until the clock hits 0. Turn the **LIGHT ON** (gas-only) to start. Others **RESET TIMER** by paying an entry fee to take the lead and extend the countdown. When the timer expires, the last leader wins. No backend or database—everything is onchain.

---

## State Machine

```
OFF  →  ACTIVE  →  FINALIZABLE  →  OFF
```

| State         | Description                                           |
|---------------|-------------------------------------------------------|
| `OFF`         | No active round; ready for LIGHT ON                   |
| `ACTIVE`      | Round running; deadline counting down                 |
| `FINALIZABLE` | Deadline passed; anyone can call `finalize`           |
| *(back to OFF)* | Round closed; claims enabled; next round can start |

---

## Round Mechanics

### LIGHT ON (start round)

- **Cost:** Gas only (no fee).
- **Effect:**
  - Starts a new round.
  - Sets `deadline = block.timestamp + 10 minutes`.
  - Sets `currentLeader = msg.sender`.
- **Edge case:** If nobody enters and the timer reaches 0 → **NO WINNER**, no rewards distributed.

### RESET TIMER (paid entry)

- **Cost:** Entry fee (depends on selected lamp, see below).
- **Effect:**
  - Resets `deadline = block.timestamp + 10 minutes`.
  - Updates `currentLeader = msg.sender`.

---

## Lamps (fee tiers)

Three fee tiers configured in one contract—**not** three separate contracts:

| Lamp | Fee                 |
|------|---------------------|
| 1    | $1 (or equivalent)  |
| 2    | 0.001 ETH           |
| 3    | 0.01 ETH            |

Changing the lamp affects **only the next round**, not the currently active round.

---

## Payout Split (final)

| Recipient        | Share |
|------------------|-------|
| Winner           | 60%   |
| Top-20 ladder    | 25% (higher positions get more) |
| Protocol fee     | 10%   |
| Ecosystem/promo  | 5%    |

---

## Finalize & Claims

### Finalize

- Contracts do not auto-run.
- After `deadline`, anyone can call `finalize` to close the round.

### Claims

- **Winner** and **Top-20** ladder: claim after `finalize`.
- **Protocol** and **Ecosystem**: claim their shares after `finalize`.

---

## Events

| Event | Purpose |
|-------|---------|
| `RoundStarted` | Emitted when LIGHT ON starts a round (roundId, starter, deadline, lamp) |
| `TimerReset` | Emitted when RESET TIMER is called (roundId, newLeader, newDeadline, feePaid) |
| `RoundFinalized` | Emitted when round is closed (roundId, winner or NO_WINNER, totalPot) |
| `WinnerClaimed` | Emitted when winner claims reward |
| `LadderClaimed` | Emitted when a top-20 position claims |
| `ProtocolFeeClaimed` | Emitted when protocol claims its share |
| `EcosystemClaimed` | Emitted when ecosystem/promo claims its share |

---

## Security Notes

- **Reentrancy:** Use checks-effects-interactions; external calls last.
- **CEI pattern:** Validate, update state, then transfer.
- **Access control:** Only authorized functions for protocol/ecosystem claims.
- **No upgradeable proxy** in v1; immutable logic for transparency.

---

## Development

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (recommended)

### Setup

```bash
# Install Foundry (if needed)
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Install dependencies (e.g. forge-std)
forge install
```

### Local Commands

```bash
forge build
forge test
forge script script/Deploy.s.sol --rpc-url <BASE_RPC> --broadcast
```

### Deploy (Base)

```bash
forge script script/Deploy.s.sol --rpc-url <BASE_RPC> --broadcast --verify
```

Set `PRIVATE_KEY` and `BASESCAN_API_KEY` (or equivalent) for deployment and verification.

---

## License & Transparency

Public repo. Transparency-first design. One contract, no upgradeable proxy in v1.
