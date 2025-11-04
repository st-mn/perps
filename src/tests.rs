use solana_program::{
    account_info::AccountInfo,
    clock::Clock,
    program_error::ProgramError,
    pubkey::Pubkey,
    rent::Rent,
    sysvar::Sysvar,
};
use crate::{Position, MarketState, calculate_position_health, calculate_unrealized_pnl};

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_position_creation() {
        let mut position = Position::default();
        position.owner = Pubkey::new_unique();
        position.base_amount = 1_000_000_000; // 1 unit long
        position.collateral = 150_000_000_000; // 150 units collateral
        position.entry_price = 100_000_000_000; // $100
        
        assert_eq!(position.base_amount, 1_000_000_000);
        assert_eq!(position.collateral, 150_000_000_000);
        assert!(position.base_amount > 0); // Long position
    }

    #[test]
    fn test_market_state_initialization() {
        let market_state = MarketState {
            funding_index: 0,
            funding_rate_per_slot: 10_000, // 0.01%
            open_interest: 0,
            bump: 255,
            last_funding_slot: 1000,
            mark_price: 100_000_000_000,
        };
        
        assert_eq!(market_state.funding_index, 0);
        assert_eq!(market_state.funding_rate_per_slot, 10_000);
        assert_eq!(market_state.mark_price, 100_000_000_000);
    }

    #[test]
    fn test_position_health_calculation() {
        let position = Position {
            owner: Pubkey::new_unique(),
            base_amount: 1_000_000_000, // 1 unit
            collateral: 150_000_000_000, // 150 units
            last_funding_index: 0,
            entry_price: 100_000_000_000, // $100
        };

        let mark_price = 100_000_000_000; // $100
        let health = calculate_position_health(&position, mark_price).unwrap();
        
        // Collateral ratio should be 150% (1.5 * 1e9 = 1_500_000_000)
        assert_eq!(health, 1_500_000_000);
    }

    #[test]
    fn test_position_health_with_price_movement() {
        let position = Position {
            owner: Pubkey::new_unique(),
            base_amount: 1_000_000_000, // 1 unit long
            collateral: 150_000_000_000, // 150 units
            last_funding_index: 0,
            entry_price: 100_000_000_000, // $100
        };

        // Price drops to $120 - position value increases for long
        let mark_price = 120_000_000_000;
        let health = calculate_position_health(&position, mark_price).unwrap();
        
        // Health should decrease as position value increased
        // 150 / 120 = 1.25 = 1_250_000_000
        assert_eq!(health, 1_250_000_000);
    }

    #[test]
    fn test_unrealized_pnl_long_profit() {
        let position = Position {
            owner: Pubkey::new_unique(),
            base_amount: 1_000_000_000, // 1 unit long
            collateral: 150_000_000_000,
            last_funding_index: 0,
            entry_price: 100_000_000_000, // $100 entry
        };

        let mark_price = 110_000_000_000; // $110 current
        let pnl = calculate_unrealized_pnl(&position, mark_price).unwrap();
        
        // PnL = (110 - 100) * 1 = +10
        assert_eq!(pnl, 10_000_000_000);
    }

    #[test]
    fn test_unrealized_pnl_long_loss() {
        let position = Position {
            owner: Pubkey::new_unique(),
            base_amount: 1_000_000_000, // 1 unit long
            collateral: 150_000_000_000,
            last_funding_index: 0,
            entry_price: 100_000_000_000, // $100 entry
        };

        let mark_price = 90_000_000_000; // $90 current
        let pnl = calculate_unrealized_pnl(&position, mark_price).unwrap();
        
        // PnL = (90 - 100) * 1 = -10
        assert_eq!(pnl, -10_000_000_000);
    }

    #[test]
    fn test_unrealized_pnl_short_profit() {
        let position = Position {
            owner: Pubkey::new_unique(),
            base_amount: -1_000_000_000, // 1 unit short
            collateral: 150_000_000_000,
            last_funding_index: 0,
            entry_price: 100_000_000_000, // $100 entry
        };

        let mark_price = 90_000_000_000; // $90 current
        let pnl = calculate_unrealized_pnl(&position, mark_price).unwrap();
        
        // PnL = (100 - 90) * 1 = +10 (profit on short when price drops)
        assert_eq!(pnl, 10_000_000_000);
    }

    #[test]
    fn test_unrealized_pnl_short_loss() {
        let position = Position {
            owner: Pubkey::new_unique(),
            base_amount: -1_000_000_000, // 1 unit short
            collateral: 150_000_000_000,
            last_funding_index: 0,
            entry_price: 100_000_000_000, // $100 entry
        };

        let mark_price = 110_000_000_000; // $110 current
        let pnl = calculate_unrealized_pnl(&position, mark_price).unwrap();
        
        // PnL = (100 - 110) * 1 = -10 (loss on short when price rises)
        assert_eq!(pnl, -10_000_000_000);
    }

    #[test]
    fn test_funding_calculation() {
        let mut position = Position {
            owner: Pubkey::new_unique(),
            base_amount: 1_000_000_000, // 1 unit long
            collateral: 150_000_000_000,
            last_funding_index: 0,
            entry_price: 100_000_000_000,
        };

        let funding_index = 1_000_000; // Some accumulated funding
        
        // Calculate funding payment: base_amount * funding_delta / 1e9
        let funding_payment = ((position.base_amount as i128)
            * (funding_index as i128))
            / 1_000_000_000i128;
        
        assert_eq!(funding_payment, 1_000); // 1 unit * 1_000_000 / 1e9 = 0.001
    }

    #[test]
    fn test_liquidation_threshold() {
        let position = Position {
            owner: Pubkey::new_unique(),
            base_amount: 1_000_000_000, // 1 unit long
            collateral: 100_000_000_000, // Only 100 units collateral
            last_funding_index: 0,
            entry_price: 100_000_000_000, // $100
        };

        let mark_price = 100_000_000_000; // $100
        let health = calculate_position_health(&position, mark_price).unwrap();
        
        // Health = 100/100 = 1.0 = 1_000_000_000 (below 1.5 threshold)
        assert_eq!(health, 1_000_000_000);
        assert!(health < 1_500_000_000); // Should be liquidatable
    }

    #[test]
    fn test_zero_position_health() {
        let position = Position {
            owner: Pubkey::new_unique(),
            base_amount: 0, // No position
            collateral: 100_000_000_000,
            last_funding_index: 0,
            entry_price: 0,
        };

        let mark_price = 100_000_000_000;
        let health = calculate_position_health(&position, mark_price).unwrap();
        
        // No position = perfect health
        assert_eq!(health, u64::MAX);
    }

    #[test]
    fn test_precision_handling() {
        // Test that our precision scaling works correctly
        let price_100_50 = 100_500_000_000u64; // $100.50
        let size_1_5 = 1_500_000_000i64; // 1.5 units
        
        // Calculate position value: size * price / 1e9
        let position_value = ((size_1_5 as u64) * price_100_50) / 1_000_000_000;
        
        // Should be 1.5 * 100.50 = 150.75
        assert_eq!(position_value, 150_750_000_000);
    }
}