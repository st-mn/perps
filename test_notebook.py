#!/usr/bin/env python3
"""
Simple test script to verify the notebook functionality works
"""

import asyncio
import sys
import os

# Add the examples directory to Python path to import our client
sys.path.append(os.path.join(os.getcwd(), 'examples'))

from client import (
    PerpetualsClient,
    PositionMonitor,
    price_to_program,
    price_from_program,
    size_to_program,
    size_from_program
)
from solders.keypair import Keypair
from solders.pubkey import Pubkey

async def test_notebook_functionality():
    print("🧪 Testing notebook functionality...")

    # Configuration
    RPC_URL = "https://api.devnet.solana.com"
    
    # Load program ID dynamically from deployment file
    try:
        with open("program_id.txt", "r") as f:
            PROGRAM_ID = f.read().strip()
        print(f"✅ Loaded program ID from file: {PROGRAM_ID}")
    except FileNotFoundError:
        PROGRAM_ID = "YOUR_PROGRAM_ID_HERE"  # Fallback if file doesn't exist
        print(f"⚠️  program_id.txt not found, using fallback: {PROGRAM_ID}")

    # Generate a keypair for testing
    payer = Keypair()
    print(f"🔑 Wallet: {payer.pubkey()}")

    # Initialize the client
    client = PerpetualsClient(RPC_URL, payer, PROGRAM_ID)

    # Test PDA generation
    vault_pda, vault_bump = client.get_program_authority()
    position_pda, pos_bump = client.get_position_address(payer.pubkey())
    market_pda, market_bump = client.get_market_state_address()

    print(f"🏦 Vault PDA: {vault_pda} (bump: {vault_bump})")
    print(f"👤 Position PDA: {position_pda} (bump: {pos_bump})")
    print(f"📊 Market PDA: {market_pda} (bump: {market_bump})")

    # Test price conversions
    prices = [100.0, 100.50, 99.99, 0.01, 1000.0]
    print("\nPrice Conversion Tests:")
    print("Human Price → Program → Human")
    print("-" * 35)

    for price in prices:
        program_price = price_to_program(price)
        converted_back = price_from_program(program_price)
        print(f"${price:>8.2f} → {program_price:>12} → ${converted_back:>8.2f}")

    # Test size conversions
    sizes = [1.0, 0.5, 10.0, 0.001]
    print("\nSize Conversion Tests:")
    print("Human Size → Program → Human")
    print("-" * 32)

    for size in sizes:
        program_size = size_to_program(size)
        converted_back = size_from_program(program_size)
        print(f"{size:>8.3f} → {program_size:>12} → {converted_back:>8.3f}")

    # Test market state query (may fail if not initialized)
    print("\n📊 Testing market state query...")
    try:
        market_state = await client.get_market_state()
        if market_state:
            print("✅ Market state found!")
            print(f"   Funding Index: {market_state.funding_index:,}")
            print(f"   Mark Price: ${price_from_program(market_state.mark_price):.2f}")
        else:
            print("⚠️  Market state not found (program may not be initialized)")
    except Exception as e:
        print(f"❌ Market state query failed: {e}")

    # Test position query
    print("\n👤 Testing position query...")
    try:
        position = await client.get_position(payer.pubkey())
        if position:
            print("✅ Position found!")
            print(f"   Size: {size_from_program(position.base_amount):.4f}")
            print(f"   Collateral: ${price_from_program(position.collateral):.2f}")
        else:
            print("ℹ️  No position found for this wallet")
    except Exception as e:
        print(f"❌ Position query failed: {e}")

    # Clean up
    await client.close()
    print("\n✅ Test completed successfully!")

if __name__ == "__main__":
    asyncio.run(test_notebook_functionality())