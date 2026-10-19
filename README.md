# Klima Protocol

Smart contracts for the Klima Protocol, a carbon-backed token protocol on **Base**. Carbon credits are deposited into per-class vaults and back the kVCM token; kVCM, K2 and Aerodrome LP tokens are staked and allocated to carbon classes; an on-chain reward engine settles daily yields; staked incentives can be retired against real carbon.

This repository mirrors the contracts deployed on Base mainnet. Each commit is one protocol release; see [CHANGELOG.md](CHANGELOG.md) and the GitHub Releases for what changed, with deployment and multisig transactions.

## Architecture

- **Three EIP-2535 diamonds**: [StakingManager](src/diamonds/StakingManager.sol) (locks, stakes, class allocations), [RewardManager](src/diamonds/RewardManager.sol) (daily yield engine), [AssetManager](src/diamonds/AssetManager.sol) (quotes, carbon swaps, rate limiting)
- **Carbon layer**: [CarbonLedger](src/contracts/CarbonLedger.sol), [CarbonVaultFactory](src/contracts/CarbonVaultFactory.sol), per-class [CarbonClassVaults](src/contracts/CarbonClassVault.sol) with embedded coupons, [MaturityManager](src/contracts/MaturityManager.sol)
- **Tokens & periphery**: [kVCM](src/contracts/tokens/KVCM.sol), [K2](src/contracts/tokens/K2.sol), [KvcmLockNFT](src/contracts/tokens/KvcmLockNFT.sol), ProtocolMinter, ProtocolRewardsEscrow, ProtocolSupplyOracle, ProtocolAccessManager

## Deployments

Every live address on Base (chain 8453) is in [`protocol-config/8453/`](protocol-config/8453/): protocol contracts and diamond facets in `protocol-config.toml`, per-class vaults and quoters in `classes/`. Each release's deployment and multisig transactions are recorded in `protocol-config/8453/releases/`.

## Build

Prerequisites: [Foundry](https://getfoundry.sh/).

```bash
git clone --recurse-submodules <this repo> && cd <this repo>
forge build
```

The compiler settings in `foundry.toml` (solc 0.8.28, `via_ir`, 700 optimizer runs) match the verified contracts on Basescan.

## Versioning

[`protocol-config/versions.json`](protocol-config/versions.json) holds the protocol version (the release tag) and a version per upgradeable contract and diamond. Diamonds are versioned as a whole, not per facet.

The protocol version follows these rules, which differ from plain semver:

- **Major**: a fundamental change to the protocol architecture or model, or a core entrypoint address (diamond or proxy) added, removed or changed.
- **Minor**: a breaking change to the external integration API, or a change to existing workflows.
- **Patch**: anything else.

A breaking change to a single contract does not by itself mean a major protocol release.

## License

MIT, see [LICENSE](LICENSE). The diamond core (LibDiamond, DiamondCut/Loupe) is derived from Nick Mudge's MIT-licensed [EIP-2535 reference implementation](https://github.com/mudgen/diamond-3-hardhat); its notice is in LICENSE.
