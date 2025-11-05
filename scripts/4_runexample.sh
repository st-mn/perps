#!/bin/bash

# Complete setup and test script for Solana Perpetuals
# This script runs all setup steps and tests the program

set -e

echo ""
echo "================================EXAMPLERUN================================"
echo ""

echo "🚀 Complete Solana Perpetuals Smart Contract Test and Demo"
echo "==========================================================="

# Test the program first
echo "Testing Smart Contract program client functionality..."
cd example
source venv/bin/activate
python -m pytest client.py -v --no-header


# Check if deployed
if [ ! -f "program_id.txt" ]; then
    echo "❌ Program not deployed. Run ./scripts/3_deploy.sh devnet first."
    exit 1
fi

echo ""
echo "1️⃣  Checking deployed Smart Contract program and demonstrating example usage..."
PROGRAM_ID=$(cat program_id.txt)
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


python client.py
cd ..

# Setup token accounts
echo ""
echo "2️⃣  Setting up token accounts..."
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
echo " USDC: $USDC"
echo " USDT: $USDT"

# Initialize market
echo ""
echo "3️⃣  Initializing market state..."
echo "📊 Checking market state..."
# Calculate market state PDA: find_program_address([b"market"], program_id)
MARKET_STATE_PDA="4aJnePhWkLdgaxgH5RdgPJ1AGo61Sog1jVMqKRSB46WY"
if solana account $MARKET_STATE_PDA --output json >/dev/null 2>&1; then
    echo "✅ Market state already exists!"
    echo "🎯 Market is ready for trading."
else
    echo "🏛️  Market state not found. Initializing market by opening first position..."

    # Check if USDC account has sufficient balance
    usdc_balance=$(spl-token balance "$USDC" 2>/dev/null || echo "0")
    if (( $(echo "$usdc_balance < 1" | bc -l 2>/dev/null || echo "1") )); then
        echo "⚠️  USDC token account is empty ($usdc_balance USDC). Skipping market initialization."
        echo "💡 To initialize the market please fund your USDC token account with devnet USDC."
    else
        # Use Python client to initialize market
        cd example
        source venv/bin/activate
        python3 - "$PROGRAM_ID" << 'EOF'
import asyncio
import sys
import os
sys.path.append('.')

from client import PerpetualsClient
from solders.keypair import Keypair
from solders.pubkey import Pubkey

async def init_market():
    # Load keypair
    payer = Keypair()
    print(f'🔑 Wallet: {payer.pubkey()}')

    # Load token accounts
    with open('token_accounts.txt', 'r') as f:
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
    client = PerpetualsClient('https://api.devnet.solana.com', payer, sys.argv[1])

    try:
        # Open a tiny position to initialize market (0.000001 base, 1000 collateral, price 50000)
        # This will create the market state account
        tx = await client.open_position(
            base_delta=1000,  # 0.000001 base (1e9 precision)
            collateral_delta=1000000,  # 1 USDC (6 decimals)
            entry_price=50000000000,  # \$50,000 (1e9 precision)
            user_token_account=Pubkey.from_string(usdc_account)
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
EOF
    cd ..

    echo "✅ Market initialization complete!"
    echo "🎯 The market is now ready for trading."
    fi

echo ""
echo "✅ Setup and testing complete for your Perpetuals program and accounts."
echo "📄   Program ID: $PROGRAM_ID"
echo "📄   USDC Account: $USDC"
echo "📄   USDT Account: $USDT"
fi
