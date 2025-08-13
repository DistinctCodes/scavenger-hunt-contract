// src/nft_rewards.cairo

//! # NFT Rewards Contract
//! 
//! This contract manages upgradeable NFT rewards for scavenger hunt completions.
//! NFTs can be upgraded from Bronze to Silver to Gold based on user achievements.
//! 
//! ## Features
//! 
//! - Mint NFT rewards for hunt completions
//! - Track and upgrade NFT levels (Bronze, Silver, Gold)
//! - Backend-controlled upgrade system
//! - Event emission for level changes

#[starknet::contract]
mod NFTRewards {
    use starknet::{ContractAddress, get_caller_address};
    use core::traits::Into;
    use core::option::OptionTrait;
    use core::array::ArrayTrait;
    use openzeppelin::access::accesscontrol::AccessControl;
    use openzeppelin::token::erc721::ERC721Component;
    use openzeppelin::introspection::src5::SRC5Component;

    component!(path: ERC721Component, storage: erc721, event: ERC721Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    // ERC721 Mixin
    #[abi(embed_v0)]
    impl ERC721MixinImpl = ERC721Component::ERC721MixinImpl<ContractState>;
    impl ERC721InternalImpl = ERC721Component::InternalImpl<ContractState>;

    // Constants for roles
    const ADMIN_ROLE: felt252 = 'ADMIN_ROLE';
    const BACKEND_ROLE: felt252 = 'BACKEND_ROLE';
    const MINTER_ROLE: felt252 = 'MINTER_ROLE';

    // NFT Level enum
    #[derive(Drop, Serde, Copy, PartialEq)]
    enum NFTLevel {
        Bronze,
        Silver, 
        Gold,
    }

    impl NFTLevelIntoU8 of Into<NFTLevel, u8> {
        fn into(self: NFTLevel) -> u8 {
            match self {
                NFTLevel::Bronze => 1,
                NFTLevel::Silver => 2,
                NFTLevel::Gold => 3,
            }
        }
    }

    impl U8IntoNFTLevel of Into<u8, NFTLevel> {
        fn into(self: u8) -> NFTLevel {
            if self == 1 {
                NFTLevel::Bronze
            } else if self == 2 {
                NFTLevel::Silver
            } else {
                NFTLevel::Gold
            }
        }
    }

    // Storage for the contract
    #[storage]
    struct Storage {
        // Access control storage
        #[substorage(v0)]
        access_control: AccessControl::Storage,
        
        // ERC721 storage
        #[substorage(v0)]
        erc721: ERC721Component::Storage,
        
        // SRC5 storage
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        
        // NFT upgrade tracking
        token_levels: Map<u256, u8>, // token_id -> level (1=Bronze, 2=Silver, 3=Gold)
        next_token_id: u256,
        
        // Hunt completion tracking for upgrades
        user_hunt_completions: Map<ContractAddress, u64>, // user -> total hunt completions
        user_tokens: Map<ContractAddress, Array<u256>>, // user -> owned token IDs
    }

    // Events
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        NFTMinted: NFTMinted,
        NFTUpgraded: NFTUpgraded,
        #[flat]
        AccessControlEvent: AccessControl::Event,
        #[flat]
        ERC721Event: ERC721Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct NFTMinted {
        token_id: u256,
        recipient: ContractAddress,
        level: u8,
    }

    #[derive(Drop, starknet::Event)]
    struct NFTUpgraded {
        token_id: u256,
        new_level: u8,
    }

    // Constructor
    #[constructor]
    fn constructor(
        ref self: ContractState,
        admin: ContractAddress,
        backend: ContractAddress,
        name: ByteArray,
        symbol: ByteArray,
        base_uri: ByteArray
    ) {
        // Initialize access control
        self.access_control.initializer();
        
        // Initialize ERC721
        self.erc721.initializer(name, symbol, base_uri);
        
        // Grant roles
        self.access_control._grant_role(ADMIN_ROLE, admin);
        self.access_control._grant_role(BACKEND_ROLE, backend);
        self.access_control._grant_role(MINTER_ROLE, backend);
        
        // Initialize token counter
        self.next_token_id.write(1);
    }

    // External functions
    #[external(v0)]
    impl NFTRewardsImpl of super::INFTRewards<ContractState> {
        /// Mints a new NFT reward for hunt completion
        /// 
        /// # Arguments
        /// 
        /// * `recipient` - Address to receive the NFT
        /// * `hunt_id` - ID of the completed hunt
        /// 
        /// # Returns
        /// 
        /// * `u256` - Token ID of the minted NFT
        fn mint_reward(
            ref self: ContractState,
            recipient: ContractAddress,
            hunt_id: u64
        ) -> u256 {
            // Only backend or admin can mint
            self.assert_only_role(MINTER_ROLE);
            
            let token_id = self.next_token_id.read();
            
            // Mint the NFT (starts at Bronze level)
            self.erc721._mint(recipient, token_id);
            self.token_levels.write(token_id, NFTLevel::Bronze.into());
            
            // Update user's hunt completions
            let current_completions = self.user_hunt_completions.read(recipient);
            self.user_hunt_completions.write(recipient, current_completions + 1);
            
            // Add to user's token list
            let mut user_tokens = self.user_tokens.read(recipient);
            user_tokens.append(token_id);
            self.user_tokens.write(recipient, user_tokens);
            
            // Increment token counter
            self.next_token_id.write(token_id + 1);
            
            // Emit event
            self.emit(Event::NFTMinted(
                NFTMinted {
                    token_id: token_id,
                    recipient: recipient,
                    level: NFTLevel::Bronze.into(),
                }
            ));
            
            token_id
        }
        
        /// Upgrades an NFT to the next level
        /// 
        /// # Arguments
        /// 
        /// * `token_id` - ID of the token to upgrade
        fn upgrade_nft(ref self: ContractState, token_id: u256) {
            // Only backend can upgrade NFTs
            self.assert_only_role(BACKEND_ROLE);
            
            // Verify token exists
            let owner = self.erc721.owner_of(token_id);
            assert(!owner.is_zero(), 'Token does not exist');
            
            // Get current level
            let current_level_u8 = self.token_levels.read(token_id);
            let current_level: NFTLevel = current_level_u8.into();
            
            // Determine new level
            let new_level = match current_level {
                NFTLevel::Bronze => NFTLevel::Silver,
                NFTLevel::Silver => NFTLevel::Gold,
                NFTLevel::Gold => {
                    // Already at max level
                    assert(false, 'Already at maximum level');
                    NFTLevel::Gold // This won't be reached
                },
            };
            
            // Update level
            self.token_levels.write(token_id, new_level.into());
            
            // Emit event
            self.emit(Event::NFTUpgraded(
                NFTUpgraded {
                    token_id: token_id,
                    new_level: new_level.into(),
                }
            ));
        }
        
        /// Gets the level of an NFT
        /// 
        /// # Arguments
        /// 
        /// * `token_id` - ID of the token
        /// 
        /// # Returns
        /// 
        /// * `u8` - Level of the NFT (1=Bronze, 2=Silver, 3=Gold)
        fn get_nft_level(self: @ContractState, token_id: u256) -> u8 {
            self.token_levels.read(token_id)
        }
        
        /// Gets the level of an NFT as enum
        /// 
        /// # Arguments
        /// 
        /// * `token_id` - ID of the token
        /// 
        /// # Returns
        /// 
        /// * `NFTLevel` - Level enum of the NFT
        fn get_nft_level_enum(self: @ContractState, token_id: u256) -> NFTLevel {
            let level_u8 = self.token_levels.read(token_id);
            level_u8.into()
        }
        
        /// Gets all tokens owned by a user
        /// 
        /// # Arguments
        /// 
        /// * `user` - Address of the user
        /// 
        /// # Returns
        /// 
        /// * `Array<u256>` - Array of token IDs owned by the user
        fn get_user_tokens(self: @ContractState, user: ContractAddress) -> Array<u256> {
            self.user_tokens.read(user)
        }
        
        /// Gets user's total hunt completions
        /// 
        /// # Arguments
        /// 
        /// * `user` - Address of the user
        /// 
        /// # Returns
        /// 
        /// * `u64` - Total number of hunt completions
        fn get_user_hunt_completions(self: @ContractState, user: ContractAddress) -> u64 {
            self.user_hunt_completions.read(user)
        }
        
        /// Checks if an NFT can be upgraded
        /// 
        /// # Arguments
        /// 
        /// * `token_id` - ID of the token
        /// 
        /// # Returns
        /// 
        /// * `bool` - True if the NFT can be upgraded
        fn can_upgrade(self: @ContractState, token_id: u256) -> bool {
            let current_level_u8 = self.token_levels.read(token_id);
            current_level_u8 < NFTLevel::Gold.into()
        }
        
        /// Gets the next token ID that will be minted
        /// 
        /// # Returns
        /// 
        /// * `u256` - Next token ID
        fn get_next_token_id(self: @ContractState) -> u256 {
            self.next_token_id.read()
        }
        
        /// Grants backend role to an address (admin only)
        /// 
        /// # Arguments
        /// 
        /// * `account` - Address to grant backend role
        fn grant_backend_role(ref self: ContractState, account: ContractAddress) {
            self.assert_only_role(ADMIN_ROLE);
            self.access_control._grant_role(BACKEND_ROLE, account);
            self.access_control._grant_role(MINTER_ROLE, account);
        }
        
        /// Revokes backend role from an address (admin only)
        /// 
        /// # Arguments
        /// 
        /// * `account` - Address to revoke backend role from
        fn revoke_backend_role(ref self: ContractState, account: ContractAddress) {
            self.assert_only_role(ADMIN_ROLE);
            self.access_control._revoke_role(BACKEND_ROLE, account);
            self.access_control._revoke_role(MINTER_ROLE, account);
        }
        
        /// Checks if an address has backend role
        /// 
        /// # Arguments
        /// 
        /// * `account` - Address to check
        /// 
        /// # Returns
        /// 
        /// * `bool` - True if the address has backend role
        fn has_backend_role(self: @ContractState, account: ContractAddress) -> bool {
            self.access_control.has_role(BACKEND_ROLE, account)
        }
    }

    // Internal functions
    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        /// Asserts that the caller has a specific role
        /// 
        /// # Arguments
        /// 
        /// * `role` - Role to check
        fn assert_only_role(self: @ContractState, role: felt252) {
            let caller = get_caller_address();
            assert(self.access_control.has_role(role, caller), 'Caller does not have role');
        }
    }
}

/// Interface for the NFTRewards contract
#[starknet::interface]
trait INFTRewards<TContractState> {
    fn mint_reward(ref self: TContractState, recipient: ContractAddress, hunt_id: u64) -> u256;
    fn upgrade_nft(ref self: TContractState, token_id: u256);
    fn get_nft_level(self: @TContractState, token_id: u256) -> u8;
    fn get_nft_level_enum(self: @TContractState, token_id: u256) -> NFTRewards::NFTLevel;
    fn get_user_tokens(self: @TContractState, user: ContractAddress) -> Array<u256>;
    fn get_user_hunt_completions(self: @TContractState, user: ContractAddress) -> u64;
    fn can_upgrade(self: @TContractState, token_id: u256) -> bool;
    fn get_next_token_id(self: @TContractState) -> u256;
    fn grant_backend_role(ref self: TContractState, account: ContractAddress);
    fn revoke_backend_role(ref self: TContractState, account: ContractAddress);
    fn has_backend_role(self: @TContractState, account: ContractAddress) -> bool;
}