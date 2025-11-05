#!/bin/bash

# Initialize market state for Solana Perpetuals
# This opens the first position which initializes the market state

set -e

echo "🏛️  Initializing Solana Perpetuals Market State..."

# Check if program_id.txt exists
if [ ! -f "program_id.txt" ]; then
    echo "❌ program_id.txt not found. Run ./scripts/deploy.sh first."
    exit 1
fi

PROGRAM_ID=$(cat program_id.txt)
echo "🆔 Program ID: $PROGRAM_ID"

# Check if token_accounts.txt exists
if [ ! -f "token_accounts.txt" ]; then
    echo "❌ token_accounts.txt not found. Run ./scripts/setup_tokens.sh first."
    exit 1
fi

# Load token accounts
source token_accounts.txt
echo "🪙 USDC Account: $USDC"
echo "🪙 USDT Account: $USDT"

# Check balance
BALANCE=$(solana balance | awk '{print $1}')
echo "💰 Current balance: $BALANCE SOL"

REQUIRED_SOL=0.01
if (( $(echo "$BALANCE < $REQUIRED_SOL" | bc -l) )); then
    echo "❌ Insufficient SOL. Need at least $REQUIRED_SOL SOL for market initialization."
    exit 1
fi

echo "📊 Checking market state..."
MARKET_STATE_EXISTS=$(solana account $PROGRAM_ID --output json 2>/dev/null | jq -r '.account.owner' 2>/dev/null || echo "none")

if [ "$MARKET_STATE_EXISTS" != "none" ]; then
    echo "✅ Market state already exists!"
    echo "🎯 Market is ready for trading."
    exit 0
fi

echo "🏛️  Market state not found. Initializing market by opening first position..."

# Use Python client to initialize market
python3 -c "
import asyncio
import sys
import os
sys.path.append('examples')

from client import PerpetualsClient
from solana.keypair import Keypair
from solana.publickey import PublicKey

async def init_market():
    # Load keypair
    payer = Keypair.from_secret_key_file('~/.config/solana/id.json')
    print(f'🔑 Wallet: {payer.public_key}')

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
    client = PerpetualsClient('https://api.devnet.solana.com', payer, '$PROGRAM_ID')

    try:
        # Open a tiny position to initialize market (0.000001 base, 1000 collateral, price 50000)
        # This will create the market state account
        tx = await client.open_position(
            base_delta=1000,  # 0.000001 base (1e9 precision)
            collateral_delta=1000000,  # 1 USDC (6 decimals)
            entry_price=50000000000,  # \$50,000 (1e9 precision)
            user_token_account=PublicKey(usdc_account)
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
echo ""
echo "📚 Next steps:"
echo "   1. Update the Jupyter notebook with your program ID and token accounts"
echo "   2. Test opening positions with the client application"