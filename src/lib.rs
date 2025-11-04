#![allow(unexpected_cfgs)]

use borsh::{BorshDeserialize, BorshSerialize};
use solana_program::{
    account_info::{next_account_info, AccountInfo},
    entrypoint,
    entrypoint::ProgramResult,
    instruction::{AccountMeta, Instruction},
    msg,
    program::{invoke, invoke_signed},
    program_error::ProgramError,
    pubkey::Pubkey,
    sysvar::{clock::Clock, rent::Rent, Sysvar},
    system_instruction,
};

// Suppress warnings for educational implementation
#[allow(unused)]

/// PDA seed for the program's authority (used for collateral vault)
pub const PDA_SEED: &[u8] = b"perps";

/// Helper function to create a SPL token transfer instruction
fn create_transfer_instruction(
    token_program: &Pubkey,
    source: &Pubkey,
    destination: &Pubkey,
    authority: &Pubkey,
    amount: u64,
) -> Result<Instruction, ProgramError> {
    let mut data = vec![3]; // Transfer instruction discriminator
    data.extend_from_slice(&amount.to_le_bytes());

    Ok(Instruction {
        program_id: *token_program,
        accounts: vec![
            AccountMeta::new(*source, false),
            AccountMeta::new(*destination, false),
            AccountMeta::new_readonly(*authority, true),
        ],
        data,
    })
}

/// Minimum collateral ratio (150% = 1.5 * 1e9)
pub const MIN_COLLATERAL_RATIO: u64 = 1_500_000_000;

/// Liquidation penalty (10% = 0.1 * 1e9)
pub const LIQUIDATION_PENALTY: u64 = 100_000_000;

/// Data stored in a user's position account
#[derive(BorshSerialize, BorshDeserialize, Debug, Default, Clone)]
pub struct Position {
    /// Owner of the position
    pub owner: Pubkey,
    /// Amount of base token (positive = long, negative = short) – 1e9 precision
    pub base_amount: i64,
    /// Collateral locked in the vault (in quote token, e.g., USDC)
    pub collateral: u64,
    /// Last funding index applied to this position
    pub last_funding_index: i64,
    /// Entry price when position was opened (1e9 precision)
    pub entry_price: u64,
}

/// Global state for the market (single‑asset example)
#[derive(BorshSerialize, BorshDeserialize, Debug, Default, Clone)]
pub struct MarketState {
    /// Index that accumulates funding payments (scaled by 1e9)
    pub funding_index: i64,
    /// Funding rate per slot (signed, 1e9 precision)
    pub funding_rate_per_slot: i64,
    /// Total open interest (sum of |base_amount|)
    pub open_interest: u64,
    /// PDA bump for authority
    pub bump: u8,
    /// Last update slot for funding
    pub last_funding_slot: u64,
    /// Current mark price (1e9 precision) - in production use oracle
    pub mark_price: u64,
}

// ---------------------------------------------------------------------
// Program entrypoint
// ---------------------------------------------------------------------
entrypoint!(process_instruction);

pub fn process_instruction(
    program_id: &Pubkey,
    accounts: &[AccountInfo],
    instruction_data: &[u8],
) -> ProgramResult {
    // First byte = instruction tag
    let (tag, rest) = instruction_data
        .split_first()
        .ok_or(ProgramError::InvalidInstructionData)?;

    match tag {
        0 => open_position(program_id, accounts, rest),
        1 => update_funding(program_id, accounts),
        2 => liquidate(program_id, accounts),
        3 => close_position(program_id, accounts),
        _ => {
            msg!("Invalid instruction tag: {}", tag);
            Err(ProgramError::InvalidInstructionData)
        }
    }
}

// ---------------------------------------------------------------------
// 0️⃣ Open / modify a position
// ---------------------------------------------------------------------
pub fn open_position(
    program_id: &Pubkey,
    accounts: &[AccountInfo],
    data: &[u8],
) -> ProgramResult {
    // Accounts:
    // 0. [signer] user
    // 1. [] token program
    // 2. [writable] user's collateral token account (quote token, e.g., USDC)
    // 3. [writable] vault token account (PDA‑owned)
    // 4. [writable] position account (PDA‑derived)
    // 5. [writable] market state account (PDA‑derived)
    // 6. [] rent sysvar
    // 7. [] clock sysvar
    // 8. [] system program (for account creation)
    let accounts_iter = &mut accounts.iter();
    let user = next_account_info(accounts_iter)?;
    let token_program = next_account_info(accounts_iter)?;
    let user_collateral = next_account_info(accounts_iter)?;
    let vault = next_account_info(accounts_iter)?;
    let position_acc = next_account_info(accounts_iter)?;
    let market_state_acc = next_account_info(accounts_iter)?;
    let rent_sysvar = next_account_info(accounts_iter)?;
    let clock_sysvar = next_account_info(accounts_iter)?;
    let system_program = next_account_info(accounts_iter)?;

    // Ensure user is signer
    if !user.is_signer {
        msg!("User must be signer");
        return Err(ProgramError::MissingRequiredSignature);
    }

    // Decode instruction payload:
    if data.len() < 24 {
        msg!("Insufficient instruction data");
        return Err(ProgramError::InvalidInstructionData);
    }

    let base_delta = i64::from_le_bytes(data[0..8].try_into().unwrap());
    let collateral_delta = u64::from_le_bytes(data[8..16].try_into().unwrap());
    let entry_price = u64::from_le_bytes(data[16..24].try_into().unwrap());

    msg!("Opening position: base_delta={}, collateral_delta={}, entry_price={}", 
         base_delta, collateral_delta, entry_price);

    // Derive PDA authority
    let (pda, bump) = Pubkey::find_program_address(&[PDA_SEED], program_id);
    
    // Verify vault is the correct PDA
    if *vault.key != pda {
        msg!("Vault account is not the correct PDA. Expected: {}, Got: {}", pda, vault.key);
        return Err(ProgramError::InvalidArgument);
    }

    let clock = Clock::from_account_info(clock_sysvar)?;
    let rent = Rent::from_account_info(rent_sysvar)?;

    // ---------- Initialize market state if empty ----------
    if market_state_acc.data_is_empty() {
        let required_lamports = rent.minimum_balance(std::mem::size_of::<MarketState>());
        
        let create_market_ix = system_instruction::create_account(
            user.key,
            market_state_acc.key,
            required_lamports,
            std::mem::size_of::<MarketState>() as u64,
            program_id,
        );

        invoke(&create_market_ix, &[
            user.clone(),
            market_state_acc.clone(),
            system_program.clone(),
        ])?;

        let market_state = MarketState {
            funding_index: 0,
            funding_rate_per_slot: 0,
            open_interest: 0,
            bump,
            last_funding_slot: clock.slot,
            mark_price: entry_price, // Initialize with entry price
        };
        market_state.serialize(&mut *market_state_acc.data.borrow_mut())?;
        msg!("Initialized market state");
    }

    // ---------- Initialize position if empty ----------
    if position_acc.data_is_empty() {
        let required_lamports = rent.minimum_balance(std::mem::size_of::<Position>());
        
        let create_position_ix = system_instruction::create_account(
            user.key,
            position_acc.key,
            required_lamports,
            std::mem::size_of::<Position>() as u64,
            program_id,
        );

        invoke(&create_position_ix, &[
            user.clone(),
            position_acc.clone(),
            system_program.clone(),
        ])?;

        let position = Position {
            owner: *user.key,
            base_amount: 0,
            collateral: 0,
            last_funding_index: 0,
            entry_price: 0,
        };
        position.serialize(&mut *position_acc.data.borrow_mut())?;
        msg!("Initialized position account for user: {}", user.key);
    }

    // ---------- Load mutable structs ----------
    #[allow(unused_mut)]
    let mut market_state = MarketState::try_from_slice(&market_state_acc.data.borrow())?;
    #[allow(unused_mut)]
    let mut position = Position::try_from_slice(&position_acc.data.borrow())?;

    // Verify position owner
    if position.owner != *user.key {
        msg!("Position owner mismatch. Expected: {}, Got: {}", user.key, position.owner);
        return Err(ProgramError::IllegalOwner);
    }

    // ---------- Transfer collateral from user to vault ----------
    if collateral_delta > 0 {
        let transfer_ix = create_transfer_instruction(
            token_program.key,
            user_collateral.key,
            vault.key,
            user.key,
            collateral_delta,
        )?;

        invoke(&transfer_ix, &[
            user_collateral.clone(),
            vault.clone(),
            user.clone(),
            token_program.clone(),
        ])?;
        
        position.collateral = position
            .collateral
            .checked_add(collateral_delta)
            .ok_or(ProgramError::InvalidArgument)?;
        
        msg!("Transferred {} collateral to vault", collateral_delta);
    }

    // ---------- Apply pending funding before position update ----------
    let funding_delta = market_state.funding_index
        .checked_sub(position.last_funding_index)
        .ok_or(ProgramError::InvalidArgument)?;

    if funding_delta != 0 && position.base_amount != 0 {
        // Funding payment = base_amount * funding_delta / 1e9
        let funding_payment = ((position.base_amount as i128)
            .checked_mul(funding_delta as i128)
            .ok_or(ProgramError::InvalidArgument)?)
            .checked_div(1_000_000_000i128)
            .ok_or(ProgramError::InvalidAccountData)?;

        if funding_payment > 0 {
            // User owes funding → deduct from collateral
            position.collateral = position
                .collateral
                .checked_sub(funding_payment as u64)
                .ok_or(ProgramError::InsufficientFunds)?;
            msg!("Applied funding payment: -{}", funding_payment);
        } else if funding_payment < 0 {
            // User receives funding → add to collateral
            position.collateral = position
                .collateral
                .checked_add((-funding_payment) as u64)
                .ok_or(ProgramError::InvalidArgument)?;
            msg!("Received funding payment: +{}", -funding_payment);
        }
    }
    position.last_funding_index = market_state.funding_index;

    // ---------- Update position ----------
    let old_base_amount = position.base_amount;
    position.base_amount = position
        .base_amount
        .checked_add(base_delta)
        .ok_or(ProgramError::InvalidArgument)?;

    // Update entry price for new position or position increase
    if old_base_amount == 0 || (old_base_amount > 0 && base_delta > 0) || (old_base_amount < 0 && base_delta < 0) {
        position.entry_price = entry_price;
    }

    // Update open interest
    let old_oi_contribution = old_base_amount.abs() as u64;
    let new_oi_contribution = position.base_amount.abs() as u64;
    
    market_state.open_interest = market_state
        .open_interest
        .checked_sub(old_oi_contribution)
        .ok_or(ProgramError::InvalidArgument)?
        .checked_add(new_oi_contribution)
        .ok_or(ProgramError::InvalidArgument)?;

    // Update mark price
    market_state.mark_price = entry_price;

    // ---------- Validate collateral ratio ----------
    if position.base_amount != 0 {
        let position_value = (position.base_amount.abs() as u64)
            .checked_mul(market_state.mark_price)
            .ok_or(ProgramError::InvalidArgument)?
            .checked_div(1_000_000_000)
            .ok_or(ProgramError::InvalidAccountData)?;

        let collateral_ratio = if position_value > 0 {
            position.collateral
                .checked_mul(1_000_000_000)
                .ok_or(ProgramError::InvalidArgument)?
                .checked_div(position_value)
                .ok_or(ProgramError::InvalidAccountData)?
        } else {
            u64::MAX
        };

        if collateral_ratio < MIN_COLLATERAL_RATIO {
            msg!("Insufficient collateral ratio: {} < {}", collateral_ratio, MIN_COLLATERAL_RATIO);
            return Err(ProgramError::InsufficientFunds);
        }
        
        msg!("Collateral ratio: {}", collateral_ratio);
    }

    // ---------- Persist changes ----------
    position.serialize(&mut *position_acc.data.borrow_mut())?;
    market_state.serialize(&mut *market_state_acc.data.borrow_mut())?;

    msg!("Position updated successfully: base={}, collateral={}, open_interest={}", 
         position.base_amount, position.collateral, market_state.open_interest);
    
    Ok(())
}

// ---------------------------------------------------------------------
// 1️⃣ Update funding index (called periodically, e.g., every slot)
// ---------------------------------------------------------------------
pub fn update_funding(_program_id: &Pubkey, accounts: &[AccountInfo]) -> ProgramResult {
    // Accounts:
    // 0. [writable] market state PDA
    // 1. [] clock sysvar
    let accounts_iter = &mut accounts.iter();
    let market_state_acc = next_account_info(accounts_iter)?;
    let clock_sysvar = next_account_info(accounts_iter)?;

    let clock = Clock::from_account_info(clock_sysvar)?;
    let mut market_state = MarketState::try_from_slice(&market_state_acc.data.borrow())?;

    // Calculate slots elapsed since last funding update
    let slots_elapsed = clock.slot
        .checked_sub(market_state.last_funding_slot)
        .ok_or(ProgramError::InvalidAccountData)?;

    if slots_elapsed == 0 {
        msg!("No slots elapsed since last funding update");
        return Ok(());
    }

    // Simple funding rate calculation:
    // - Base rate: 0.01% per slot (10_000 per slot when scaled by 1e9)
    // - Adjusted by open interest imbalance (in practice, use more sophisticated model)
    let base_rate = 10_000i64; // 0.01% * 1e9 = 10_000
    
    // In production, this would consider:
    // - Interest rate differentials
    // - Long/short imbalance
    // - Market volatility
    // - External funding rates
    market_state.funding_rate_per_slot = if market_state.open_interest > 1_000_000_000 {
        base_rate.checked_mul(2).ok_or(ProgramError::InvalidArgument)?  // Higher rate for higher OI
    } else {
        base_rate
    };

    // Accumulate funding index
    let funding_increment = market_state.funding_rate_per_slot
        .checked_mul(slots_elapsed as i64)
        .ok_or(ProgramError::InvalidArgument)?;
        
    market_state.funding_index = market_state.funding_index
        .checked_add(funding_increment)
        .ok_or(ProgramError::InvalidArgument)?;

    market_state.last_funding_slot = clock.slot;

    // Persist changes
    market_state.serialize(&mut *market_state_acc.data.borrow_mut())?;

    msg!("Funding updated: rate_per_slot={}, index={}, slots_elapsed={}", 
         market_state.funding_rate_per_slot, market_state.funding_index, slots_elapsed);
    
    Ok(())
}

// ---------------------------------------------------------------------
// 2️⃣ Liquidate an undercollateralized position
// ---------------------------------------------------------------------
pub fn liquidate(program_id: &Pubkey, accounts: &[AccountInfo]) -> ProgramResult {
    // Accounts:
    // 0. [signer] liquidator
    // 1. [] token program
    // 2. [writable] liquidator's token account (to receive liquidation reward)
    // 3. [writable] vault token account (PDA‑owned)
    // 4. [writable] position account to liquidate
    // 5. [writable] market state account
    // 6. [] clock sysvar
    let accounts_iter = &mut accounts.iter();
    let liquidator = next_account_info(accounts_iter)?;
    let token_program = next_account_info(accounts_iter)?;
    let liquidator_token_acc = next_account_info(accounts_iter)?;
    let vault = next_account_info(accounts_iter)?;
    let position_acc = next_account_info(accounts_iter)?;
    let market_state_acc = next_account_info(accounts_iter)?;
    let clock_sysvar = next_account_info(accounts_iter)?;

    if !liquidator.is_signer {
        msg!("Liquidator must be signer");
        return Err(ProgramError::MissingRequiredSignature);
    }

    let _clock = Clock::from_account_info(clock_sysvar)?;
    let mut market_state = MarketState::try_from_slice(&market_state_acc.data.borrow())?;
    let mut position = Position::try_from_slice(&position_acc.data.borrow())?;

    // Verify position exists and has exposure
    if position.base_amount == 0 {
        msg!("Position has no exposure to liquidate");
        return Err(ProgramError::InvalidArgument);
    }

    // Apply any pending funding
    let funding_delta = market_state.funding_index
        .checked_sub(position.last_funding_index)
        .ok_or(ProgramError::InvalidArgument)?;

    if funding_delta != 0 {
        let funding_payment = ((position.base_amount as i128)
            .checked_mul(funding_delta as i128)
            .ok_or(ProgramError::InvalidArgument)?)
            .checked_div(1_000_000_000i128)
            .ok_or(ProgramError::InvalidAccountData)?;

        if funding_payment > 0 {
            position.collateral = position
                .collateral
                .checked_sub(funding_payment as u64)
                .unwrap_or(0); // Don't fail if insufficient, that makes it more liquidatable
        } else {
            position.collateral = position
                .collateral
                .checked_add((-funding_payment) as u64)
                .ok_or(ProgramError::InvalidArgument)?;
        }
    }
    position.last_funding_index = market_state.funding_index;

    // Calculate position value and current PnL
    let position_size = position.base_amount.abs() as u64;
    let position_value = position_size
        .checked_mul(market_state.mark_price)
        .ok_or(ProgramError::InvalidArgument)?
        .checked_div(1_000_000_000)
        .ok_or(ProgramError::InvalidAccountData)?;

    // Calculate unrealized PnL
    let _entry_value = position_size
        .checked_mul(position.entry_price)
        .ok_or(ProgramError::InvalidArgument)?
        .checked_div(1_000_000_000)
        .ok_or(ProgramError::InvalidAccountData)?;

    let unrealized_pnl = if position.base_amount > 0 {
        // Long position: PnL = (mark_price - entry_price) * size
        (market_state.mark_price as i64)
            .checked_sub(position.entry_price as i64)
            .ok_or(ProgramError::InvalidArgument)?
            .checked_mul(position_size as i64)
            .ok_or(ProgramError::InvalidArgument)?
            .checked_div(1_000_000_000)
            .ok_or(ProgramError::InvalidAccountData)?
    } else {
        // Short position: PnL = (entry_price - mark_price) * size
        (position.entry_price as i64)
            .checked_sub(market_state.mark_price as i64)
            .ok_or(ProgramError::InvalidArgument)?
            .checked_mul(position_size as i64)
            .ok_or(ProgramError::InvalidArgument)?
            .checked_div(1_000_000_000)
            .ok_or(ProgramError::InvalidAccountData)?
    };

    // Calculate effective collateral (including unrealized PnL)
    let effective_collateral = if unrealized_pnl >= 0 {
        position.collateral
            .checked_add(unrealized_pnl as u64)
            .ok_or(ProgramError::InvalidArgument)?
    } else {
        position.collateral
            .checked_sub((-unrealized_pnl) as u64)
            .unwrap_or(0)
    };

    // Check if position is liquidatable
    let collateral_ratio = if position_value > 0 {
        effective_collateral
            .checked_mul(1_000_000_000)
            .ok_or(ProgramError::InvalidArgument)?
            .checked_div(position_value)
            .ok_or(ProgramError::InvalidAccountData)?
    } else {
        u64::MAX
    };

    if collateral_ratio >= MIN_COLLATERAL_RATIO {
        msg!("Position is not liquidatable. Collateral ratio: {} >= {}", 
             collateral_ratio, MIN_COLLATERAL_RATIO);
        return Err(ProgramError::InvalidArgument);
    }

    // Calculate liquidation penalty
    let penalty_amount = position.collateral
        .checked_mul(LIQUIDATION_PENALTY)
        .ok_or(ProgramError::InvalidArgument)?
        .checked_div(1_000_000_000)
        .ok_or(ProgramError::InvalidAccountData)?;

    // Derive PDA for signing
    let (pda, bump) = Pubkey::find_program_address(&[PDA_SEED], program_id);
    let seeds = &[PDA_SEED, &[bump]];
    let signer_seeds = &[&seeds[..]];

    // Transfer liquidation reward to liquidator
    if penalty_amount > 0 {
        let transfer_ix = create_transfer_instruction(
            token_program.key,
            vault.key,
            liquidator_token_acc.key,
            &pda,
            penalty_amount,
        )?;

        invoke_signed(&transfer_ix, &[
            vault.clone(),
            liquidator_token_acc.clone(),
            vault.clone(), // PDA authority
            token_program.clone(),
        ], signer_seeds)?;
    }

    // Update market state
    market_state.open_interest = market_state.open_interest
        .checked_sub(position_size)
        .ok_or(ProgramError::InvalidArgument)?;

    // Clear the position
    position.base_amount = 0;
    position.collateral = position.collateral
        .checked_sub(penalty_amount)
        .unwrap_or(0);
    position.entry_price = 0;

    // Persist changes
    position.serialize(&mut *position_acc.data.borrow_mut())?;
    market_state.serialize(&mut *market_state_acc.data.borrow_mut())?;

    msg!("Position liquidated: penalty={}, remaining_collateral={}, ratio_was={}", 
         penalty_amount, position.collateral, collateral_ratio);
    
    Ok(())
}

// ---------------------------------------------------------------------
// 3️⃣ Close position (voluntary)
// ---------------------------------------------------------------------
pub fn close_position(program_id: &Pubkey, accounts: &[AccountInfo]) -> ProgramResult {
    // Accounts:
    // 0. [signer] user (position owner)
    // 1. [] token program
    // 2. [writable] user's token account (to receive collateral)
    // 3. [writable] vault token account (PDA‑owned)
    // 4. [writable] position account
    // 5. [writable] market state account
    let accounts_iter = &mut accounts.iter();
    let user = next_account_info(accounts_iter)?;
    let token_program = next_account_info(accounts_iter)?;
    let user_token_acc = next_account_info(accounts_iter)?;
    let vault = next_account_info(accounts_iter)?;
    let position_acc = next_account_info(accounts_iter)?;
    let market_state_acc = next_account_info(accounts_iter)?;

    if !user.is_signer {
        return Err(ProgramError::MissingRequiredSignature);
    }

    let mut market_state = MarketState::try_from_slice(&market_state_acc.data.borrow())?;
    let mut position = Position::try_from_slice(&position_acc.data.borrow())?;

    // Verify ownership
    if position.owner != *user.key {
        return Err(ProgramError::IllegalOwner);
    }

    if position.base_amount == 0 && position.collateral == 0 {
        msg!("Position already closed");
        return Ok(());
    }

    // Apply any pending funding
    let funding_delta = market_state.funding_index
        .checked_sub(position.last_funding_index)
        .ok_or(ProgramError::InvalidArgument)?;

    if funding_delta != 0 && position.base_amount != 0 {
        let funding_payment = ((position.base_amount as i128)
            .checked_mul(funding_delta as i128)
            .ok_or(ProgramError::InvalidArgument)?)
            .checked_div(1_000_000_000i128)
            .ok_or(ProgramError::InvalidAccountData)?;

        if funding_payment > 0 {
            position.collateral = position
                .collateral
                .checked_sub(funding_payment as u64)
                .unwrap_or(0);
        } else {
            position.collateral = position
                .collateral
                .checked_add((-funding_payment) as u64)
                .ok_or(ProgramError::InvalidArgument)?;
        }
    }

    // Update market state
    if position.base_amount != 0 {
        market_state.open_interest = market_state.open_interest
            .checked_sub(position.base_amount.abs() as u64)
            .ok_or(ProgramError::InvalidArgument)?;
    }

    // Transfer remaining collateral to user
    if position.collateral > 0 {
        let (pda, bump) = Pubkey::find_program_address(&[PDA_SEED], program_id);
        let seeds = &[PDA_SEED, &[bump]];
        let signer_seeds = &[&seeds[..]];

        let transfer_ix = create_transfer_instruction(
            token_program.key,
            vault.key,
            user_token_acc.key,
            &pda,
            position.collateral,
        )?;

        invoke_signed(&transfer_ix, &[
            vault.clone(),
            user_token_acc.clone(),
            vault.clone(), // PDA authority
            token_program.clone(),
        ], signer_seeds)?;
    }

    let returned_collateral = position.collateral;

    // Clear the position
    position.base_amount = 0;
    position.collateral = 0;
    position.entry_price = 0;
    position.last_funding_index = market_state.funding_index;

    // Persist changes
    position.serialize(&mut *position_acc.data.borrow_mut())?;
    market_state.serialize(&mut *market_state_acc.data.borrow_mut())?;

    msg!("Position closed: returned_collateral={}, new_open_interest={}", 
         returned_collateral, market_state.open_interest);
    
    Ok(())
}

// ---------------------------------------------------------------------
// Helper functions for testing and client integration
// ---------------------------------------------------------------------

/// Calculate position health (collateral ratio)
pub fn calculate_position_health(position: &Position, mark_price: u64) -> Result<u64, ProgramError> {
    if position.base_amount == 0 {
        return Ok(u64::MAX); // No position = perfect health
    }

    let position_value = (position.base_amount.abs() as u64)
        .checked_mul(mark_price)
        .ok_or(ProgramError::InvalidArgument)?
        .checked_div(1_000_000_000)
        .ok_or(ProgramError::InvalidAccountData)?;

    if position_value == 0 {
        return Ok(u64::MAX);
    }

    position.collateral
        .checked_mul(1_000_000_000)
        .ok_or(ProgramError::InvalidArgument)?
        .checked_div(position_value)
        .ok_or(ProgramError::InvalidAccountData)
}

/// Calculate unrealized PnL for a position
pub fn calculate_unrealized_pnl(position: &Position, mark_price: u64) -> Result<i64, ProgramError> {
    if position.base_amount == 0 {
        return Ok(0);
    }

    let position_size = position.base_amount.abs() as u64;
    
    let pnl = if position.base_amount > 0 {
        // Long position: PnL = (mark_price - entry_price) * size / 1e9
        (mark_price as i64)
            .checked_sub(position.entry_price as i64)
            .ok_or(ProgramError::InvalidArgument)?
            .checked_mul(position_size as i64)
            .ok_or(ProgramError::InvalidArgument)?
            .checked_div(1_000_000_000)
            .ok_or(ProgramError::InvalidAccountData)?
    } else {
        // Short position: PnL = (entry_price - mark_price) * size / 1e9
        (position.entry_price as i64)
            .checked_sub(mark_price as i64)
            .ok_or(ProgramError::InvalidArgument)?
            .checked_mul(position_size as i64)
            .ok_or(ProgramError::InvalidArgument)?
            .checked_div(1_000_000_000)
            .ok_or(ProgramError::InvalidAccountData)?
    };

    Ok(pnl)
}

#[cfg(test)]
mod tests;

// Re-export for testing
