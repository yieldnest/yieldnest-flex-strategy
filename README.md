# Yieldnest Flex Strategy


The Yieldnest Flex Strategy is a flexible yield strategy implementation that enables:

- Deposits and withdrawals of base assets
- Accounting of rewards and losses through a dedicated accounting module

Key features:

- Flexible accounting system that tracks total assets and share price
- Configurable target APY and slashing percentage
- Rewards accrual mechanism with cooldown periods

The strategy is designed to be modular and extensible, allowing for different yield strategies  while maintaining a consistent accounting and security model.

Architecture:

- FlexStrategy: Core strategy contract handling deposits/withdrawals and accounting
- AccountingModule: Manages reward/loss processing and share price calculations  
- AccountingToken: ERC20 token that stands as an IOU for the underlying asset.
- RewardsSweeper: Peripheral. Handles automated reward collection and processing
- FixedRateProvider: Provides APY target rates for the strategy


## Deployment

Before running the script, ensure appropriate variables are set in
`script\DeployFlexStrategy.s.sol:assignDeploymentParameters()`

```
# deploy strategy
forge script DeployFlexStrategy --rpc-url <MAINNET_RPC_URL>  --slow --broadcast --account <CAST_WALLET_ACCOUNT>  --sender <SENDER_ADDRESS>  --verify --etherscan-api-key <ETHERSCAN_API_KEY>  -vvv

# verify deployment
forge script VerifyFlexStrategy --rpc-url <MAINNET_RPC_URL>
```
