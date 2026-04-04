# TempoBoard Whitepaper

## 1. Overview

TempoBoard is a pathUSD-native meme launch board built on Tempo Mainnet. The protocol is designed around simple, stablecoin-denominated price discovery, allowing any user to create a token, trade on an internal bonding curve, and graduate into external liquidity after the internal sale target is completed.

The core design goals are:

- simple token launches
- clear curve-based price discovery
- stablecoin settlement from start to finish
- a defined graduation path into external liquidity
- protocol-level value capture around `$TEB`

## 2. Network and Settlement

TempoBoard is deployed on Tempo Mainnet.

- Network: `Tempo Mainnet`
- Chain ID: `4217`
- RPC: `https://rpc.tempo.xyz`
- Settlement asset: `pathUSD`
- pathUSD address: `0x20c0000000000000000000000000000000000000`

Using a single chain and a single settlement asset keeps the launch flow easier to understand. Token creation, curve trading, graduation accounting, and external liquidity preparation are all expressed in stablecoin terms.

## 3. Token Launch Structure

Each launch on TempoBoard follows the same base model:

- fixed total supply: `1,000,000,000`
- internal curve sale cap: `800,000,000`
- remaining supply after graduation: `200,000,000`
- settlement asset for internal trading: `pathUSD`

This means:

- `80%` of total supply is available on the internal curve
- `20%` of total supply is reserved for post-graduation liquidity

Any user can create a token. Once created, the token enters the internal trading phase and remains there until the graduation threshold is met.

## 4. Price Discovery Model

TempoBoard uses a quadratic bonding curve for price discovery.

### Curve Formula

```text
price(sold) = 0.000003 + 0.000062 * (sold / 800,000,000)^2
```

Where:

- `sold` is the cumulative number of tokens sold from the internal curve
- `800,000,000` is the internal sale cap

This creates a curve that starts relatively low and accelerates upward as more supply is sold.

### Detailed Calculation

```text
saleCap = 800,000,000
r = sold / saleCap

price(sold) = 0.000003 + 0.000062 * r^2
```

### Buy Calculation

```text
buyTax = pathUsdIn * 1%
netPathUsdIn = pathUsdIn - buyTax
tokensOut = netPathUsdIn / price(sold)
```

### Sell Calculation

```text
grossPathUsdOut = tokensIn * price(sold)
sellTax = grossPathUsdOut * 1%
netPathUsdOut = grossPathUsdOut - sellTax
```

This means the protocol applies the trading tax first, and only the net settlement amount is used for the actual buy or sell result.

## 5. Graduation and External Liquidity

Graduation is triggered once the internal curve reaches the sale cap:

```text
graduate when sold >= 800,000,000
```

In the current model:

- full internal curve fill is about `19,124.58 pathUSD` in gross user spend
- after the `1%` trading tax, the contract retains about `18,933.33 pathUSD` net

At graduation:

- the remaining `20%` of token supply
- and `18,933.33 pathUSD`

are intended to be deployed as liquidity on `Uniswap V2`.

This creates a clear transition from internal curve price discovery to external market liquidity.

## 6. Trading Tax and Protocol Revenue Split

TempoBoard applies a `1%` trading tax.

That tax is split as follows:

- `50%` to buy back and burn the best-performing token from the past `24 hours`
- `20%` to buy back the best-performing token from the past `24 hours` for partner distribution
- `30%` to staking rewards

### Protocol Fee Split Formula

For a given epoch `e`:

```text
taxPool(e) = totalTradingVolume(e) * 1%

burnBuybackPool(e) = taxPool(e) * 50%
partnerBuybackPool(e) = taxPool(e) * 20%
stakingPool(e) = taxPool(e) * 30%
```

This means each 24-hour period converts trading activity into:

- direct buyback-and-burn pressure for the best-performing token on the board
- a partner distribution pool backed by the best-performing token on the board
- a reward stream for stakers

## 7. Staking Rewards Formula

Staking rewards are distributed every `24 hours`.

For each 24-hour reward epoch:

```text
reward(i, e) = stakingPool(e) * stake(i, e) / totalStaked(e)
```

Where:

- `reward(i, e)` = reward paid to wallet `i` in epoch `e`
- `stakingPool(e)` = the staking allocation generated during epoch `e`
- `stake(i, e)` = the amount staked by wallet `i` at the reward snapshot for epoch `e`
- `totalStaked(e)` = the total amount staked across all wallets at that same snapshot

### Interpretation

If a wallet holds `5%` of the total staked amount at the time of distribution, it receives `5%` of that day’s staking pool.

Example:

```text
If:
taxPool(e) = 10,000
stakingPool(e) = 10,000 * 30% = 3,000
stake(i, e) / totalStaked(e) = 5%

Then:
reward(i, e) = 3,000 * 5% = 150
```

This design keeps reward distribution transparent and directly linked to protocol trading activity.

## 8. Best-Performing Token Logic

TempoBoard evaluates the best-performing token across the previous `24 hours` and uses that token as the target asset for two fee destinations:

- the `50%` buyback-and-burn allocation
- the `20%` partner distribution allocation

This creates a feedback loop where the strongest token on the board can receive additional market attention, while part of the resulting fee value is permanently removed from circulation and part is routed to ecosystem partners.

## 9. Summary

TempoBoard is designed as a stablecoin-native launch board on Tempo:

- fixed supply launches
- quadratic bonding curve price discovery
- internal sale cap at `80%`
- graduation into external liquidity
- `pathUSD` settlement
- board-level token buybacks, burns, partner distribution, and staking rewards

The protocol turns trading activity into a recurring cycle:

1. users create and trade tokens
2. the protocol collects a `1%` trading tax
3. `50%` supports buyback and burn of the strongest token from the past `24h`
4. `20%` supports buybacks of the strongest token from the past `24h` for partner distribution
5. `30%` funds staking rewards

This creates a launch system where market activity, token discovery, partner incentives, and staking participation all reinforce each other.
