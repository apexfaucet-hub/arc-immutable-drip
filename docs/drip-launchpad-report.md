# Drip Launchpad: contracts, tests and review report

Scope of this turn: contracts, tests, planted-fault profile and deploy script only. Nothing was deployed. No frontend was touched.

## 1. Files created or changed

Changed
- `foundry.toml` (added `via_ir = false`, `ffi = false`, read-only `fs_permissions` on `contracts/out`, `[fuzz]`, `[invariant]`, `[profile.planted]`)
- `AGENTS.md` (appended a Drip Launchpad section)

Created, production
- `contracts/DripLimits.sol`
- `contracts/DripFaucet.sol`
- `contracts/DripVault.sol`
- `contracts/DripLaunchpad.sol`
- `contracts/interfaces/IDripFaucet.sol`
- `contracts/interfaces/IDripVault.sol`
- `contracts/interfaces/IDripLaunchpad.sol`

Created, deploy script (not run on a live chain; simulated locally only)
- `contracts/script/DeployDemo.s.sol`
- `contracts/script/DripDemoToken.sol`

Created, tests (default profile)
- `contracts/test/spec/SpecBase.sol`, `RealHooks.sol`, `FaucetSpec.sol`, `VaultSpec.sol`, `LaunchpadSpec.sol`, `ReentrancySpec.sol`, `NoBackdoorSpec.sol`, `InvariantSpec.sol`
- `contracts/test/FaucetReal.t.sol`, `VaultReal.t.sol`, `LaunchpadReal.t.sol`, `ReentrancyReal.t.sol`, `NoBackdoorReal.t.sol`, `InvariantReal.t.sol`, `AbiSurface.t.sol`
- `contracts/test/mocks/MockERC20.sol`, `FeeToken.sol`, `NoOpTransferFromToken.sol`, `HookToken.sol`, `ReentrantToken.sol`, `ClaimAttacker.sol`, `DripHandler.sol`

Created, planted faults (only compiled by `[profile.planted]`)
- `planted/FaucetNoCooldown.sol` (P1), `planted/VaultNoPeriod.sol` (P2), `planted/VaultAccumulates.sol` (P3), `planted/LaunchpadTrustsAmount.sol` (P4), `planted/FaucetReentrant.sol` (P5)
- `test-planted/P1_FaucetNoCooldown.t.sol`, `P2_VaultNoPeriod.t.sol`, `P3_VaultAccumulates.t.sol`, `P4_LaunchpadTrustsAmount.t.sol`, `P5_FaucetReentrant.t.sol`

Created, docs
- `README.md`, `docs/drip-launchpad-report.md` (this file), `docs/build-output.txt`, `docs/test-output-default.txt`, `docs/test-output-planted.txt`

## 2. Toolchain

- solc 0.8.28 (`solc_version = "0.8.28"`, `auto_detect_solc = false`)
- `evm_version = "cancun"`
- optimizer enabled, `optimizer_runs = 200`, `via_ir = false`
- `ffi = false`; `fs_permissions = [{ access = "read", path = "contracts/out" }]`
- OpenZeppelin Contracts 5.6.1 (`node_modules/@openzeppelin/contracts`, pinned exactly in `package.json`)
- forge-std 1.16.2 (`lib/forge-std`), Foundry forge 1.7.1
- Fuzz: 256 runs. Invariant: 128 runs, depth 100, `fail_on_revert = false`.

## 3. Test output

- Default profile (`forge test -vv`): 68 passed, 0 failed. Full output: `docs/test-output-default.txt`.
- Planted profile (`FOUNDRY_PROFILE=planted forge test -vv`): 59 passed, 12 failed (all 12 expected). Full output: `docs/test-output-planted.txt`.

Planted results (each failure is an assertion inside the test body, never in setUp, never a compile error):

| Fault | Suite | Failing tests | Sibling tests |
| --- | --- | --- | --- |
| P1 FaucetNoCooldown | FaucetSpec | ClaimOnceEver, CooldownBoundary, CooldownIsEnforcedPerAddress | 8 pass |
| P2 VaultNoPeriod | VaultSpec | DripTwiceInOnePeriodReverts, MaxPeriodFirstDripImmediateSecondNever, MissedPeriodsDoNotAccumulate | 9 pass |
| P3 VaultAccumulates | VaultSpec | MissedPeriodsDoNotAccumulate, DripMathOver1000Drips (fuzz) | 10 pass |
| P4 LaunchpadTrustsAmount | LaunchpadSpec | FeeOnTransferCreditsOnlyWhatArrived, RejectsTokenThatMovesNothing | 19 pass |
| P5 FaucetReentrant | ReentrancySpec | ClaimReentryFailsAndOuterClaimPaysOnce, BubbledClaimReentryRevertsEverything | drip and launch re-entry pass; all 11 FaucetSpec tests pass |

## 4. Diffs of the planted copies against production

### P1: DripFaucet.sol -> FaucetNoCooldown.sol

```diff
13c13
< contract DripFaucet is IDripFaucet, ReentrancyGuard {
---
> contract FaucetNoCooldown is IDripFaucet, ReentrancyGuard {
50d49
<         if (block.timestamp < nextClaimAt[msg.sender]) revert CooldownActive(nextClaimAt[msg.sender]);
```

### P2: DripVault.sol -> VaultNoPeriod.sol

```diff
14c14
< contract DripVault is IDripVault, ReentrancyGuard {
---
> contract VaultNoPeriod is IDripVault, ReentrancyGuard {
50d49
<         if (block.timestamp < nextDripAt) revert DripTooSoon(nextDripAt);
```

### P3: DripVault.sol -> VaultAccumulates.sol

```diff
14c14
< contract DripVault is IDripVault, ReentrancyGuard {
---
> contract VaultAccumulates is IDripVault, ReentrancyGuard {
54c54
<         nextDripAt = block.timestamp + period;
---
>         nextDripAt = nextDripAt + period;
```

### P4: DripLaunchpad.sol -> LaunchpadTrustsAmount.sol

```diff
15c15
< contract DripLaunchpad is IDripLaunchpad, ReentrancyGuard {
---
> contract LaunchpadTrustsAmount is IDripLaunchpad, ReentrancyGuard {
62c62
<         uint256 received = token.balanceOf(vault) - balanceBefore;
---
>         uint256 received = amount;
```

### P5: DripFaucet.sol -> FaucetReentrant.sol

```diff
13c13
< contract DripFaucet is IDripFaucet, ReentrancyGuard {
---
> contract FaucetReentrant is IDripFaucet, ReentrancyGuard {
49c49
<     function claim() external nonReentrant returns (uint256 amount) {
---
>     function claim() external returns (uint256 amount) {
54d53
<         nextClaimAt[msg.sender] = block.timestamp + cooldown;
55a55
>         nextClaimAt[msg.sender] = block.timestamp + cooldown;
```


## 5. Deviations from SPEC.md

See the chat summary; reproduced here.

1. Error names and placement. The spec fixes only `CooldownActive`, `FaucetEmpty`, `DripTooSoon`, `NothingToDrip`, `NothingReceived` and "a custom error on an out-of-range id". I added: `InvalidToken`, `InvalidClaimAmount`, `CooldownTooShort(uint64)`, `InvalidFaucet`, `InvalidDripBps(uint16)`, `PeriodTooShort(uint64)`, `InvalidAmount`, `UnknownLaunch(uint256)`. Events and errors are declared in the three interfaces (`IDripFaucet`, `IDripVault`, `IDripLaunchpad`) and inherited, so the faulty copies share identical selectors. `DripFaucet.CooldownActive.selector` and `IDripFaucet.CooldownActive.selector` are the same value; the tests use the interface form.
2. Imports are root-relative (`contracts/DripLimits.sol`, ...) instead of `./`. This makes the planted copies byte-identical to production except for the one removed check and the renamed contract.
3. Constructor and `launch` parameter names: constructors use `token_`, `faucet_`, ... (a plain `token` would shadow the public immutable getter). Types and order are as specified.
4. NatSpec for the external functions lives in the interfaces and is attached with `@inheritdoc`, plus `@dev` notes on the implementations.
5. Deploy script path is `contracts/script/DeployDemo.s.sol` (this project's Foundry `script` directory), with the token in `contracts/script/DripDemoToken.sol`. Because that directory is inside `src`, both are compiled by the default build.
6. `[profile.planted]` uses `src = "planted"`, `test = "test-planted"`, `out = "out-planted"`, `cache_path = "cache-planted"` so it can never overwrite `contracts/out`. The planted tests import the shared spec contracts from `contracts/test/spec/`.
7. `SpecBase` has no `setUp` of its own (it exposes `_initTime()`, which does the `vm.warp(1_750_000_000)`): Solidity's multiple-inheritance override rules otherwise force every concrete test to restate `setUp`. Each spec's `setUp` calls `_initTime()` first.
8. The hook base `RealHooks` is shared by the `*Real` tests and by the planted tests, which override only the faulty hook. P5 is run twice: against `FaucetSpec` (expected all PASS) and `ReentrancySpec` (expected the two claim re-entry tests to FAIL).
9. Case 8(a) (ABI enumeration) and the invariant suite run against the production contracts only; there is no planted target for them. The invariant suite uses a standard token; fee-on-transfer behaviour is covered by the example-based test (case 7).
10. I did not use inline `forge-config` to lower the fuzz runs of the 1,000-drip test: 256 runs finish in about 7 seconds, so no reduction was needed.
11. The spec's "no inline assembly in our own code" holds for production and test code written here; OpenZeppelin's own assembly (SafeERC20, Math) is used as shipped.

## 6. Security review

Method: manual line-by-line review of the three production contracts and the library against the spec's hard rules, plus the test suite above (example, fuzz and invariant). No external audit and no formal verification was done.

What I checked and found sound
- Authority: there is no owner, role, signature, proxy, `delegatecall`, `selfdestruct`, assembly, `receive`, `fallback` or payable function. The ABI test proves the external surface is exactly the expected list and that only `launch`, `drip` and `claim` are state-changing. Probing 40 admin selectors, empty calldata and ETH from three actors on all three contracts always reverts.
- Reentrancy: `launch`, `drip`, `claim` are `nonReentrant` (storage guard) and write state before the token transfer. `balanceOf` calls compile to `STATICCALL`, so a hostile token cannot re-enter through them. A hook token cannot get a second payout in one claim (tested both ways) and cannot re-enter `drip` or `launch`.
- Math: `Math.mulDiv(bal, bps, 10000)` with `bps <= 9999` is strictly below `bal` for `bal >= 1`, and cannot overflow for any `uint256`, so a drip never empties a vault. Timestamp sums are `uint256` plus a `uint64`, which cannot overflow.
- Launch accounting: the vault is credited with the measured balance difference, `NothingReceived` guards a token that moves nothing, `launch` only pulls from `msg.sender`, and the factory never holds tokens.
- Validation is identical in the factory and in the vault and faucet constructors (shared `DripLimits`).

Risks I could not remove (by design or inherent to the model)
1. Funds are permanently locked in the system: no rescue exists. Tokens donated to a vault or faucet, or sent to the factory by mistake, can never be recovered.
2. Dust is stranded forever. The vault decays geometrically and the last units (up to `10000 / dripBps` wei) can never be dripped (`NothingToDrip`).
3. Token issuer powers. If the launched token can freeze, blocklist or pause (USDC-style), the issuer can freeze the vault or faucet and the funds are stuck with no recourse. A blocklisted claimer simply reverts and keeps their cooldown.
4. Permissionless launch with any token. A hostile or look-alike token can be launched. Our contracts stay safe, but a user who claims it is trusting that token. For a malicious token the `amountReceived` in `Launched` is only as honest as the token's `balanceOf`; indexers and UIs must not trust it.
5. Fee-on-transfer, rebasing and deflationary tokens: drip and claim events report the amount sent, not the amount received. A negatively rebasing token can shrink the vault without any call. Behaviour is as specified, not a bug.
6. Sybil drain of the faucet. The cooldown is per address, so one party with many addresses can claim `claimAmount` per address per cooldown and drain the faucet faster than intended; later claimants then get `FaucetEmpty`. Nothing trusted can prevent this.
7. Anyone can call `drip()`, including at the very first block of a launch. That is intended, but the launcher cannot delay the first drip or choose when it happens.
8. Launcher footguns that cannot be undone: a huge `period` or `cooldown` (up to `type(uint64).max`) effectively freezes drips or makes claims one-time; a `claimAmount` far above the faucet's funding drains it on the first claim. A UI must warn before launch.
9. Standalone vault or faucet deployments only check non-zero addresses. A token address with no code makes every later call revert; the factory path would reject such a token at launch.
10. Cross-contract effects: each contract has its own guard, so a hook token inside `vault.drip()` could call `faucet.claim()` (a different contract). Accounting stays consistent because `claim` pays from the live balance, and this was reasoned about rather than separately tested.
11. Timestamps can be nudged by block producers by a few seconds. The minimum period (1 hour) and cooldown (1 minute) make this immaterial.
12. Lint notes: `forge build` reports `block-timestamp` notes on the two time checks (intended) and an unchecked-transfer note in the test handler.
13. Test limits: the invariant suite uses a standard token, runs 128 sequences of 100 calls, and was not run against a fork or live chain. Gas on Arc was not measured here.
