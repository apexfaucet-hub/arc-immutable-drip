# Split contracts: design and security note

Contracts: `contracts/Split.sol`, `contracts/SplitFactory.sol`, `contracts/SplitLimits.sol`, interfaces in `contracts/interfaces/ISplit.sol` and `ISplitFactory.sol`. Same toolchain as the launchpad (solc 0.8.28, cancun, optimizer 200 runs, OpenZeppelin Contracts 5.6.1, forge-std 1.16.2).

## What it is

`SplitFactory.createSplit(address[2] payees, uint16[2] sharesBps)` deploys one `Split` whose payees and shares are immutable. The factory has no owner, no fee, no constructor arguments and no payable function. It keeps a public list (`splitCount`, `splits(id)`, `isSplit(address)`) and emits `SplitCreated(split, payees, shares, creator)`.

A `Split` has no owner, admin, upgrade, pause, `delegatecall` or assembly. It supports ERC-20 tokens only (Arc's native USDC is also an ERC-20 at `0x3600000000000000000000000000000000000000`).

- `release(token)`: callable by anyone. Counts everything the split received since the last release and credits each payee its share. It moves no tokens. It never reverts because of rounding dust.
- `withdraw(token)`: callable only by a payee. Pays that payee its own credit (it first counts any unreleased tokens, so one call is enough). The credit is zeroed before the transfer.

No `receive`, no `fallback`, no payable function: native value sent to a split or to the factory reverts, so it cannot be sent by mistake. (The test suite sends empty calldata, plain value, unknown selectors with value and value to every valid function from five actors; all revert and nothing lands.)

## Why pull payments

`release` pays nobody. Each payee pulls its own credit with `withdraw`. A payee that the token refuses (for example a blocklisted address) can only block its own withdrawal: the other payee's credit lives in separate storage and is untouched. This is tested with a blocklisting token in both directions. A push design would have to send both payments in one call and either revert for everyone or add a fallback path, which is more code and more ways to be wrong.

## Rounding

Credit is always computed on the cumulative amount ever received, as `floor(received * share / 10000)` per payee, minus what that payee was already credited. So:

- each payee is always within 1 unit of its exact share of the cumulative inflow, however many tiny releases happen (200 releases of 1 wei at 70/30 give exactly 140 and 60);
- the unattributed rounding dust is at most 1 unit in total and is folded into the next release automatically;
- the split never credits more than it received.

A naive "floor each release separately" design would let repeated 1-unit releases give everything to one side. That is why the design uses cumulative accounting.

## Tests

Default profile: see `docs/test-output-default.txt`. Split coverage: construction validation and boundaries; exact release, events (topics and data), withdraw, double withdraw, stranger withdraw; odd amounts; a fuzz over many releases with interleaved withdrawals (never pays more than received, balance equals in minus out, each side within 1 unit, dust at most 1); a blocklisting token; reentrancy through a hook token in both `withdraw` and `release` (caught and bubbled variants); a fee-on-transfer token; factory creation, enumeration, events and error bubbling; an admin-selector and native-value probe from five actors; an ABI surface test; a stateful invariant suite.

Planted faults (`planted/` and `test-planted/`, `[profile.planted]`): see `docs/test-output-planted.txt`.

| Fault | File | Result |
| --- | --- | --- |
| (a) shares not enforced to sum 10000 | `planted/SplitNoSumCheck.sol` (and `SplitFactoryNoSumCheck.sol`, which only swaps in the faulty split) | the sum-rejection test fails, on the split and on the factory; all other tests pass |
| (b) release pays everything to payee 0 | `planted/SplitPaysAllToPayee0.sol` | 13 of 21 split tests, all 5 blocklist tests, both reentrancy payout tests and an invariant fail |
| (c) pull accounting forgets to zero payee 0's credit | `planted/SplitCreditNotZeroed.sol` | 4 split tests, both reentrancy payout tests and 2 invariants fail; blocklist tests (which never withdraw twice) pass |

## Security review

Method: manual review of `Split`, `SplitFactory` and `SplitLimits` against the requirements, plus the tests above. There is no external audit and no formal verification.

Checked and sound
- Nobody can change payees or shares: they are immutables set in the constructor; there is no function that writes them; the ABI test lists exactly eight functions on `Split` and four on `SplitFactory`, and only `release`, `withdraw` and `createSplit` change state.
- Solvency: `pending0 + pending1 + dust` equals the tokens held for a well-behaved token. The invariant suite checks balance plus withdrawn equals received and pending never exceeds the balance.
- Reentrancy: `release` and `withdraw` are `nonReentrant`; `withdraw` zeroes the credit before the transfer; the only token calls are `balanceOf` (a `STATICCALL`, which cannot re-enter) and `safeTransfer`. Tested with a hook token whose payee re-enters.
- Validation lives in the `Split` constructor (non-zero, distinct payees; shares each above zero summing to exactly 10000, summed as `uint256`), so a split deployed directly is as safe as one from the factory. The factory only relays the constructor's error.

Risks that cannot be removed
1. A payee that its token refuses to pay (blocklisted, frozen, paused token) keeps its credit forever; there is no way to redirect it. Only that payee is affected. The same applies if the split itself is frozen by the token issuer: then nobody can withdraw.
2. A payee that is a contract must be able to call `withdraw` itself. There is no `withdrawTo` and no delegation, by design.
3. Payees and shares can never be corrected. A wrong address is a permanent loss. Creators and counterparties must read `payee0`, `payee1`, `shares0` and `shares1` on the deployed split before sending revenue to it.
4. Anyone can create a split, so `isSplit(address)` only proves the split came from this factory, not that its terms are fair or that the payees are who they claim to be.
5. Up to 1 unit of rounding dust per token stays in the split until more value arrives. If nothing else is ever sent, it stays there.
6. Tokens that change balances on their own (rebasing down, confiscation) can leave pending credits above the balance. The first payee to withdraw is paid first and a later withdrawal can revert. Fee-on-transfer tokens are safe for the contract's accounting but the payee receives less than its credit.
7. Anyone can call `release` for any token address, creating ledger entries for hostile tokens. This is harmless to other tokens (each token has its own ledger); a hostile token can only break its own accounting and can only revert its own calls.
8. Native value: the split cannot receive it through any normal path. If value were forced into an address by a mechanism that bypasses code (for example a self-destruct beneficiary on a chain that still supports it), it could not be recovered by the split on a chain where native and ERC-20 balances are separate. Arc documents native USDC and the ERC-20 at `0x3600...` as two views of one balance, so any such value would show up as USDC and be released normally. I did not test a forced send.
9. Both payees are treated as unrelated parties: there is no dispute, pause or clawback path. Anything the two agents need beyond a fixed split (changing terms, adding a third party) needs a new split.
10. Test limits: the fuzz uses 40 releases per run at 256 runs and the invariant suite 128 sequences of 100 calls, on a local chain. Behaviour on Arc was not measured before deployment.
