#!/bin/bash

# Solana Perpetuals Program Deployment Script
# This script deploys the built program to Solana

set -e

echo ""
echo "================================DEPLOY================================"
echo ""

NETWORK=${1:-devnet}
KEYPAIR_PATH=${2:-~/.config/solana/id.json}

echo "🚀 Deploying Solana Perpetuals Program to $NETWORK..."

# Check if program is built
if [ ! -f "target/deploy/simple_perps.so" ]; then
    echo "❌ Program not built. Run ./scripts/1_build.sh first."
    exit 1
fi

# Check if keypair exists
if [ ! -f "$KEYPAIR_PATH" ]; then
    echo "❌ Keypair not found at $KEYPAIR_PATH"
    echo "💡 Create a keypair with: solana-keygen new --outfile $KEYPAIR_PATH"
    exit 1
fi

# Set Solana config
echo "⚙️  Configuring Solana CLI..."
solana config set --keypair "$KEYPAIR_PATH"

case $NETWORK in
    "devnet")
        solana config set --url https://api.devnet.solana.com
        echo "💰 Airdropping SOL for deployment (devnet only)..."
        solana airdrop 2 --commitment finalized || echo "⚠️  Airdrop may have failed, continuing..."
        ;;
    "testnet")
        solana config set --url https://api.testnet.solana.com
        ;;
    "mainnet")
        solana config set --url https://api.mainnet-beta.solana.com
        echo "⚠️  DEPLOYING TO MAINNET! Make sure you have enough SOL for deployment."
        ;;
    *)
        echo "❌ Invalid network: $NETWORK. Use 'devnet', 'testnet', or 'mainnet'"
        exit 1
        ;;
esac

# Check balance
BALANCE=$(solana balance --commitment finalized | awk '{print $1}')
echo "💳 Wallet balance: $BALANCE SOL"

if (( $(echo "$BALANCE < 0.1" | bc -l) )); then
    echo "⚠️  Warning: Balance is low. You may need more SOL for deployment."
    if [ "$NETWORK" = "devnet" ]; then
        echo "💡 Run: solana airdrop 2"
    fi
fi

# Deploy the program
echo "📤 Deploying program..."
PROGRAM_ID=$(solana program deploy target/deploy/simple_perps.so --commitment finalized --output json | jq -r '.programId')

if [ "$PROGRAM_ID" != "null" ] && [ -n "$PROGRAM_ID" ]; then
    echo "✅ Deployment successful!"
    echo "🆔 Program ID: $PROGRAM_ID"
    echo "🌐 Network: $NETWORK"
    
    # Save program ID to file
    echo "$PROGRAM_ID" > example/program_id.txt
    echo "💾 Program ID saved to example/program_id.txt"
    
    # Show program info
    echo ""
    echo "📊 Program Info:"
    solana program show "$PROGRAM_ID" --commitment finalized
    
    echo ""
    echo "🎉 Your perpetuals program is now live!"
    echo "📚 Next steps:"
    echo "   1. Create token accounts for collateral (USDC/USDT)"
    echo "   2. Initialize market state and positions"
    echo "   3. Test opening positions with your client application"
else
    echo "❌ Deployment failed!"
    exit 1
fi