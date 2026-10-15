# SUN test coverage

Run from the repository root:

```sh
forge build
FOUNDRY_FUZZ_SEED=0xafedbd0c51c871146ac46750bcde0fa523713d34be6fab383f0b0d2bb53bc97f forge test
```

All imports resolve to files already in the repository. The suite needs no RPC,
FFI, environment mutation, or downloaded dependencies. Fuzz tests retain Foundry's
default run count. The handler invariant is limited to 64 sequences of 48 calls.

| Suite | Coverage |
| --- | --- |
| `SUNTokenSmoke.t.sol` | Branding, decimals, exact fixed supply, full constructor allocation, external 90% pool / 10% swarm distribution, untaxed seed and wallet transfers, basic rejection paths. |
| `SUNToken.t.sol` | Buy tax and events, rounding, delegated gross allowances, infinite approvals and revocation, self transfers, swarm claims, validly encoded privileged-call probes, forbidden opcodes, fuzzed conservation. |
| `SUNTokenEdges.t.sol` | Contract deployer versus launch caller, mint event, gross-versus-net authorization and funding, maximum amounts, atomic rollback of both fee legs and allowances, sender versus spender tax classification, creator spending, recipient aliasing, zero and dust events. |
| `SUNTokenInvariant.t.sol` | Random transfers, approvals, revocations, delegated spending, buys, sells, and rejected calls. An independent ledger checks all actor balances and allowances, fixed supply, and fixed parameters after each handler action. Handler assertions fail the campaign rather than being silently discarded as reverts. |
| `UniswapV4.t.sol` | Actual vendored PoolManager at the specified address, both currency orderings, single-sided liquidity, separate trader, direct and forwarded output, exact-input and exact-output buys, untaxed sells, LP fees and withdrawals, fixed 12,500 pool fee, net-output slippage rejection, underpayment rejection and recovery. |

The PoolManager constructor executes at the specified address, preserving its
NoDelegateCall immutable. Each swap's sync, payment, settlement, and take execute
within one unlock callback. Transient currency deltas are checked inside that
callback, before Forge clears them at the transaction boundary. The deliberately
underpaid sell leaves a one-unit debt and must revert with `CurrencyNotSettled`.

The model uses six funded actors to reach varied post-launch states; its starting
balances are test setup, not a second launch distribution policy. All fees are
accounted for at the fixed creator address, including when sender and receiver
coincide or the creator is the recipient.

Integration is offline against the committed v4-core implementation, with a plain
test token at the specified IMD address. These tests do not verify live Robinhood
Chain bytecode or state, the external launch factory, its Merkle proofs, or a
production router. A live-chain fork check of those deployed components remains
outside this suite. An exact-output buy is gross at PoolManager and net at the
recipient, as required by the creator tax; minimum-output checks use actual
received balances. The forwarding helper is a test fixture, not a claim of
compatibility with every router.
