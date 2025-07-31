//! # Enhanced Referral Rewarder Contract
//! 
//! This contract manages referral logic with actual reward distribution

use starknet::{ContractAddress, get_caller_address};

/// Interface for the Enhanced ReferralRewarder contract
#[starknet::interface]
pub trait IEnhancedReferralRewarder<TContractState> {
    fn register_with_referral(ref self: TContractState, referrer: ContractAddress);
    fn claim_referral_reward(ref self: TContractState, invitee: ContractAddress, hunt_id: u64);
    fn get_referrer(self: @TContractState, invitee: ContractAddress) -> ContractAddress;
    fn has_claimed_reward(self: @TContractState, referrer: ContractAddress, invitee: ContractAddress) -> bool;
    fn get_required_completions(self: @TContractState) -> u64;
    fn set_challenge_manager(ref self: TContractState, address: ContractAddress);
    fn set_required_completions(ref self: TContractState, count: u64);
    
    // New reward-related functions
    fn set_reward_token(ref self: TContractState, token_address: ContractAddress);
    fn set_reward_amount(ref self: TContractState, amount: u256);
    fn fund_contract(ref self: TContractState, amount: u256);
    fn withdraw_funds(ref self: TContractState, amount: u256);
    fn get_reward_amount(self: @TContractState) -> u256;
    fn get_contract_balance(self: @TContractState) -> u256;
}

#[starknet::contract]
pub mod EnhancedReferralRewarder {
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp, Zeroable};
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::access::accesscontrol::interface::{IAccessControl};
    use openzeppelin::access::accesscontrol::DEFAULT_ADMIN_ROLE;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use nft_scavenger_hunt::challenge_manager::{IChallengeManagerDispatcher, IChallengeManagerDispatcherTrait};
    use starknet::storage::{Map, StoragePointerReadAccess, StoragePointerWriteAccess, StoragePathEntry, Vec, VecTrait, MutableVecTrait};

    component!(path: AccessControlComponent, storage: access_control, event: AccessControlEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    // Component implementations
    #[abi(embed_v0)]
    impl AccessControlImpl = AccessControlComponent::AccessControlImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;
    
    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;

    // Constants for roles
    const ADMIN_ROLE: felt252 = 'ADMIN_ROLE';

    #[storage]
    struct Storage {
        #[substorage(v0)]
        access_control: AccessControlComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        
        // Existing storage
        challenge_manager: ContractAddress,
        invitee_to_referrer: Map<ContractAddress, ContractAddress>,
        is_registered: Map<ContractAddress, bool>,
        referral_reward_claimed: Map<(ContractAddress, ContractAddress), bool>,
        required_completions: u64,
        
        // New reward-related storage
        reward_token: ContractAddress,  // ERC20 token address for rewards
        reward_amount: u256,            // Amount of tokens to reward per referral
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        UserRegisteredWithReferrer: UserRegisteredWithReferrer,
        ReferralCompleted: ReferralCompleted,
        RewardDistributed: RewardDistributed,
        RewardTokenSet: RewardTokenSet,
        RewardAmountSet: RewardAmountSet,
        ContractFunded: ContractFunded,
        FundsWithdrawn: FundsWithdrawn,
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct UserRegisteredWithReferrer {
        invitee: ContractAddress,
        referrer: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct ReferralCompleted {
        referrer: ContractAddress,
        invitee: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct RewardDistributed {
        referrer: ContractAddress,
        invitee: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct RewardTokenSet {
        token_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct RewardAmountSet {
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct ContractFunded {
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct FundsWithdrawn {
        amount: u256,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, 
        admin: ContractAddress, 
        challenge_manager_address: ContractAddress,
        reward_token_address: ContractAddress,
        reward_amount: u256
    ) {
        // Initialize components
        // self.src5.initializer();
        self.access_control.initializer();
        
        // Grant admin role
        self.access_control._grant_role(ADMIN_ROLE, admin);
        
        // Set initial values
        self.challenge_manager.write(challenge_manager_address);
        self.required_completions.write(3);
        self.reward_token.write(reward_token_address);
        self.reward_amount.write(reward_amount);
    }

    #[abi(embed_v0)]
    impl EnhancedReferralRewarderImpl of super::IEnhancedReferralRewarder<ContractState> {
        fn register_with_referral(ref self: ContractState, referrer: ContractAddress) {
            let invitee = get_caller_address();
            assert(!self.is_registered.read(invitee), 'User already has a referrer');
            assert(!referrer.is_zero(), 'Referrer cannot be zero address');
            assert(invitee != referrer, 'Cannot refer yourself');

            self.invitee_to_referrer.write(invitee, referrer);
            self.is_registered.write(invitee, true);

            self.emit(UserRegisteredWithReferrer { invitee, referrer });
        }

        fn claim_referral_reward(ref self: ContractState, invitee: ContractAddress, hunt_id: u64) {
            let referrer = get_caller_address();
            let stored_referrer = self.invitee_to_referrer.read(invitee);
            assert(stored_referrer == referrer, 'You are not the referrer');
            assert(!stored_referrer.is_zero(), 'No referral record found');
            assert(!self.referral_reward_claimed.read((referrer, invitee)), 'Reward already claimed');

            // Verify puzzle completions
            let cm_address = self.challenge_manager.read();
            let challenge_manager_dispatcher = IChallengeManagerDispatcher {
                contract_address: cm_address
            };

            let completed_challenges = challenge_manager_dispatcher
                .get_user_completed_challenges(invitee, hunt_id);
            let completion_count: u64 = completed_challenges.len().into();
            let required_count = self.required_completions.read();

            assert!(completion_count >= required_count, "Invitee has not completed enough puzzles");

            // Mark reward as claimed
            self.referral_reward_claimed.write((referrer, invitee), true);

            // Distribute actual reward
            let reward_amount = self.reward_amount.read();
            let reward_token_address = self.reward_token.read();
            
            if !reward_token_address.is_zero() && reward_amount > 0 {
                let reward_token = IERC20Dispatcher { contract_address: reward_token_address };
                
                // Check contract has sufficient balance
                let contract_balance = reward_token.balance_of(starknet::get_contract_address());
                assert(contract_balance >= reward_amount, 'Insufficient contract balance');
                
                // Transfer reward to referrer
                let success = reward_token.transfer(referrer, reward_amount);
                assert(success, 'Reward transfer failed');
                
                self.emit(RewardDistributed { referrer, invitee, amount: reward_amount });
            }

            self.emit(ReferralCompleted { referrer, invitee });
        }

        fn get_referrer(self: @ContractState, invitee: ContractAddress) -> ContractAddress {
            self.invitee_to_referrer.read(invitee)
        }

        fn has_claimed_reward(
            self: @ContractState, referrer: ContractAddress, invitee: ContractAddress
        ) -> bool {
            self.referral_reward_claimed.read((referrer, invitee))
        }

        fn get_required_completions(self: @ContractState) -> u64 {
            self.required_completions.read()
        }

        fn set_challenge_manager(ref self: ContractState, address: ContractAddress) {
            self.access_control.assert_only_role(ADMIN_ROLE);
            self.challenge_manager.write(address);
        }

        fn set_required_completions(ref self: ContractState, count: u64) {
            self.access_control.assert_only_role(ADMIN_ROLE);
            self.required_completions.write(count);
        }

        // New reward-related functions
        fn set_reward_token(ref self: ContractState, token_address: ContractAddress) {
            self.access_control.assert_only_role(ADMIN_ROLE);
            self.reward_token.write(token_address);
            self.emit(RewardTokenSet { token_address });
        }

        fn set_reward_amount(ref self: ContractState, amount: u256) {
            self.access_control.assert_only_role(ADMIN_ROLE);
            self.reward_amount.write(amount);
            self.emit(RewardAmountSet { amount });
        }

        fn fund_contract(ref self: ContractState, amount: u256) {
            self.access_control.assert_only_role(ADMIN_ROLE);
            let reward_token_address = self.reward_token.read();
            assert(!reward_token_address.is_zero(), 'Reward token not set');
            
            let reward_token = IERC20Dispatcher { contract_address: reward_token_address };
            let caller = get_caller_address();
            let contract_address = starknet::get_contract_address();
            
            let success = reward_token.transfer_from(caller, contract_address, amount);
            assert(success, 'Funding transfer failed');
            
            self.emit(ContractFunded { amount });
        }

        fn withdraw_funds(ref self: ContractState, amount: u256) {
            self.access_control.assert_only_role(ADMIN_ROLE);
            let reward_token_address = self.reward_token.read();
            assert(!reward_token_address.is_zero(), 'Reward token not set');
            
            let reward_token = IERC20Dispatcher { contract_address: reward_token_address };
            let caller = get_caller_address();
            
            let success = reward_token.transfer(caller, amount);
            assert(success, 'Withdrawal transfer failed');
            
            self.emit(FundsWithdrawn { amount });
        }

        fn get_reward_amount(self: @ContractState) -> u256 {
            self.reward_amount.read()
        }

        fn get_contract_balance(self: @ContractState) -> u256 {
            let reward_token_address = self.reward_token.read();
            if reward_token_address.is_zero() {
                return 0;
            }
            
            let reward_token = IERC20Dispatcher { contract_address: reward_token_address };
            reward_token.balance_of(starknet::get_contract_address())
        }
    }
}