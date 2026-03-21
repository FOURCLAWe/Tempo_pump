# Tempomeme

Tempomeme is a meme launchpad built on Tempo Mainnet.

It combines:
- a `TempoUSDCLaunch` contract for token creation, curve trading, fees, and graduation
- a static multi-page frontend for market browsing, token creation, token detail, and docs
- Vercel rewrites for clean routes like `/token?token=...`

## Docs

Project documentation lives here:

- [docs/overview.md](/Users/xiaoyu/Documents/New%20project/Tempo_pump/docs/overview.md)

## Current Network

- Chain: `Tempo Mainnet`
- Chain ID: `4217`
- USDC: `0x20c000000000000000000000b9537d11c60e8b50`
- Primary launch contract: `0x25d8978d45e8987b55e3E16132eb4a65Bf4Dc6C4`

## Frontend Routes

- `/`
- `/tokens`
- `/create`
- `/token?token=<token-address>`

## Local Preview

From the project root:

```bash
python3 -m http.server 4175
```

Then open:

```text
http://127.0.0.1:4175/
```

## Notes

- The current primary contract uses an `80%` internal sale cap and manual post-graduation withdrawal for external LP setup.
