#!/bin/bash

# Setup script for Solana Perpetuals
# Creates token accounts and initializes market state

set -e

echo "🚀 Setting up Solana Perpetuals..."

# Check balance
BALANCE=$(solana balance | awk '{print $1}')
echo "💰 Current balance: $BALANCE SOL"

REQUIRED_SOL=0.01
if (( $(echo "$BALANCE < $REQUIRED_SOL" | bc -l) )); then
    echo "❌ Insufficient SOL. Need at least $REQUIRED_SOL SOL for setup."
    echo "💡 Get SOL from: https://solfaucet.com or https://faucet.solana.com"
    exit 1
fi

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
echo "USDC=$USDC_ACCOUNT" > token_accounts.txt
echo "USDT=$USDT_ACCOUNT" >> token_accounts.txt

echo "💾 Token accounts saved to token_accounts.txt"

# Airdrop some test tokens (if available)
echo "🪙 Airdropping test USDC..."
spl-token mint $USDC_MINT 1000000 $USDC_ACCOUNT 2>/dev/null || echo "⚠️  USDC airdrop failed (may not be available)"

echo "🪙 Airdropping test USDT..."
spl-token mint $USDT_MINT 1000000 $USDT_ACCOUNT 2>/dev/null || echo "⚠️  USDT airdrop failed (may not be available)"

echo "✅ Setup complete!"
echo "📄 Token accounts:"
echo "   USDC: $USDC_ACCOUNT"
echo "   USDT: $USDT_ACCOUNT"
echo ""
echo "🎯 Next: Run ./scripts/init_market.sh to initialize market state"