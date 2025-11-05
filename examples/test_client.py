#!/usr/bin/env python3
"""
Test script for Solana Perpetuals Python Client

This script demonstrates basic testing patterns for the perpetuals client
and can be used as a reference for integration tests.
"""

import asyncio
import pytest
from solders.keypair import Keypair
from solders.pubkey import Pubkey
from client import PerpetualsClient, Position, MarketState, price_to_program, price_from_program

# Test configuration
TEST_RPC_URL = "https://api.devnet.solana.com"
TEST_PROGRAM_ID = "11111111111111111111111111111111"  # Placeholder

class TestPerpetualsClient:
    """Test cases for the Perpetuals client"""
    
    @pytest.fixture
    async def client(self):
        """Create a test client"""
        payer = Keypair()
        client = PerpetualsClient(TEST_RPC_URL, payer, TEST_PROGRAM_ID)
        yield client
        await client.close()
    
    def test_price_conversion(self):
        """Test price conversion utilities"""
        # Test whole numbers
        assert price_to_program(100.0) == 100_000_000_000
        assert price_from_program(100_000_000_000) == 100.0
        
        # Test decimals
        assert price_to_program(100.50) == 100_500_000_000
        assert abs(price_from_program(100_500_000_000) - 100.50) < 1e-9
        
        # Test small values
        assert price_to_program(0.01) == 10_000_000
        assert abs(price_from_program(10_000_000) - 0.01) < 1e-9
    
    def test_pda_generation(self, client):
        """Test PDA generation"""
        # Test that PDAs are generated consistently
        vault1, bump1 = client.get_program_authority()
        vault2, bump2 = client.get_program_authority()
        
        assert vault1 == vault2
        assert bump1 == bump2
        assert isinstance(vault1, Pubkey)
        assert 0 <= bump1 <= 255
    
    def test_position_deserialization(self):
        """Test Position deserialization"""
        # Create mock position data
        owner = Keypair().pubkey()
        base_amount = 1_000_000_000  # 1 unit long
        collateral = 150_000_000_000  # 150 units
        last_funding_index = 12345
        entry_price = 100_500_000_000  # $100.50
        
        # Pack data manually
        import struct
        data = bytearray(64)
        data[0:32] = bytes(owner)
        data[32:40] = struct.pack('<q', base_amount)
        data[40:48] = struct.pack('<Q', collateral)
        data[48:56] = struct.pack('<q', last_funding_index)
        data[56:64] = struct.pack('<Q', entry_price)
        
        # Deserialize
        position = Position.from_bytes(bytes(data))
        
        assert position.owner == owner
        assert position.base_amount == base_amount
        assert position.collateral == collateral
        assert position.last_funding_index == last_funding_index
        assert position.entry_price == entry_price
    
    def test_market_state_deserialization(self):
        """Test MarketState deserialization"""
        # Create mock market state data
        funding_index = -50000
        funding_rate_per_slot = 10000
        open_interest = 1000_000_000_000
        bump = 254
        last_funding_slot = 12345678
        mark_price = 101_000_000_000  # $101
        
        # Pack data manually
        import struct
        data = bytearray(41)
        data[0:8] = struct.pack('<q', funding_index)
        data[8:16] = struct.pack('<q', funding_rate_per_slot)
        data[16:24] = struct.pack('<Q', open_interest)
        data[24:25] = struct.pack('<B', bump)
        data[25:33] = struct.pack('<Q', last_funding_slot)
        data[33:41] = struct.pack('<Q', mark_price)
        
        # Deserialize
        market_state = MarketState.from_bytes(bytes(data))
        
        assert market_state.funding_index == funding_index
        assert market_state.funding_rate_per_slot == funding_rate_per_slot
        assert market_state.open_interest == open_interest
        assert market_state.bump == bump
        assert market_state.last_funding_slot == last_funding_slot
        assert market_state.mark_price == mark_price

async def integration_test():
    """Integration test (requires actual deployed program)"""
    print("🧪 Running integration test...")
    
    # This would require an actual program deployment
    # For now, just test the client initialization
    try:
        payer = Keypair()
        client = PerpetualsClient(TEST_RPC_URL, payer, TEST_PROGRAM_ID)
        
        print(f"✅ Client initialized with wallet: {payer.pubkey()}")
        print(f"Program ID: {client.program_id}")
        
        # Test PDA generation
        vault_pda, vault_bump = client.get_program_authority()
        position_pda, pos_bump = client.get_position_address(payer.pubkey())
        market_pda, market_bump = client.get_market_state_address()
        
        print(f"Vault PDA: {vault_pda} (bump: {vault_bump})")
        print(f"Position PDA: {position_pda} (bump: {pos_bump})")
        print(f"Market PDA: {market_pda} (bump: {market_bump})")
        
        await client.close()
        print("✅ Integration test completed")
        
    except Exception as e:
        print(f"❌ Integration test failed: {e}")

async def stress_test():
    """Basic stress test for PDA generation"""
    print("💪 Running stress test...")
    
    payer = Keypair()
    client = PerpetualsClient(TEST_RPC_URL, payer, TEST_PROGRAM_ID)
    
    try:
        # Generate many PDAs to test performance
        start_time = asyncio.get_event_loop().time()
        
        for i in range(1000):
            test_user = Keypair().pubkey()
            client.get_position_address(test_user)
        
        end_time = asyncio.get_event_loop().time()
        
        print(f"✅ Generated 1000 PDAs in {end_time - start_time:.3f} seconds")
        
    except Exception as e:
        print(f"❌ Stress test failed: {e}")
    finally:
        await client.close()

def run_unit_tests():
    """Run unit tests"""
    print("🔬 Running unit tests...")
    
    test_client = TestPerpetualsClient()
    
    # Run tests
    try:
        test_client.test_price_conversion()
        print("✅ Price conversion tests passed")
        
        test_client.test_position_deserialization()
        print("✅ Position deserialization tests passed")
        
        test_client.test_market_state_deserialization()
        print("✅ Market state deserialization tests passed")
        
        print("🎉 All unit tests passed!")
        
    except Exception as e:
        print(f"❌ Unit tests failed: {e}")

async def main():
    """Main test runner"""
    print("🐍 Solana Perpetuals Python Client Tests")
    print("=" * 50)
    
    # Run unit tests
    run_unit_tests()
    print()
    
    # Run integration test
    await integration_test()
    print()
    
    # Run stress test
    await stress_test()
    print()
    
    print("📊 Test Summary:")
    print("- Unit tests: Price conversion, data deserialization")
    print("- Integration tests: Client initialization, PDA generation")
    print("- Stress tests: Performance with multiple PDAs")
    print()
    print("💡 To test with real program:")
    print("1. Deploy the program to devnet")
    print("2. Update TEST_PROGRAM_ID with your program ID")
    print("3. Create token accounts and fund with devnet SOL/USDC")
    print("4. Run the full example with: python client.py")

if __name__ == "__main__":
    asyncio.run(main())