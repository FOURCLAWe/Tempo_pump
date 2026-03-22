# Tempomeme on Tempo

Tempomeme is a USDC-native meme launchpad built on Tempo Mainnet. The product combines Tempo's payments-first design with internal curve trading, a clear graduation threshold, and a defined post-curve liquidity path.

## 1. Chain

Tempomeme is built on Tempo Mainnet because the launch flow is expressed in stablecoin terms from start to finish. The current frontend is configured around a single chain and a single settlement asset.

- Network: `Tempo Mainnet`
- Chain ID: `4217`
- RPC: `https://rpc.tempo.xyz`
- USDC settlement token: `0x20c000000000000000000000b9537d11c60e8b50`

What this means in practice:

- Wallets need to be connected to Tempo Mainnet.
- Token creation, buying, and selling all use the same Tempo-side launch contract.
- USDC is the settlement asset used by the current site flow.
- This keeps launch pricing, trade flow, and graduation accounting in USD terms.

## 2. Curve Formula and External Migration

Tempomeme uses a quadratic internal curve for price discovery. Trading stays inside the platform until 80% of supply is sold, and only then does the project graduate toward external liquidity deployment.

Current primary launch contract:

- Launch contract: `0x37B8Cce1b4aeD401A26f01B8f19f87d352Cb3ABf`
- Internal sale cap: `800,000,000` tokens
- This equals `80%` of the total supply

Curve formula:

```text
price(sold) = 0.000003 + 0.000062 * (sold / 800,000,000)^2
```

Detailed calculation:

```text
saleCap = 800,000,000
r = sold / saleCap

price(sold) = 0.000003 + 0.000062 * r^2

buyFee = usdcIn * 1%
netUsdc = usdcIn - buyFee
tokensOut = netUsdc / price(sold)

grossUsdcBack = tokensIn * price(sold)
sellFee = grossUsdcBack * 1%
usdcOut = grossUsdcBack - sellFee

migrate when sold >= 800,000,000
```

How to read it:

- The curve starts near `0.00000300 USDC`.
- Price increases as more tokens are sold from the internal curve inventory.
- Because the formula is quadratic, price acceleration is stronger later in the sale than at the beginning.
- The ratio form is `r = sold / 800,000,000`, so price growth is tied directly to internal sale progress.
- On buys, the contract removes the 1% fee first and converts the remaining USDC at the current curve price.
- On sells, the contract computes gross USDC at the current curve price and then deducts the 1% fee.

External migration condition:

- The current contract migrates to external liquidity after the internal curve sells out `800,000,000` tokens.
- In other words, the internal curve must be fully filled before the project moves to the external liquidity stage.
- On a no-sell path, that is about `19,124.58 USDC` gross user spend.
- After the `1%` trading fee, the contract retains about `18,933.33 USDC` net.
- At graduation, the remaining `20%` of token supply and `19,124.58 USDC` are intended to be added as liquidity on `Uniswap V2`.

## 3. Official Token

The official ecosystem token is `$TME`. Tempomeme describes the exchange fee policy around a `1%` trading fee, with most of that fee routed back into the official token and the remainder reserved for the treasury wallet.

Platform fee policy:

- `90%` of the `1%` trading fee is allocated to buy back `$TME` and distribute it through airdrops.
- The remaining `10%` of the `1%` trading fee flows into the treasury wallet.

This policy is meant to do two things at the same time:

- route most fee value back into `$TME` through buybacks and user airdrops
- keep a treasury reserve available for protocol operations, upkeep, and growth
