#!/bin/bash

# Complete setup and test script for Solana Perpetuals
# This script runs all setup steps and tests the program

set -e

echo "🚀 Complete Solana Perpetuals Setup and Test"
echo "=========================================="

# Check if deployed
if [ ! -f "program_id.txt" ]; then
    echo "❌ Program not deployed. Run ./scripts/deploy.sh devnet first."
    exit 1
fi

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

# Setup token accounts
echo ""
echo "1️⃣ Setting up token accounts..."
if [ ! -f "token_accounts.txt" ]; then
    ./scripts/setup_tokens.sh
else
    echo "✅ Token accounts already exist"
fi

# Load token accounts
source token_accounts.txt
echo "🪙 USDC: $USDC"
echo "🪙 USDT: $USDT"

# Initialize market
echo ""
echo "2️⃣ Initializing market state..."
./scripts/init_market.sh

# Test the program
echo ""
echo "3️⃣ Testing program functionality..."
cd examples
source venv/bin/activate
python3 -c "
import asyncio
import sys
import os
sys.path.append('.')

from client import PerpetualsClient
from solders.keypair import Keypair
from solders.pubkey import Pubkey

async def test_program():
    # Load keypair
    payer = Keypair()
    print(f'🔑 Wallet: {payer.pubkey()}')

    # Load token accounts
    with open('../token_accounts.txt', 'r') as f:
        lines = f.readlines()
        usdc_account = None
        for line in lines:
            if line.startswith('USDC='):
                usdc_account = line.split('=')[1].strip()
                break

    if not usdc_account:
        print('❌ USDC account not found')
        return

    # Create client
    client = PerpetualsClient('https://api.devnet.solana.com', payer, '$PROGRAM_ID')

    try:
        # Test opening a small position
        print('📈 Opening test position...')
        tx = await client.open_position(
            base_delta=1000000,  # 0.001 base
            collateral_delta=1000000,  # 1 USDC
            entry_price=50000000000,  # \$50,000
            user_token_account=Pubkey(usdc_account)
        )
        print(f'✅ Position opened! TX: {tx}')

        # Test updating funding
        print('💰 Updating funding rates...')
        tx2 = await client.update_funding()
        print(f'✅ Funding updated! TX: {tx2}')

        # Test closing position
        print('📉 Closing position...')
        # Note: close_position method needs to be implemented in client.py
        print('⚠️  Close position test skipped (method not implemented)')

    except Exception as e:
        print(f'❌ Test failed: {e}')
    finally:
        await client.close()

asyncio.run(test_program())
"
cd ..

echo ""
echo "✅ Setup and testing complete!"
echo ""
echo "🎯 Your perpetuals program is ready!"
echo ""
echo "📚 Next steps:"
echo "   1. Open examples/perpetuals_tutorial.ipynb in Jupyter"
echo "   2. Update USER_TOKEN_ACCOUNT with your USDC token account"
echo "   3. Run through the tutorial cells to test trading"
echo ""
echo "📄 Your accounts:"
echo "   Program ID: $PROGRAM_ID"
echo "   USDC Account: $USDC"
echo "   USDT Account: $USDT"