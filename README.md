# Minimal Perpetuals (Perps) Program Solana Smart Contract

A **minimal educational implementation** of a perpetual futures trading program on Solana. This demonstrates the core concepts of opening positions, funding payments, and liquidations.

> ⚠️ **Not Production Ready**: This implementation is missing critical components like secure price oracles, order book matching, proper risk management, and extensive security checks. Use as a learning resource and starting point only.

## 🏗️ Architecture Overview

The program implements a simplified perpetual futures system with these key components:

- **Positions**: Long/short exposure with collateral backing
- **Funding Mechanism**: Periodic payments between longs and shorts
- **Liquidation System**: Automatic closure of undercollateralized positions
- **Market State**: Global parameters and funding rates

## 📊 Core Structures

### Position
```rust
pub struct Position {
    pub owner: Pubkey,           // Position owner
    pub base_amount: i64,        // Signed position size (+ = long, - = short)
    pub collateral: u64,         // Locked collateral in quote token
    pub last_funding_index: i64, // Last applied funding index
    pub entry_price: u64,        // Entry price (1e9 precision)
}
```

### MarketState
```rust
pub struct MarketState {
    pub funding_index: i64,          // Cumulative funding index
    pub funding_rate_per_slot: i64,  // Current funding rate
    pub open_interest: u64,          // Total position size
    pub bump: u8,                    // PDA bump
    pub last_funding_slot: u64,      // Last funding update
    pub mark_price: u64,            // Current mark price
}
```

## 🎯 Instructions

### 0. Open Position (`open_position`)
Creates or modifies a trading position.

**Parameters:**
- `base_delta: i64` - Position size change (positive = long, negative = short)
- `collateral_delta: u64` - Additional collateral to deposit
- `entry_price: u64` - Price for the position (1e9 precision)

**Accounts:**
- User (signer)
- Token program
- User's collateral token account
- Vault token account (PDA)
- Position account (PDA)
- Market state account (PDA)
- Rent sysvar
- Clock sysvar
- System program

### 1. Update Funding (`update_funding`)
Updates the global funding rate and index.

**Accounts:**
- Market state account (writable)
- Clock sysvar

### 2. Liquidate (`liquidate`)
Liquidates an undercollateralized position.

**Accounts:**
- Liquidator (signer)
- Token program
- Liquidator's token account
- Vault token account (PDA)
- Position account (writable)
- Market state account (writable)
- Clock sysvar

### 3. Close Position (`close_position`)
Voluntarily closes a position and returns collateral.

**Accounts:**
- User/owner (signer)
- Token program
- User's token account
- Vault token account (PDA)
- Position account (writable)
- Market state account (writable)

## 🚀 Quick Start

### Prerequisites

#### Windows
**⚠️ Windows MUST use WSL (Windows Subsystem for Linux) for Solana development:**

1. **Install WSL**:
   ```cmd
   # Run as Administrator in Command Prompt or PowerShell
   wsl --install
   # Reboot if prompted
   ```

2. **Setup development environment in WSL**:
   ```bash
   # Open WSL terminal and run all subsequent commands in WSL
   sudo apt update && sudo apt install curl git build-essential
   ```

4. **Use WSL for all development**:
   - Always use WSL terminal for building and deploying
   - WSL Tunnel Extension if using VS Code
   - Run `./scripts/1_build.sh` (not `scripts\build.bat`)

#### All Platforms

1. **Install Solana CLI**:
   ```bash
   # Unix/Mac/WSL
   sh -c "$(curl -sSfL https://release.solana.com/v1.18.0/install)"
   
   # Windows (Direct - NOT recommended, use WSL instead)
   # Download and run: https://release.solana.com/v1.18.0/solana-install-init-x86_64-pc-windows-msvc.exe
   ```

2. **Install Rust and Solana BPF toolchain**:
   ```bash
   rustup component add rust-src
   solana install init
   ```

3. **Create/Import Wallet**:
   ```bash
   # Create new keypair
   solana-keygen new --outfile ~/.config/solana/id.json
   
   # OR import existing (e.g., from Phantom)
   solana-keygen recover "prompt://?key=0"
   ```

### Getting Test SOL for Devnet

**Before deploying to devnet, you need test SOL. The official faucet has rate limits (2 requests per 8 hours).**

1. **Automated Faucet Script** (Recommended):
   ```bash
   # Try multiple faucets automatically
   ./scripts/2_getsol.sh [amount]  # Default: 1 SOL
   
   # Examples:
   ./scripts/2_getsol.sh           # Get 1 SOL
   ./scripts/2_getsol.sh 2         # Get 2 SOL
   ```

2. **Manual Options**:
   - **Official Faucet**: https://faucet.solana.com (rate limited)
   - **SolFaucet**: https://solfaucet.com (manual interaction required)
   - **Community Discord**: Ask in Solana communities

3. **Check Your Balance**:
   ```bash
   solana balance
   ```

### Build and Deploy

1. **Clone and Build**:
   ```bash
   cd simple_perps
   
   # Unix/Mac/WSL (recommended for all platforms)
   ./scripts/1_build.sh
   
   # Windows (Direct - use only if WSL is not available)
   scripts\build.bat
   ```

   **Note for Windows users**: Always prefer WSL environment for development.

2. **Deploy to Devnet**:
   ```bash
   # Unix/Mac/WSL (recommended for all platforms)
   ./scripts/3_deploy.sh devnet
   
   # Windows (Direct - use only if WSL is not available)
   scripts\deploy.bat devnet
   ```

3. **Deploy to Mainnet**:
   ```bash
   # Unix/Mac/WSL (ensure you have sufficient SOL!)
   ./scripts/3_deploy.sh mainnet
   
   # Windows (Direct - use only if WSL is not available)
   scripts\deploy.bat mainnet
   ```

## 💰 Economic Model

### Funding Mechanism
- **Base Rate**: 0.01% per slot
- **Rate Adjustment**: Higher rates for increased open interest
- **Payment Direction**: Longs pay shorts when funding is positive (and vice versa)
- **Frequency**: Updated every slot (programmable)

### Collateral Requirements
- **Minimum Ratio**: 150% (1.5x leverage)
- **Liquidation Threshold**: Below 150% collateral ratio
- **Liquidation Penalty**: 10% of collateral to liquidator

### Price Precision
- All prices use 1e9 (1 billion) precision
- Example: $100.50 = 100,500,000,000

## 🔒 Security Considerations

This is an **educational implementation** with several important limitations:

### Missing Production Features
- [ ] **Oracle Integration**: Uses manual price updates instead of secure oracles
- [ ] **Order Book**: No matching engine or limit orders
- [ ] **Risk Management**: Minimal position sizing and exposure limits
- [ ] **Multi-Asset**: Single market only
- [ ] **Governance**: No parameter updates or emergency controls
- [ ] **Insurance Fund**: No backstop for bad debt
- [ ] **Circuit Breakers**: No halt mechanisms for extreme volatility

### Known Vulnerabilities
- **Price Manipulation**: Mark price can be set arbitrarily
- **Front-Running**: No MEV protection
- **Flash Loan Attacks**: Insufficient oracle and validation
- **Precision Errors**: Basic integer arithmetic without comprehensive overflow checks

## 🧪 Testing Strategy

### Unit Tests
```bash
cargo test
```

### Integration Testing
1. **Position Lifecycle**:
   - Open long position with collateral
   - Apply funding updates
   - Close position and verify PnL

2. **Liquidation Testing**:
   - Create undercollateralized position
   - Trigger liquidation
   - Verify penalty distribution

3. **Funding Mechanics**:
   - Multiple positions with different funding indices
   - Verify cumulative funding calculations

### Devnet Testing
```bash
# Fund test wallet
solana airdrop 2

# Deploy program
./scripts/3_deploy.sh devnet

# Test with client integration
```

## 📁 Project Structure

```
simple_perps/
├── src/
│   └── lib.rs              # Main program logic
├── scripts/
│   ├── 1_build.sh         # Unix build script (includes env setup)
│   ├── build.bat          # Windows build script
│   ├── 2_getsol.sh        # Get SOL from faucet
│   ├── 3_deploy.sh         # Unix deployment script
│   ├── deploy.bat         # Windows deployment script
│   ├── 4_runexample.sh    # Run example and setup
├── Cargo.toml             # Rust dependencies
└── README.md              # This file
```

## 🔗 Client Integration

### Position Management
```typescript
// Pseudo-code for client integration
const position = await openPosition({
  baseDelta: 1_000_000_000,    // 1 unit long
  collateralDelta: 150_000_000_000, // 150 USDC
  entryPrice: 100_500_000_000,  // $100.50
});
```

### Funding Updates
```typescript
// Should be called periodically (every slot or less frequent)
await updateFunding();
```

### Liquidation Monitoring
```typescript
// Monitor positions for liquidation opportunities
const positions = await getUndercollateralizedPositions();
for (const position of positions) {
  await liquidatePosition(position);
}
```

## 🛣️ Roadmap for Production

To make this production-ready, you would need:

1. **Oracle Integration**: Pyth, Switchboard, or custom oracle network
2. **Order Book**: Matching engine with limit/market orders
3. **Risk Engine**: Position limits, leverage caps, circuit breakers
4. **Multi-Asset Support**: Cross-margin, portfolio risk
5. **Governance**: DAO controls for parameters
6. **Insurance Fund**: Bad debt coverage
7. **MEV Protection**: Commit-reveal schemes or other mechanisms
8. **Audit**: Comprehensive security audit
9. **Emergency Controls**: Pause/upgrade mechanisms
10. **Advanced Features**: Stop losses, take profits, advanced order types

## 📚 References

- [Solana Program Library](https://spl.solana.com/)
- [Anchor Framework](https://anchor-lang.com/) (for easier development)
- [Perpetual Protocol Whitepaper](https://perp.com/)
- [dYdX Perpetuals](https://docs.dydx.exchange/)
- [Mango Markets](https://docs.mango.markets/)

## ⚖️ License

MIT License - See LICENSE file for details.

## 🤝 Contributing

This is an educational project. Contributions welcome for:
- Bug fixes in the learning implementation
- Additional documentation
- Test coverage improvements
- Client integration examples

**Not suitable for production use without significant additional development and security auditing.**
