/**
 * Simple Perpetuals Client Example
 * 
 * This TypeScript example demonstrates how to interact with the
 * Simple Perpetuals Solana program from a client application.
 * 
 * Prerequisites:
 * - npm install @solana/web3.js @solana/spl-token
 * - Program deployed and Program ID available
 */

import {
    Connection,
    PublicKey,
    Keypair,
    Transaction,
    TransactionInstruction,
    SystemProgram,
    SYSVAR_RENT_PUBKEY,
    SYSVAR_CLOCK_PUBKEY,
    sendAndConfirmTransaction,
} from '@solana/web3.js';
import {
    TOKEN_PROGRAM_ID,
    createAssociatedTokenAccountInstruction,
    getAssociatedTokenAddress,
} from '@solana/spl-token';

// Configuration
const PROGRAM_ID = new PublicKey('YOUR_PROGRAM_ID_HERE'); // Replace with actual program ID
const PDA_SEED = 'perps';
const PRECISION = 1_000_000_000; // 1e9 precision for prices

// Instruction tags
const INSTRUCTION_OPEN_POSITION = 0;
const INSTRUCTION_UPDATE_FUNDING = 1;
const INSTRUCTION_LIQUIDATE = 2;
const INSTRUCTION_CLOSE_POSITION = 3;

class PerpetualsClient {
    connection: Connection;
    payer: Keypair;
    programId: PublicKey;

    constructor(connection: Connection, payer: Keypair, programId: PublicKey) {
        this.connection = connection;
        this.payer = payer;
        this.programId = programId;
    }

    /**
     * Get PDA for the program authority (vault)
     */
    getProgramAuthority(): [PublicKey, number] {
        return PublicKey.findProgramAddressSync(
            [Buffer.from(PDA_SEED)],
            this.programId
        );
    }

    /**
     * Get PDA for a user's position account
     */
    getPositionAddress(user: PublicKey): [PublicKey, number] {
        return PublicKey.findProgramAddressSync(
            [Buffer.from('position'), user.toBuffer()],
            this.programId
        );
    }

    /**
     * Get PDA for the market state account
     */
    getMarketStateAddress(): [PublicKey, number] {
        return PublicKey.findProgramAddressSync(
            [Buffer.from('market')],
            this.programId
        );
    }

    /**
     * Open or modify a position
     */
    async openPosition(
        baseDelta: number,      // Position size change (signed)
        collateralDelta: number, // Additional collateral
        entryPrice: number,     // Entry price
        userTokenAccount: PublicKey
    ): Promise<string> {
        const [vaultPda] = this.getProgramAuthority();
        const [positionPda] = this.getPositionAddress(this.payer.publicKey);
        const [marketStatePda] = this.getMarketStateAddress();

        // Create instruction data
        const instructionData = Buffer.alloc(25);
        instructionData.writeUInt8(INSTRUCTION_OPEN_POSITION, 0);
        instructionData.writeBigInt64LE(BigInt(baseDelta), 1);
        instructionData.writeBigUInt64LE(BigInt(collateralDelta), 9);
        instructionData.writeBigUInt64LE(BigInt(entryPrice), 17);

        const instruction = new TransactionInstruction({
            programId: this.programId,
            keys: [
                { pubkey: this.payer.publicKey, isSigner: true, isWritable: false },
                { pubkey: TOKEN_PROGRAM_ID, isSigner: false, isWritable: false },
                { pubkey: userTokenAccount, isSigner: false, isWritable: true },
                { pubkey: vaultPda, isSigner: false, isWritable: true },
                { pubkey: positionPda, isSigner: false, isWritable: true },
                { pubkey: marketStatePda, isSigner: false, isWritable: true },
                { pubkey: SYSVAR_RENT_PUBKEY, isSigner: false, isWritable: false },
                { pubkey: SYSVAR_CLOCK_PUBKEY, isSigner: false, isWritable: false },
                { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
            ],
            data: instructionData,
        });

        const transaction = new Transaction().add(instruction);
        
        return await sendAndConfirmTransaction(
            this.connection,
            transaction,
            [this.payer],
            { commitment: 'confirmed' }
        );
    }

    /**
     * Update funding rates (should be called periodically)
     */
    async updateFunding(): Promise<string> {
        const [marketStatePda] = this.getMarketStateAddress();

        const instructionData = Buffer.alloc(1);
        instructionData.writeUInt8(INSTRUCTION_UPDATE_FUNDING, 0);

        const instruction = new TransactionInstruction({
            programId: this.programId,
            keys: [
                { pubkey: marketStatePda, isSigner: false, isWritable: true },
                { pubkey: SYSVAR_CLOCK_PUBKEY, isSigner: false, isWritable: false },
            ],
            data: instructionData,
        });

        const transaction = new Transaction().add(instruction);
        
        return await sendAndConfirmTransaction(
            this.connection,
            transaction,
            [this.payer],
            { commitment: 'confirmed' }
        );
    }

    /**
     * Liquidate an undercollateralized position
     */
    async liquidate(
        positionOwner: PublicKey,
        liquidatorTokenAccount: PublicKey
    ): Promise<string> {
        const [vaultPda] = this.getProgramAuthority();
        const [positionPda] = this.getPositionAddress(positionOwner);
        const [marketStatePda] = this.getMarketStateAddress();

        const instructionData = Buffer.alloc(1);
        instructionData.writeUInt8(INSTRUCTION_LIQUIDATE, 0);

        const instruction = new TransactionInstruction({
            programId: this.programId,
            keys: [
                { pubkey: this.payer.publicKey, isSigner: true, isWritable: false },
                { pubkey: TOKEN_PROGRAM_ID, isSigner: false, isWritable: false },
                { pubkey: liquidatorTokenAccount, isSigner: false, isWritable: true },
                { pubkey: vaultPda, isSigner: false, isWritable: true },
                { pubkey: positionPda, isSigner: false, isWritable: true },
                { pubkey: marketStatePda, isSigner: false, isWritable: true },
                { pubkey: SYSVAR_CLOCK_PUBKEY, isSigner: false, isWritable: false },
            ],
            data: instructionData,
        });

        const transaction = new Transaction().add(instruction);
        
        return await sendAndConfirmTransaction(
            this.connection,
            transaction,
            [this.payer],
            { commitment: 'confirmed' }
        );
    }

    /**
     * Close a position voluntarily
     */
    async closePosition(userTokenAccount: PublicKey): Promise<string> {
        const [vaultPda] = this.getProgramAuthority();
        const [positionPda] = this.getPositionAddress(this.payer.publicKey);
        const [marketStatePda] = this.getMarketStateAddress();

        const instructionData = Buffer.alloc(1);
        instructionData.writeUInt8(INSTRUCTION_CLOSE_POSITION, 0);

        const instruction = new TransactionInstruction({
            programId: this.programId,
            keys: [
                { pubkey: this.payer.publicKey, isSigner: true, isWritable: false },
                { pubkey: TOKEN_PROGRAM_ID, isSigner: false, isWritable: false },
                { pubkey: userTokenAccount, isSigner: false, isWritable: true },
                { pubkey: vaultPda, isSigner: false, isWritable: true },
                { pubkey: positionPda, isSigner: false, isWritable: true },
                { pubkey: marketStatePda, isSigner: false, isWritable: true },
            ],
            data: instructionData,
        });

        const transaction = new Transaction().add(instruction);
        
        return await sendAndConfirmTransaction(
            this.connection,
            transaction,
            [this.payer],
            { commitment: 'confirmed' }
        );
    }

    /**
     * Get position data for a user
     */
    async getPosition(user: PublicKey): Promise<any> {
        const [positionPda] = this.getPositionAddress(user);
        
        try {
            const accountInfo = await this.connection.getAccountInfo(positionPda);
            if (!accountInfo || !accountInfo.data) {
                return null;
            }

            // Parse position data (simplified - in practice use borsh)
            const data = accountInfo.data;
            return {
                owner: new PublicKey(data.slice(0, 32)),
                baseAmount: data.readBigInt64LE(32),
                collateral: data.readBigUInt64LE(40),
                lastFundingIndex: data.readBigInt64LE(48),
                entryPrice: data.readBigUInt64LE(56),
            };
        } catch (error) {
            console.error('Error fetching position:', error);
            return null;
        }
    }

    /**
     * Get market state
     */
    async getMarketState(): Promise<any> {
        const [marketStatePda] = this.getMarketStateAddress();
        
        try {
            const accountInfo = await this.connection.getAccountInfo(marketStatePda);
            if (!accountInfo || !accountInfo.data) {
                return null;
            }

            // Parse market state data (simplified - in practice use borsh)
            const data = accountInfo.data;
            return {
                fundingIndex: data.readBigInt64LE(0),
                fundingRatePerSlot: data.readBigInt64LE(8),
                openInterest: data.readBigUInt64LE(16),
                bump: data.readUInt8(24),
                lastFundingSlot: data.readBigUInt64LE(25),
                markPrice: data.readBigUInt64LE(33),
            };
        } catch (error) {
            console.error('Error fetching market state:', error);
            return null;
        }
    }
}

// Example usage
async function example() {
    // Connect to devnet
    const connection = new Connection('https://api.devnet.solana.com', 'confirmed');
    
    // Load your keypair
    const payer = Keypair.generate(); // In practice, load from file
    
    // Initialize client
    const client = new PerpetualsClient(connection, payer, PROGRAM_ID);
    
    try {
        // Example: Open a long position
        console.log('Opening long position...');
        const userTokenAccount = await getAssociatedTokenAddress(
            new PublicKey('USDC_MINT_ADDRESS'), // Replace with actual USDC mint
            payer.publicKey
        );
        
        const txId = await client.openPosition(
            1 * PRECISION,       // 1 unit long
            150 * PRECISION,     // 150 USDC collateral
            100.5 * PRECISION,   // $100.50 entry price
            userTokenAccount
        );
        console.log('Transaction:', txId);

        // Example: Update funding
        console.log('Updating funding...');
        const fundingTxId = await client.updateFunding();
        console.log('Funding update transaction:', fundingTxId);

        // Example: Check position
        const position = await client.getPosition(payer.publicKey);
        console.log('Position:', position);

        // Example: Check market state
        const marketState = await client.getMarketState();
        console.log('Market state:', marketState);

    } catch (error) {
        console.error('Example error:', error);
    }
}

// Utility functions
export function priceToProgram(price: number): number {
    return Math.floor(price * PRECISION);
}

export function priceFromProgram(programPrice: bigint): number {
    return Number(programPrice) / PRECISION;
}

export function sizeToProgram(size: number): number {
    return Math.floor(size * PRECISION);
}

export function sizeFromProgram(programSize: bigint): number {
    return Number(programSize) / PRECISION;
}

// Export the client class
export { PerpetualsClient };

// Run example if this file is executed directly
if (require.main === module) {
    example().catch(console.error);
}