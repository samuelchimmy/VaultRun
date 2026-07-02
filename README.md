# VaultRun

VaultRun is a web3-powered rhythm obstacle runner game running entirely in a single HTML file using vanilla JavaScript, Canvas2D, and the Web Audio API. It integrates with the Celo blockchain via `viem` to support daily onchain challenges using stablecoins (USDm, USDT, USDC).

## Features
- **No External Engines:** Pure Canvas2D rendering and vanilla JS.
- **Web Audio Synth:** All sound effects and music are generated synthetically using the Web Audio API without any external dependencies.
- **Procedural Obstacles:** Mulberry32 PRNG seeded by the current UTC day generates identical courses for all players daily.
- **Smart Contract Economy:** Fully transparent payouts for the top 3 daily scorers and an automated developer rake.
- **MiniPay Optimized:** Designed primarily for the MiniPay in-app browser on Android.

## Setup Instructions
1. Since the application is a single `index.html` file, you can serve it with any standard HTTP server. E.g. `npx serve .` or `python -m http.server 3000`.
2. Connect using MiniPay. If testing on desktop, you will need a wallet extension like MetaMask connected to the Celo Mainnet.

## Deployment Steps
### Smart Contract
1. Use [Remix IDE](https://remix.ethereum.org/) or Hardhat/Foundry to deploy `VaultRunGame.sol` to the Celo Mainnet.
2. In the constructor, provide the developer wallet address that will receive the 20% rake.
3. Verify the contract source code on [Celoscan](https://celoscan.io/).

### Application
1. In `index.html`, locate `appState.contractAddress = '0x0000000000000000000000000000000000000000'; // DEPLOY_AND_REPLACE` around line 240.
2. Replace the address with the deployed `VaultRunGame` smart contract address.
3. Host the `index.html` file on any static hosting provider (e.g., GitHub Pages, Vercel, Netlify, Cloudflare Pages).

## License
MIT License
