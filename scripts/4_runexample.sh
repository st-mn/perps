#!/bin/bash

# Complete setup and test script for Solana Perpetuals
# This script runs all setup steps and tests the program

set -e

echo "🚀 Complete Solana Perpetuals Setup and Test"
echo "=========================================="

# Check if deployed
if [ ! -f "example/program_id.txt" ]; then
    echo "❌ Program not deployed. Run ./scripts/3_deploy.sh devnet first."
    exit 1
fi

PROGRAM_ID=$(cat example/program_id.txt)
echo "✅ Program deployed: $PROGRAM_ID"

# Check balance
BALANCE=$(solana balance | awk '{print $1}')
echo "💰 Current balance: $BALANCE SOL"

REQUIRED_SOL=0.02
if (( $(echo "$BALANCE < $REQUIRED_SOL" | bc -l) )); then
    echo "❌ Insufficient SOL. Need at least $REQUIRED_SOL SOL."
    echo "💡 Get SOL from: https://solfaucet.com"
    echo ""
    echo "Then run this script again."
    exit 1
fi

# Setup token accounts
echo ""
echo "1️⃣ Setting up token accounts..."
if [ ! -f "example/token_accounts.txt" ]; then
    # Devnet token mints
    USDC_MINT="EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"  # Devnet USDC
    USDT_MINT="Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"  # Devnet USDT

    echo "🪙 Creating USDC token account..."
    USDC_ACCOUNT=$(spl-token create-account $USDC_MINT --owner ~/.config/solana/id.json | grep "Creating account" | awk '{print $3}')
    echo "✅ USDC Account: $USDC_ACCOUNT"

    echo "🪙 Creating USDT token account..."
    USDT_ACCOUNT=$(spl-token create-account $USDT_MINT --owner ~/.config/solana/id.json | grep "Creating account" | awk '{print $3}')
    echo "✅ USDT Account: $USDT_ACCOUNT"

    # Save token accounts
    echo "USDC=$USDC_ACCOUNT" > example/token_accounts.txt
    echo "USDT=$USDT_ACCOUNT" >> example/token_accounts.txt

    echo "💾 Token accounts saved to example/token_accounts.txt"

    # Airdrop some test tokens (if available)
    echo "🪙 Airdropping test USDC..."
    spl-token mint $USDC_MINT 1000000 $USDC_ACCOUNT 2>/dev/null || echo "⚠️  USDC airdrop failed (may not be available)"

    echo "🪙 Airdropping test USDT..."
    spl-token mint $USDT_MINT 1000000 $USDT_ACCOUNT 2>/dev/null || echo "⚠️  USDT airdrop failed (may not be available)"
else
    echo "✅ Token accounts already exist"
fi

# Load token accounts
source example/token_accounts.txt
echo "🪙 USDC: $USDC"
echo "🪙 USDT: $USDT"

# Initialize market
echo ""
echo "2️⃣ Initializing market state..."
echo "📊 Checking market state..."
MARKET_STATE_EXISTS=$(solana account $PROGRAM_ID --output json 2>/dev/null | jq -r '.account.owner' 2>/dev/null || echo "none")

if [ "$MARKET_STATE_EXISTS" != "none" ]; then
    echo "✅ Market state already exists!"
    echo "🎯 Market is ready for trading."
else
    echo "🏛️  Market state not found. Initializing market by opening first position..."

    # Use Python client to initialize market
    python3 -c "
import asyncio
import sys
import os
sys.path.append('example')

from client import PerpetualsClient
from solders.keypair import Keypair
from solders.pubkey import Pubkey

async def init_market():
    # Load keypair
    payer = Keypair()
    print(f'🔑 Wallet: {payer.pubkey()}')

    # Load token accounts
    with open('example/token_accounts.txt', 'r') as f:
        lines = f.readlines()
        usdc_account = None
        for line in lines:
            if line.startswith('USDC='):
                usdc_account = line.split('=')[1].strip()
                break

    if not usdc_account:
        print('❌ USDC account not found')
        return

    print(f'🪙 Using USDC account: {usdc_account}')

    # Create client
    client = PerpetualsClient('https://api.devnet.solana.com', payer, '$PROGRAM_ID')

    try:
        # Open a tiny position to initialize market (0.000001 base, 1000 collateral, price 50000)
        # This will create the market state account
        tx = await client.open_position(
            base_delta=1000,  # 0.000001 base (1e9 precision)
            collateral_delta=1000000,  # 1 USDC (6 decimals)
            entry_price=50000000000,  # \$50,000 (1e9 precision)
            user_token_account=Pubkey(usdc_account)
        )
        print(f'✅ Market initialized! TX: {tx}')

        # Close the position immediately to clean up
        tx2 = await client.close_position()
        print(f'✅ Position closed! TX: {tx2}')

    except Exception as e:
        print(f'❌ Error: {e}')
    finally:
        await client.close()

asyncio.run(init_market())
"

    echo "✅ Market initialization complete!"
    echo "🎯 The market is now ready for trading."
fi

# Test the program
echo ""
echo "3️⃣ Testing program functionality..."
cd example
source venv/bin/activate
echo "Running client demo and tests..."
python client.py
cd ..

echo ""
echo "✅ Setup and testing complete!"
echo ""
echo "🎯 Your perpetuals program is ready!"
echo ""
echo "📚 Next steps:"
echo "   1. Run the client demo: cd example && python client.py"
echo "   2. Update USER_TOKEN_ACCOUNT with your USDC token account"
echo "   3. Run through the tutorial cells to test trading"
echo ""
echo "📄 Your accounts:"
echo "   Program ID: $PROGRAM_ID"
echo "   USDC Account: $USDC"
echo "   USDT Account: $USDT"