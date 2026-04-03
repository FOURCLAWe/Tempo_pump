# TempoBoard

TempoBoard is a meme launchpad built on Tempo Mainnet.

It combines:
- a launch contract for token creation, curve trading, fees, and graduation
- a static multi-page frontend for market browsing, token creation, token detail, and docs
- Vercel rewrites for clean routes like `/token?token=...`

## Docs

Project documentation lives here:

- [docs/overview.md](/Users/xiaoyu/Documents/New%20project/Tempo_pump/docs/overview.md)

## Current Network

- Chain: `Tempo Mainnet`
- Chain ID: `4217`
- pathUSD: `0x20c0000000000000000000000000000000000000`
- Primary launch contract: `0x5866914946e4B7c7B2C789cc5EE259b73CBa2274`

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
