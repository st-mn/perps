# Python Client Setup Guide

This directory contains Python examples for interacting with the Simple Perpetuals Solana program.

## 📦 Installation

### 1. Create Virtual Environment (Recommended)

```bash
# Create virtual environment
python -m venv venv

# Activate virtual environment
# Windows:
venv\Scripts\activate
# Unix/Mac:
source venv/bin/activate
```

### 2. Install Dependencies

```bash
# Install required packages
pip install -r requirements.txt

# Or install manually:
pip install solana solders spl-token borsh-construct httpx
```

## 🚀 Quick Start

### 1. Update Configuration

The client automatically loads the program ID from `../program_id.txt` (created during deployment). If the file doesn't exist, it falls back to a placeholder.

For the Jupyter notebook, the program ID is loaded automatically from the deployment file.

### 2. Create Token Accounts

You'll need a USDC token account for collateral:
```bash
# Create USDC token account (devnet)
spl-token create-account EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v

# Get some devnet USDC (if available)
# Or use a devnet USDC faucet
```

### 3. Run Examples

```bash
# Run the main example
python client.py

# Run tests
python test_client.py

# Or with pytest (if installed)
pytest test_client.py -v
```

## 📋 Files Overview

- **`client.py`** - Main Python client implementation
- **`test_client.py`** - Unit and integration tests
- **`requirements.txt`** - Python package dependencies
- **`package.json`** - TypeScript client dependencies (for comparison)
- **`client.ts`** - TypeScript client implementation

## 🔧 Client Features

### PerpetualsClient Class
- **Connection Management**: Async RPC client with proper cleanup
- **Position Operations**: Open, modify, and close positions
- **Funding Updates**: Periodic funding rate calculations
- **Liquidations**: Liquidate undercollateralized positions
- **Data Queries**: Get position and market state information

### Utility Functions
- **Price Conversion**: Human-readable ↔ Program format (1e9 precision)
- **Size Conversion**: Position sizes with proper scaling
- **Health Calculations**: Real-time collateral ratio monitoring
- **PnL Calculations**: Unrealized profit/loss tracking

### PositionMonitor Class
- **Liquidation Monitoring**: Scan for liquidation opportunities
- **Position Summaries**: Comprehensive position analytics
- **Health Tracking**: Real-time risk assessment

## 📊 Usage Examples

### Basic Position Management

```python
import asyncio
from solana.keypair import Keypair
from solana.publickey import PublicKey
from client import PerpetualsClient, price_to_program

async def example():
    # Initialize client
    payer = Keypair()  # Load your keypair
    client = PerpetualsClient(
        "https://api.devnet.solana.com",
        payer,
        "YOUR_PROGRAM_ID"
    )
    
    try:
        # Open a long position
        tx_id = await client.open_position(
            base_delta=price_to_program(1.0),      # 1 unit long
            collateral_delta=price_to_program(150), # 150 USDC
            entry_price=price_to_program(100.50),   # $100.50
            user_token_account=PublicKey("YOUR_TOKEN_ACCOUNT")
        )
        print(f"Position opened: {tx_id}")
        
        # Check position
        position = await client.get_position(payer.public_key)
        if position:
            print(f"Position size: {position.base_amount / 1e9}")
            print(f"Collateral: {position.collateral / 1e9}")
    
    finally:
        await client.close()

# Run example
asyncio.run(example())
```

### Liquidation Bot Example

```python
from client import PerpetualsClient, PositionMonitor

async def liquidation_bot():
    client = PerpetualsClient(rpc_url, payer, program_id)
    monitor = PositionMonitor(client)
    
    # List of users to monitor
    users_to_monitor = [
        PublicKey("user1..."),
        PublicKey("user2..."),
        # ... more users
    ]
    
    while True:
        # Check for liquidation opportunities
        liquidatable = await monitor.monitor_liquidations(users_to_monitor)
        
        for user in liquidatable:
            try:
                tx_id = await client.liquidate(user, liquidator_token_account)
                print(f"Liquidated {user}: {tx_id}")
            except Exception as e:
                print(f"Failed to liquidate {user}: {e}")
        
        # Wait before next check
        await asyncio.sleep(10)
```

## 🧪 Testing

### Unit Tests
```bash
python test_client.py
```

Tests cover:
- Price conversion utilities
- PDA generation consistency
- Data serialization/deserialization
- Error handling

### Integration Tests

For integration testing with a real program:

1. Deploy the program to devnet
2. Update `TEST_PROGRAM_ID` in `test_client.py`
3. Create and fund token accounts
4. Run full integration tests

## ⚠️ Security Notes

This is an **educational implementation**. For production use:

- ✅ Use hardware wallets or secure key management
- ✅ Implement proper error handling and retries
- ✅ Add transaction confirmation checks
- ✅ Validate all inputs and responses
- ✅ Use secure RPC endpoints
- ✅ Implement rate limiting for API calls
- ✅ Add comprehensive logging
- ✅ Test thoroughly on devnet before mainnet

## 🔗 Additional Resources

- [Solana Python Documentation](https://solana-py.readthedocs.io/)
- [SPL Token Python](https://spl-token-py.readthedocs.io/)
- [Solana Web3.js](https://solana-labs.github.io/solana-web3.js/) (for TypeScript comparison)
- [Borsh Serialization](https://borsh.io/)

## 🐛 Troubleshooting

### Common Issues

1. **Import Errors**
   ```
   ModuleNotFoundError: No module named 'solana'
   ```
   Solution: Install dependencies with `pip install -r requirements.txt`

2. **RPC Connection Issues**
   ```
   ConnectionError: Unable to connect to RPC
   ```
   Solution: Check internet connection and RPC endpoint

3. **Invalid Program ID**
   ```
   ProgramError: Invalid program ID
   ```
   Solution: Ensure program is deployed and ID is correct

4. **Insufficient Balance**
   ```
   InsufficientFundsError
   ```
   Solution: Fund wallet with devnet SOL using `solana airdrop`

### Getting Help

- Check the main README.md for program documentation
- Review the Rust implementation in `src/lib.rs`
- Compare with TypeScript client in `client.ts`
- Join Solana Discord for community support