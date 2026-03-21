# Tempomeme Docs

## 1. Chain

Tempomeme is built on Tempo Mainnet and the current frontend is configured around that chain only.

- Network: `Tempo Mainnet`
- Chain ID: `4217`
- RPC: `https://rpc.tempo.xyz`
- USDC settlement token: `0x20c000000000000000000000b9537d11c60e8b50`

What this means in practice:

- Wallets need to be connected to Tempo Mainnet.
- Token creation, buying, and selling all use the same Tempo-side launch contract.
- USDC is the settlement asset used by the current site flow.

## 2. Curve Formula and External Migration

Current primary launch contract:

- Launch contract: `0x25d8978d45e8987b55e3E16132eb4a65Bf4Dc6C4`
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

## 3. Official Token

The official ecosystem token is `$TME`.

Platform fee policy:

- `50%` of trading fees are allocated to buy back `$TME`.
- The remaining `50%` is reserved for maintenance and project development.

This policy is meant to do two things at the same time:

- route part of platform fee value back into the official token
- keep part of platform fee value available for product upkeep, iteration, and broader ecosystem growth
