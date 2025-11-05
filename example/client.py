"""
Simple Perpetuals Python Client Example

This Python example demonstrates how to interact with the
Simple Perpetuals Solana program from a Python application.

Prerequisites:
- pip install solana solders borsh-construct spl-token
- Program deployed and Program ID available
"""

import asyncio
import struct
from typing import Optional, Tuple, Dict, Any
from dataclasses import dataclass
from solana.rpc.async_api import AsyncClient
from solana.rpc.commitment import Confirmed, Finalized
from solana.rpc.types import TxOpts
from solders.keypair import Keypair
from solders.pubkey import Pubkey
from solders.system_program import ID as SYS_PROGRAM_ID
from solders.sysvar import RENT as SYSVAR_RENT_PUBKEY, CLOCK as SYSVAR_CLOCK_PUBKEY
from solders.transaction import Transaction, VersionedTransaction
from solders.message import Message, MessageV0
from solders.instruction import Instruction, AccountMeta
from spl.token.constants import TOKEN_PROGRAM_ID
from spl.token.instructions import transfer, TransferParams
from spl.token._layouts import ACCOUNT_LAYOUT
import borsh_construct as borsh

# Load program ID dynamically from deployment file
try:
    with open("program_id.txt", "r") as f:
        PROGRAM_ID_STR = f.readline().strip()
    program_id_loaded = True
except FileNotFoundError:
    PROGRAM_ID_STR = "YOUR_PROGRAM_ID_HERE"  # Fallback if file doesn't exist
    program_id_loaded = False
PDA_SEED = b"perps"
PRECISION = 1_000_000_000  # 1e9 precision for prices

# Instruction tags
INSTRUCTION_OPEN_POSITION = 0
INSTRUCTION_UPDATE_FUNDING = 1
INSTRUCTION_LIQUIDATE = 2
INSTRUCTION_CLOSE_POSITION = 3

# Borsh schemas for data serialization/deserialization
@dataclass
class Position:
    owner: Pubkey
    base_amount: int  # i64
    collateral: int   # u64
    last_funding_index: int  # i64
    entry_price: int  # u64

    @classmethod
    def from_bytes(cls, data: bytes) -> 'Position':
        """Deserialize Position from account data"""
        if len(data) < 64:
            raise ValueError("Invalid position data length")
        
        owner = Pubkey(data[0:32])
        base_amount = struct.unpack('<q', data[32:40])[0]  # i64
        collateral = struct.unpack('<Q', data[40:48])[0]   # u64
        last_funding_index = struct.unpack('<q', data[48:56])[0]  # i64
        entry_price = struct.unpack('<Q', data[56:64])[0]  # u64
        
        return cls(owner, base_amount, collateral, last_funding_index, entry_price)

@dataclass
class MarketState:
    funding_index: int          # i64
    funding_rate_per_slot: int  # i64
    open_interest: int          # u64
    bump: int                   # u8
    last_funding_slot: int      # u64
    mark_price: int            # u64

    @classmethod
    def from_bytes(cls, data: bytes) -> 'MarketState':
        """Deserialize MarketState from account data"""
        if len(data) < 41:
            raise ValueError("Invalid market state data length")
        
        funding_index = struct.unpack('<q', data[0:8])[0]        # i64
        funding_rate_per_slot = struct.unpack('<q', data[8:16])[0]  # i64
        open_interest = struct.unpack('<Q', data[16:24])[0]      # u64
        bump = struct.unpack('<B', data[24:25])[0]               # u8
        last_funding_slot = struct.unpack('<Q', data[25:33])[0]  # u64
        mark_price = struct.unpack('<Q', data[33:41])[0]         # u64
        
        return cls(funding_index, funding_rate_per_slot, open_interest, 
                  bump, last_funding_slot, mark_price)

class PerpetualsClient:
    """Python client for interacting with the Simple Perpetuals program"""
    
    def __init__(self, rpc_url: str, payer: Keypair, program_id: str):
        self.client = AsyncClient(rpc_url, commitment=Confirmed)
        self.payer = payer
        self.program_id = Pubkey.from_string(program_id)
        
    async def close(self):
        """Close the RPC client"""
        await self.client.close()
    
    def get_program_authority(self) -> Tuple[Pubkey, int]:
        """Get PDA for the program authority (vault)"""
        return Pubkey.find_program_address([PDA_SEED], self.program_id)
    
    def get_position_address(self, user: Pubkey) -> Tuple[Pubkey, int]:
        """Get PDA for a user's position account"""
        return Pubkey.find_program_address([b"position", bytes(user)], self.program_id)
    
    def get_market_state_address(self) -> Tuple[Pubkey, int]:
        """Get PDA for the market state account"""
        return Pubkey.find_program_address([b"market"], self.program_id)
    
    async def open_position(
        self,
        base_delta: int,        # Position size change (signed)
        collateral_delta: int,  # Additional collateral
        entry_price: int,       # Entry price
        user_token_account: Pubkey
    ) -> str:
        """Open or modify a position"""
        
        vault_pda, _ = self.get_program_authority()
        position_pda, _ = self.get_position_address(self.payer.pubkey())
        market_state_pda, _ = self.get_market_state_address()
        
        # Create instruction data
        instruction_data = bytearray(25)
        instruction_data[0] = INSTRUCTION_OPEN_POSITION
        instruction_data[1:9] = struct.pack('<q', base_delta)      # i64
        instruction_data[9:17] = struct.pack('<Q', collateral_delta)  # u64
        instruction_data[17:25] = struct.pack('<Q', entry_price)   # u64
        
        accounts = [
            AccountMeta(pubkey=self.payer.pubkey(), is_signer=True, is_writable=False),
            AccountMeta(pubkey=TOKEN_PROGRAM_ID, is_signer=False, is_writable=False),
            AccountMeta(pubkey=user_token_account, is_signer=False, is_writable=True),
            AccountMeta(pubkey=vault_pda, is_signer=False, is_writable=True),
            AccountMeta(pubkey=position_pda, is_signer=False, is_writable=True),
            AccountMeta(pubkey=market_state_pda, is_signer=False, is_writable=True),
            AccountMeta(pubkey=SYSVAR_RENT_PUBKEY, is_signer=False, is_writable=False),
            AccountMeta(pubkey=SYSVAR_CLOCK_PUBKEY, is_signer=False, is_writable=False),
            AccountMeta(pubkey=SYS_PROGRAM_ID, is_signer=False, is_writable=False),
        ]
        
        instruction = Instruction(
            program_id=self.program_id,
            data=bytes(instruction_data),
            accounts=accounts
        )
        
        # Get latest blockhash
        blockhash_resp = await self.client.get_latest_blockhash()
        recent_blockhash = blockhash_resp.value.blockhash
        
        # Create message
        message = MessageV0.try_compile(
            self.payer.pubkey(),
            [instruction],
            [],
            recent_blockhash
        )
        
        # Create transaction
        transaction = VersionedTransaction(message, [self.payer])
        
        response = await self.client.send_transaction(
            transaction, 
            opts=TxOpts(skip_preflight=False, preflight_commitment=Confirmed)
        )
        
        return response['result']
    
    async def update_funding(self) -> str:
        """Update funding rates (should be called periodically)"""
        
        market_state_pda, _ = self.get_market_state_address()
        
        instruction_data = bytes([INSTRUCTION_UPDATE_FUNDING])
        
        accounts = [
            AccountMeta(pubkey=market_state_pda, is_signer=False, is_writable=True),
            AccountMeta(pubkey=SYSVAR_CLOCK_PUBKEY, is_signer=False, is_writable=False),
        ]
        
        instruction = Instruction(
            program_id=self.program_id,
            data=instruction_data,
            accounts=accounts
        )
        
        transaction = Transaction().add(instruction)
        
        response = await self.client.send_transaction(
            transaction,
            self.payer,
            opts=TxOpts(skip_preflight=False, preflight_commitment=Confirmed)
        )
        
        return response['result']
    
    async def liquidate(
        self,
        position_owner: Pubkey,
        liquidator_token_account: Pubkey
    ) -> str:
        """Liquidate an undercollateralized position"""
        
        vault_pda, _ = self.get_program_authority()
        position_pda, _ = self.get_position_address(position_owner)
        market_state_pda, _ = self.get_market_state_address()
        
        instruction_data = bytes([INSTRUCTION_LIQUIDATE])
        
        accounts = [
            AccountMeta(pubkey=self.payer.pubkey(), is_signer=True, is_writable=False),
            AccountMeta(pubkey=TOKEN_PROGRAM_ID, is_signer=False, is_writable=False),
            AccountMeta(pubkey=liquidator_token_account, is_signer=False, is_writable=True),
            AccountMeta(pubkey=vault_pda, is_signer=False, is_writable=True),
            AccountMeta(pubkey=position_pda, is_signer=False, is_writable=True),
            AccountMeta(pubkey=market_state_pda, is_signer=False, is_writable=True),
            AccountMeta(pubkey=SYSVAR_CLOCK_PUBKEY, is_signer=False, is_writable=False),
        ]
        
        instruction = Instruction(
            program_id=self.program_id,
            data=instruction_data,
            accounts=accounts
        )
        
        transaction = Transaction().add(instruction)
        
        response = await self.client.send_transaction(
            transaction,
            self.payer,
            opts=TxOpts(skip_preflight=False, preflight_commitment=Confirmed)
        )
        
        return response['result']
    
    async def close_position(self, user_token_account: Pubkey) -> str:
        """Close a position voluntarily"""
        
        vault_pda, _ = self.get_program_authority()
        position_pda, _ = self.get_position_address(self.payer.pubkey())
        market_state_pda, _ = self.get_market_state_address()
        
        instruction_data = bytes([INSTRUCTION_CLOSE_POSITION])
        
        accounts = [
            AccountMeta(pubkey=self.payer.pubkey(), is_signer=True, is_writable=False),
            AccountMeta(pubkey=TOKEN_PROGRAM_ID, is_signer=False, is_writable=False),
            AccountMeta(pubkey=user_token_account, is_signer=False, is_writable=True),
            AccountMeta(pubkey=vault_pda, is_signer=False, is_writable=True),
            AccountMeta(pubkey=position_pda, is_signer=False, is_writable=True),
            AccountMeta(pubkey=market_state_pda, is_signer=False, is_writable=True),
        ]
        
        instruction = Instruction(
            program_id=self.program_id,
            data=instruction_data,
            accounts=accounts
        )
        
        transaction = Transaction().add(instruction)
        
        response = await self.client.send_transaction(
            transaction,
            self.payer,
            opts=TxOpts(skip_preflight=False, preflight_commitment=Confirmed)
        )
        
        return response['result']
    
    async def get_position(self, user: Pubkey) -> Optional[Position]:
        """Get position data for a user"""
        
        position_pda, _ = self.get_position_address(user)
        
        try:
            response = await self.client.get_account_info(position_pda, commitment=Confirmed)
            if response.value is None:
                return None
            
            account_data = response.value.data
            return Position.from_bytes(account_data)
            
        except Exception as e:
            return None
    
    async def get_market_state(self) -> Optional[MarketState]:
        """Get market state"""
        
        market_state_pda, _ = self.get_market_state_address()
        
        try:
            response = await self.client.get_account_info(market_state_pda, commitment=Confirmed)
            if response.value is None:
                return None
            
            account_data = response.value.data
            return MarketState.from_bytes(account_data)
            
        except Exception as e:
            return None
    
    async def calculate_position_health(self, position: Position, mark_price: int) -> float:
        """Calculate position health (collateral ratio)"""
        if position.base_amount == 0:
            return float('inf')  # No position = perfect health
        
        position_value = abs(position.base_amount) * mark_price // PRECISION
        if position_value == 0:
            return float('inf')
        
        return position.collateral / position_value
    
    async def calculate_unrealized_pnl(self, position: Position, mark_price: int) -> int:
        """Calculate unrealized PnL for a position"""
        if position.base_amount == 0:
            return 0
        
        position_size = abs(position.base_amount)
        
        if position.base_amount > 0:  # Long position
            # PnL = (mark_price - entry_price) * size / 1e9
            pnl = (mark_price - position.entry_price) * position_size // PRECISION
        else:  # Short position
            # PnL = (entry_price - mark_price) * size / 1e9
            pnl = (position.entry_price - mark_price) * position_size // PRECISION
        
        return pnl

# Utility functions
def price_to_program(price: float) -> int:
    """Convert human-readable price to program format"""
    return int(price * PRECISION)

def price_from_program(program_price: int) -> float:
    """Convert program price to human-readable format"""
    return program_price / PRECISION

def size_to_program(size: float) -> int:
    """Convert human-readable size to program format"""
    return int(size * PRECISION)

def size_from_program(program_size: int) -> float:
    """Convert program size to human-readable format"""
    return program_size / PRECISION

async def example_usage():
    """Example usage of the Perpetuals client"""
    
    # Connect to devnet
    rpc_url = "https://api.devnet.solana.com"
    
    # Generate a keypair (in practice, load from file)
    payer = Keypair()
    
    # Initialize client
    client = PerpetualsClient(rpc_url, payer, PROGRAM_ID_STR)
    
    try:
        print(f"💰 Wallet: {payer.pubkey()}")
        
        # Test PDA generation (works without deployed program)
        vault_pda, vault_bump = client.get_program_authority()
        position_pda, pos_bump = client.get_position_address(payer.pubkey())
        market_pda, market_bump = client.get_market_state_address()
        
        print(f"🏦 Vault PDA: {vault_pda} (bump: {vault_bump})")
        print(f"👤 Position PDA: {position_pda} (bump: {pos_bump})")
        print(f"📊 Market PDA: {market_pda} (bump: {market_bump})")
        
        # Test price conversions
        test_price = 100.50
        program_price = price_to_program(test_price)
        converted_back = price_from_program(program_price)
        print(f"💰 Price conversion test: ${test_price} → {program_price} → ${converted_back}")
        
        # Try to read market state from deployed program (silently)
        try:
            market_state = await client.get_market_state()
            if market_state:
                pass  # Successfully read market state, but don't print
            else:
                pass  # Market state not found, but don't print
        except Exception:
            pass  # Could not read market state, but don't print
        
        # Try to read position for this wallet (silently)
        try:
            position = await client.get_position(payer.pubkey())
            if position:
                pass  # Position found, but don't print
            else:
                pass  # No position found, but don't print
        except Exception:
            pass  # Could not read position, but don't print
        
    except Exception as e:
        print(f"❌ Example error: {e}")
    finally:
        await client.close()

class PositionMonitor:
    """Utility class for monitoring positions and liquidation opportunities"""
    
    def __init__(self, client: PerpetualsClient):
        self.client = client
    
    async def monitor_liquidations(self, user_addresses: list[Pubkey]) -> list[Pubkey]:
        """Monitor positions for liquidation opportunities"""
        liquidatable = []
        
        market_state = await self.client.get_market_state()
        if not market_state:
            return liquidatable
        
        for user in user_addresses:
            position = await self.client.get_position(user)
            if not position or position.base_amount == 0:
                continue
            
            health = await self.client.calculate_position_health(position, market_state.mark_price)
            
            # Check if below 150% collateral ratio (1.5)
            if health < 1.5:
                liquidatable.append(user)
                print(f"🚨 Liquidation opportunity: {user} (health: {health:.3f})")
        
        return liquidatable
    
    async def get_position_summary(self, user: Pubkey) -> Dict[str, Any]:
        """Get comprehensive position summary"""
        position = await self.client.get_position(user)
        if not position:
            return {"exists": False}
        
        market_state = await self.client.get_market_state()
        if not market_state:
            return {"exists": True, "error": "Market state not available"}
        
        health = await self.client.calculate_position_health(position, market_state.mark_price)
        pnl = await self.client.calculate_unrealized_pnl(position, market_state.mark_price)
        
        return {
            "exists": True,
            "owner": str(position.owner),
            "size": size_from_program(position.base_amount),
            "collateral": price_from_program(position.collateral),
            "entry_price": price_from_program(position.entry_price),
            "mark_price": price_from_program(market_state.mark_price),
            "health_ratio": health,
            "unrealized_pnl": price_from_program(pnl),
            "is_liquidatable": health < 1.5,
            "position_type": "Long" if position.base_amount > 0 else "Short" if position.base_amount < 0 else "None"
        }

# ===== TEST SUITE =====

import pytest
import pytest_asyncio

# Test configuration
TEST_RPC_URL = "https://api.devnet.solana.com"
TEST_PROGRAM_ID = "11111111111111111111111111111111"  # Placeholder

class TestPerpetualsClient:
    """Test cases for the Perpetuals client"""
    
    @pytest_asyncio.fixture
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
    
    @pytest.mark.asyncio
    async def test_pda_generation(self, client):
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

# Run demo if this file is executed directly
if __name__ == "__main__":
    print("🐍 Creating Solana Perpetuals Python Client")
    if not program_id_loaded:
        print("⚠️  Make sure to replace PROGRAM_ID_STR and token accounts with actual values!")
    asyncio.run(example_usage())