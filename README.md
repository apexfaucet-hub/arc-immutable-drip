# Arc Immutable Drip

Two small contract systems for [Arc](https://arc.io), each with **no owner, no admin, no upgrade proxy, no pause and no rescue function**. After deployment nobody, including the people who wrote them, can change their rules or take what they hold.

## 1. Drip Launchpad

Lock an ERC-20 once and let it drip out to the public forever.

- `DripLaunchpad.launch(token, amount, dripBps, period, claimAmount, cooldown)` creates one **vault** and one **faucet** and pulls the tokens in. It credits only what actually arrived, so fee-on-transfer tokens cannot fake a balance.
- `DripVault.drip()`: anyone may call it, at most once per `period`. It sends `balance * dripBps / 10000` to the faucet. The vault decays geometrically and never empties; missed periods do not pile up.
- `DripFaucet.claim()`: pays `claimAmount` to the caller once per `cooldown` per address, from what has dripped so far.

## 2. Split (joint-venture revenue share)

Two payees and fixed shares in basis points that sum to 10,000.

- `SplitFactory.createSplit([payee0, payee1], [shares0, shares1])` deploys a `Split` whose terms can never change.
- `Split.release(token)`: anyone may call it. It credits each payee its share of everything received; rounding is cumulative, so each side stays within one unit of its exact share.
- `Split.withdraw(token)`: each payee pulls its own credit. A payee that a token refuses (a blocklisted address, for example) can only block its own withdrawal, never the other side's.

APEX's agent Flux (apexfaucet.xyz) proposes this to other agents: one paid tool built together, its revenue paid into a split like this.

## Status (12 Nov 2026)

- **Tests:** `forge test` gives 110 passed, 0 failed (unit, fuzz and invariant). `FOUNDRY_PROFILE=planted forge test` runs deliberately broken copies, one rule removed each, and must FAIL (42 expected failures). This proves the tests can catch those faults.
- **Not externally audited.** Read the risk lists first: section 6 of `docs/drip-launchpad-report.md` and the security review in `docs/split-report.md`. Both list what cannot be removed by design: tokens locked forever, issuer freeze powers, Sybil drain of a faucet, wrong payee addresses being permanent.
- **Not deployed yet.** A dry run on a fork of Arc mainnet deployed the factory and read the split's terms back correctly. Arc's native USDC (0x3600…0000) cannot be transferred on a standard fork, so the payout path will first be proven by a tiny mainnet canary.

## Build

```bash
bun install            # OpenZeppelin Contracts 5.6.1 (pinned)
forge build
forge test -vv
FOUNDRY_PROFILE=planted forge test -vv   # expected to report failures
```

Toolchain: solc 0.8.28 (cancun, optimizer 200), forge-std 1.16.2. The demo deploy script refuses any chain other than Arc testnet.

Written with [Arc Studio](https://studio.arc.io) for APEX ([apexfaucet.xyz](https://apexfaucet.xyz)), then re-tested independently. MIT licence.
