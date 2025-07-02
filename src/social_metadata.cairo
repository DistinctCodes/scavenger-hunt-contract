//! # Social Metadata Contract
//! 
//! This contract manages on-chain metadata for hunts, challenges, and user achievements.
//! It provides functionality for social sharing of achievements and progress.
//! 
//! ## Features
//! 
//! - Store and retrieve on-chain metadata for hunts and challenges
//! - Generate shareable content for social media platforms
//! - Track user achievements and progress
//! - Support for customizable social sharing templates

#[starknet::contract]
mod SocialMetadata {
    use starknet::{ContractAddress, get_caller_address};
    use core::traits::Into;
    use core::option::OptionTrait;
    use core::array::ArrayTrait;
    use core::array::SpanTrait;
    use core::integer::BoundedInt;
    use openzeppelin::access::accesscontrol::AccessControl;
    use nft_scavenger_hunt::hunt_factory::{IHuntFactoryDispatcher, IHuntFactoryDispatcherTrait};
    use nft_scavenger_hunt::challenge_manager::{IChallengeManagerDispatcher, IChallengeManagerDispatcherTrait};
    use nft_scavenger_hunt::leaderboard::{ILeaderboardDispatcher, ILeaderboardDispatcherTrait};

    // Constants for roles
    const ADMIN_ROLE: felt252 = 'ADMIN_ROLE';
    const MODERATOR_ROLE: felt252 = 'MODERATOR_ROLE';
    const HUNT_FACTORY_ROLE: felt252 = 'HUNT_FACTORY_ROLE';
    const CHALLENGE_MANAGER_ROLE: felt252 = 'CHALLENGE_MANAGER_ROLE';

    // Storage for the contract
    #[storage]
    struct Storage {
        // Access control storage
        #[substorage(v0)]
        access_control: AccessControl::Storage,
        
        // Contract addresses
        hunt_factory: ContractAddress,
        challenge_manager: ContractAddress,
        leaderboard: ContractAddress,
        
        // Hunt metadata
        hunt_descriptions: LegacyMap<u64, felt252>,
        hunt_images: LegacyMap<u64, felt252>,
        hunt_external_urls: LegacyMap<u64, felt252>,
        
        // Challenge metadata
        challenge_descriptions: LegacyMap<(u64, u64), felt252>,
        challenge_images: LegacyMap<(u64, u64), felt252>,
        
        // User achievement metadata
        user_achievements: LegacyMap<(ContractAddress, u64), Array<felt252>>,
        
        // Social sharing templates
        hunt_completion_template: felt252,
        challenge_completion_template: felt252,
        leaderboard_position_template: felt252,
        
        // Base URL for sharing
        base_sharing_url: felt252,
    }

    // ... rest of the SocialMetadata implementation from the original file
    // (I'll include the key structs and events here)

    // Metadata struct for hunts
    #[derive(Drop, Serde)]
    struct HuntMetadata {
        id: u64,
        name: felt252,
        description: felt252,
        image_url: felt252,
        external_url: felt252,
        start_time: u64,
        end_time: u64,
        total_challenges: u64,
    }

    // Social sharing content struct
    #[derive(Drop, Serde)]
    struct SocialShareContent {
        title: felt252,
        description: felt252,
        image_url: felt252,
        share_url: felt252,
    }

    // Events
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        HuntMetadataUpdated: HuntMetadataUpdated,
        ChallengeMetadataUpdated: ChallengeMetadataUpdated,
        UserAchievementAdded: UserAchievementAdded,
        SharingTemplateUpdated: SharingTemplateUpdated,
        #[flat]
        AccessControlEvent: AccessControl::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct HuntMetadataUpdated {
        hunt_id: u64,
        description: felt252,
        image_url: felt252,
        external_url: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct ChallengeMetadataUpdated {
        hunt_id: u64,
        challenge_id: u64,
        description: felt252,
        image_url: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct UserAchievementAdded {
        user: ContractAddress,
        hunt_id: u64,
        challenge_id: u64,
        achievement_text: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct SharingTemplateUpdated {
        template_type: felt252,
        template: felt252,
    }

    // Constructor
    #[constructor]
    fn constructor(ref self: ContractState, admin: ContractAddress) {
        // Initialize access control
        self.access_control.initializer();
        
        // Grant admin role to the specified admin
        self.access_control._grant_role(ADMIN_ROLE, admin);
        
        // Set default sharing templates
        self.hunt_completion_template.write('I completed the {hunt_name} scavenger hunt!');
        self.challenge_completion_template.write('I solved the {challenge_name} challenge in {hunt_name}!');
        self.leaderboard_position_template.write('I\'m ranked #{position} in the {hunt_name} leaderboard!');
        
        // Set default base sharing URL
        self.base_sharing_url.write('https://scavengerhunt.io/share');
    }

    // External functions implementation would continue here...
    // (The rest of the SocialMetadata implementation from the original file)
}

/// Interface for the SocialMetadata contract
#[starknet::interface]
trait ISocialMetadata<TContractState> {
    fn set_hunt_factory(ref self: TContractState, hunt_factory_address: ContractAddress);
    fn set_challenge_manager(ref self: TContractState, challenge_manager_address: ContractAddress);
    fn set_leaderboard(ref self: TContractState, leaderboard_address: ContractAddress);
    
    fn update_hunt_metadata(
        ref self: TContractState,
        hunt_id: u64,
        description: felt252,
        image_url: felt252,
        external_url: felt252
    );
    
    fn get_hunt_metadata(self: @TContractState, hunt_id: u64) -> SocialMetadata::HuntMetadata;
    
    fn generate_hunt_completion_share(
        self: @TContractState,
        user: ContractAddress,
        hunt_id: u64
    ) -> SocialMetadata::SocialShareContent;
}