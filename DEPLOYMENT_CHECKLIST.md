# WEN OFF — Deployment + Frontend Wiring Checklist (Base Sepolia)

Single end-to-end checklist. Run from **whenoff-contracts** repo root unless stated otherwise.

---

## Setup (run once)

Create a local `.env` from the example (gitignored), then install deps and build:

```bash
cp .env.example .env
# Edit .env and fill in: PRIVATE_KEY (hex 0x...), BASE_SEPOLIA_RPC_URL, PROTOCOL_BENEFICIARY, ECOSYSTEM_BENEFICIARY

forge install foundry-rs/forge-std
export $(grep -v '^#' .env | xargs)
forge build
forge test
forge script script/Deploy.s.sol \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

---

## A) CONTRACTS REPO (whenoff-contracts)

### 1) Files/folders you must have before deploying

| Path | Required |
|------|----------|
| `foundry.toml` | Yes |
| `script/Deploy.s.sol` | Yes |
| `src/WenOff.sol` | Yes |
| `lib/forge-std/` (from `forge install foundry-rs/forge-std`) | Yes (for build) |

No `broadcast/` or `out/` needed before first deploy; they are created by Forge.

---

### 2) Environment variables

**Where:** Copy `.env.example` to `.env` in the **repo root** (`whenoff-contracts/.env`), then fill in real values. Do **not** commit `.env` (it is in `.gitignore`).

**Required:**

| Variable | Example format | Example (fake) |
|----------|----------------|----------------|
| `PRIVATE_KEY` | Hex, 0x + 64 hex chars | `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80` |
| `BASE_SEPOLIA_RPC_URL` | HTTPS URL | `https://sepolia.base.org` or Alchemy/Infura URL |
| `PROTOCOL_BENEFICIARY` | Ethereum address | `0x1234567890123456789012345678901234567890` |
| `ECOSYSTEM_BENEFICIARY` | Ethereum address | `0x1234567890123456789012345678901234567890` |

**Optional (constructor defaults used if unset):**

| Variable | Example |
|----------|---------|
| `FEE_ONE_WEI` | `1000000000000000` (0.001 ether in wei) |
| `FEE_TWO_WEI` | `1000000000000000` |
| `FEE_THREE_WEI` | `10000000000000000` (0.01 ether) |

---

### 3) Exact commands (from repo root)

```bash
# 1) Load env (from repo root)
export $(grep -v '^#' .env | xargs)

# 2) Build
forge build

# 3) Test
forge test

# 4) Deploy to Base Sepolia (broadcast)
forge script script/Deploy.s.sol \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

If `forge build` fails with missing `forge-std`, run: `forge install foundry-rs/forge-std`

---

### 4) Where the deployed contract address appears

**A) Terminal output**

After a successful run, look for this block:

```
WenOff deployed
  deployer:  0x...
  chainId:   84532
  contract:  0x...
```

- **Copy the deployed address from the line that starts with `  contract: `** — the value is the `0x...` right after that.

**B) File in workspace after broadcast**

- **Path:** `broadcast/Deploy.s.sol/84532/run-latest.json`  
  (If your Forge version uses the full script path: `broadcast/script/Deploy.s.sol/84532/run-latest.json`.)

- **What to copy:** Open the JSON file. In the `transactions` array, find the object whose `transactionType` is `CREATE` (or that has `contractAddress`). Copy the value of **`contractAddress`**.

---

### 5) What to save after deploy and where to record it

Save these three values:

| What | Where to get it |
|------|------------------|
| **Contract address** | Terminal line `contract: 0x...` or `run-latest.json` → `contractAddress` |
| **Chain ID** | Terminal line `chainId: 84532` (Base Sepolia) |
| **Deploy tx hash** | Terminal “Transaction hash” line for the deployment, or `run-latest.json` → `hash` of the CREATE tx |

**Where to record:** In this repo, add a short **Deployed (Base Sepolia)** section in `README.md` (or a one-line note), for example:

```markdown
### Deployed (Base Sepolia)
- Contract: `0x...` (chainId: 84532). Deploy tx: `0x...`.
```

Do **not** put `PRIVATE_KEY` or RPC URLs in the README.

---

### 6) (Optional) BaseScan verification

Run **after** deployment, from the contracts repo:

1. Get an API key: https://basescan.org/myapikey  
2. Set `BASESCAN_API_KEY` in your environment.  
3. Encode constructor args (use the same values as in `.env` for the deploy):

```bash
cast abi-encode "constructor(uint256,uint256,uint256,address,address)" \
  "$FEE_ONE_WEI" "$FEE_TWO_WEI" "$FEE_THREE_WEI" "$PROTOCOL_BENEFICIARY" "$ECOSYSTEM_BENEFICIARY"
```

4. Verify (replace `<DEPLOYED_ADDRESS>` and `<ENCODED_ARGS>`):

```bash
forge verify-contract <DEPLOYED_ADDRESS> src/WenOff.sol:WenOff \
  --chain-id 84532 \
  --etherscan-api-key $BASESCAN_API_KEY \
  --constructor-args <ENCODED_ARGS>
```

---

## B) FRONTEND REPO (whenoff-frontend)

### 7) Wiring frontend to Base Sepolia

**Contract address**

- Create a config file, e.g. `src/config.ts` or `src/constants.ts`.
- Define the deployed address and chain ID:

```ts
export const WENOFF_CONTRACT_ADDRESS = '0x...'  // paste from terminal or run-latest.json
export const CHAIN_ID_BASE_SEPOLIA = 84532
```

- Use `WENOFF_CONTRACT_ADDRESS` wherever you instantiate the contract (ethers/viem/wagmi).

**ABI**

- Create `src/abi/WenOff.json` (or `src/contracts/WenOff.json`).
- Paste the **full JSON** from the Foundry build output (see section 8). The frontend only needs the **`abi`** array; you can paste the whole file and use `WenOffAbi.abi` or extract the `abi` array only.

**Default chain**

- If using wagmi: in your config (e.g. `wagmi.config.ts` or the provider config), set `chains` to include Base Sepolia and set it as the default (e.g. first in the list or via `defaultChain`).
- If using a different provider (e.g. ethers + custom provider), pass `new JsonRpcProvider(BASE_SEPOLIA_RPC_URL)` and use chainId `84532` for checks.

**Wrong network message + switch button**

- Read `chainId` from the connected wallet (e.g. `useChainId()` in wagmi, or `provider.getNetwork().then(n => n.chainId)`).
- If `chainId !== 84532`: show a message like “Please switch to Base Sepolia” and a button that calls the wallet’s “switch chain” (e.g. wagmi `switchChain` or `window.ethereum.request({ method: 'wallet_switchEthereumChain', params: [{ chainId: '0x14a34' }] })` for 84532 = 0x14a34).

---

### 8) Where to get the ABI (Foundry output)

**Path in whenoff-contracts repo (after `forge build`):**

```
whenoff-contracts/out/WenOff.sol/WenOff.json
```

- Open `WenOff.json`.
- Copy the **entire file** (or only the **`abi`** array).
- In the frontend, save it as e.g. `src/abi/WenOff.json` and import:

```ts
import WenOffAbi from '@/abi/WenOff.json'
// use WenOffAbi.abi when creating the contract instance
```

---

### 9) Minimal “test panel” (Sepolia-only) plan

**Buttons (each calls the contract):**

| Button | Contract call |
|--------|----------------|
| LIGHT ON | `lightOn(lampId)` — e.g. lampId 0 (ONE). No value. |
| RESET TIMER | `enter()` or `resetTimer()` with `value: entryFeeWei[lampId]` (read from contract or config). |
| FINALIZE | `finalize()`. |
| CLAIM | `claim(roundId)` with current `roundId`. |

**Raw debug values (read from contract, display as text):**

- `roundId` → `currentRoundId()`
- `state` → `roundState()` (0=OFF, 1=ACTIVE, 2=FINALIZABLE)
- `deadline` → `roundDeadline()` (timestamp)
- `leader` → `roundLeader()`
- `pot` → `roundPot()`
- `lampId` → `roundLamp()` (0/1/2)
- `claimableAmount` → `getClaimable(roundId, userAddress)` for the connected wallet

Use a single “Refresh” or live hook to refetch these after each action.

---

### 10) End-to-end manual test flow

| Step | Action | What to check |
|------|--------|----------------|
| 1 | Connect wallet; ensure chain is Base Sepolia (84532). | Wrong-network UI hides when on 84532. |
| 2 | **LIGHT OFF → LIGHT ON:** Click LIGHT ON (e.g. lamp ONE). | `roundState` = ACTIVE, `roundId` increments, `leader` = your address, `deadline` ≈ now + 10 min, `pot` = 0. |
| 3 | **Paid entry:** From another wallet (or same), call RESET TIMER with the required ETH (e.g. 0.001 ETH for lamp ONE). | `leader` and `deadline` update, `pot` increases. |
| 4 | **Finalize timing:** Contract uses a 10-minute timer. Options: (a) Wait ~10 minutes on Sepolia, or (b) Deploy a test contract with a shorter duration for UI testing. In production, after deadline passes, anyone can call FINALIZE. | After deadline, FINALIZE succeeds; round state becomes OFF, winner/ladder/protocol/ecosystem can claim. |
| 5 | Click **FINALIZE** (after deadline). | `roundFinalized(roundId)` true; winner set if pot > 0. |
| 6 | **Claim:** Winner / ladder / protocol / ecosystem click CLAIM with the finished `roundId`. | Each can claim once; balance increases; second claim reverts. |
| 7 | **No-winner scenario:** New round: LIGHT ON, then **do not** call RESET TIMER. Wait until after deadline, then FINALIZE. | Winner is `address(0)`, no payouts; claim should revert or show 0 for that round. |

**Note:** The UI cannot “warp” time. On Base Sepolia you either wait ~10 minutes or deploy a test contract with a shorter round duration for faster UI testing.

---

## Quick reference

- **Deploy (contracts):** `forge script script/Deploy.s.sol --rpc-url $BASE_SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast`
- **Copy address from:** Terminal line `  contract: 0x...` or `broadcast/Deploy.s.sol/84532/run-latest.json` → `contractAddress`
- **ABI path:** `out/WenOff.sol/WenOff.json` → `abi` array (or full file in frontend)
- **Chain ID Base Sepolia:** 84532
