#!/bin/bash

# Solana Devnet Faucet Script
# Tries multiple sources to obtain test SOL

set -e

echo ""
echo "================================GETSOL================================"
echo ""


WALLET_ADDRESS=${1:-"$(solana address)"}
AMOUNT=${2:-1}

echo "🚰 Solana Devnet Faucet Script"
echo "📧 Wallet: $WALLET_ADDRESS"
echo "💰 Amount: $AMOUNT SOL"
echo ""

# Function to check balance
check_balance() {
    echo "💳 Checking balance..."
    BALANCE=$(solana balance --commitment confirmed | awk '{print $1}')
    echo "💰 Current balance: $BALANCE SOL"
    echo ""
}

# Function to try airdrop with specific RPC
try_airdrop() {
    local rpc_url=$1
    local name=$2

    echo "🔄 Trying $name ($rpc_url)..."

    # Configure RPC
    solana config set --url "$rpc_url" > /dev/null 2>&1

    # Try airdrop
    if solana airdrop $AMOUNT --commitment confirmed 2>/dev/null; then
        echo "✅ Success with $name!"
        check_balance
        return 0
    else
        echo "❌ Failed with $name"
        return 1
    fi
}

# Function to try direct API call
try_api_airdrop() {
    local rpc_url=$1
    local name=$2

    echo "🔄 Trying $name API ($rpc_url)..."

    # Direct API call
    response=$(curl -s -X POST -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"requestAirdrop\",\"params\":[\"$WALLET_ADDRESS\", ${AMOUNT}000000000]}" \
        "$rpc_url")

    if echo "$response" | grep -q '"result"'; then
        echo "✅ Success with $name API!"
        sleep 2
        check_balance
        return 0
    else
        echo "❌ Failed with $name API: $(echo "$response" | jq -r '.error.message // "Unknown error"')"
        return 1
    fi
}

echo "🏦 Starting faucet attempts..."
echo ""

# Initial balance check
check_balance

# Try official Solana faucet first
if try_airdrop "https://api.devnet.solana.com" "Official Solana Faucet"; then
    echo "🎉 Got SOL from official faucet!"
    exit 0
fi

# Try different RPC endpoints
RPC_ENDPOINTS=(
    "https://devnet.solana.com:Official Solana (alt)"
    "https://api.devnet-beta.solana.com:Devnet Beta"
    "https://solana-api.projectserum.com:Project Serum"
    "https://rpc.ankr.com/solana_devnet:Ankr (may require API key)"
    "https://solana-devnet-rpc.allthatnode.com:All That Node"
    "https://devnet-rpc.shyft.to:Shyft (may require API key)"
    "https://solana-devnet.g.alchemy.com/v2/demo:Alchemy Demo"
)

for endpoint in "${RPC_ENDPOINTS[@]}"; do
    IFS=':' read -r url name <<< "$endpoint"
    if try_airdrop "$url" "$name"; then
        echo "🎉 Got SOL from $name!"
        exit 0
    fi
    sleep 1
done

# Try API calls for endpoints that support them
API_ENDPOINTS=(
    "https://api.devnet.solana.com:Official API"
)

for endpoint in "${API_ENDPOINTS[@]}"; do
    IFS=':' read -r url name <<< "$endpoint"
    if try_api_airdrop "$url" "$name"; then
        echo "🎉 Got SOL from $name!"
        exit 0
    fi
    sleep 1
done

# Try community faucets (if they have APIs)
echo "🔄 Trying community faucets..."

# SolFaucet API attempt (if available) - silent
# Note: SolFaucet requires manual interaction, but let's try if they have an API
curl -s "https://solfaucet.com/api/airdrop" \
    -H "Content-Type: application/json" \
    -d "{\"address\":\"$WALLET_ADDRESS\",\"amount\":$AMOUNT}" >/dev/null 2>&1 || true

# Try smaller amounts
echo ""
echo "🔄 Trying smaller amounts..."
for small_amount in 0.5 0.1 0.05; do
    echo "🔄 Trying $small_amount SOL..."
    if solana airdrop $small_amount --commitment confirmed 2>/dev/null; then
        echo "✅ Got $small_amount SOL!"
        check_balance
        break
    fi
    sleep 1
done

# Final balance check
echo ""
echo "📊 Final balance check:"
check_balance

echo ""
echo "💡 Faucet attempts completed."
echo ""
echo "📋 If all faucets failed, try:"
echo "   1. Wait 8+ hours for official faucet reset"
echo "   2. Use https://faucet.solana.com manually"
echo "   3. Try https://solfaucet.com manually"
echo "   4. Ask in Solana Discord communities"
echo "   5. Use a different wallet with existing devnet SOL"
echo ""
echo "🎯 Once you have SOL, deploy with:"
echo "   ./scripts/3_deploy.sh devnet"