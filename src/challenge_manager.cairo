... shell ...

```cairo file="src/social_metadata.cairo"
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

    // Metadata struct for challenges
    #[derive(Drop, Serde)]
    struct ChallengeMetadata {
        id: u64,
        hunt_id: u64,
        question: felt252,
        description: felt252,
        image_url: felt252,
        points: u64,
    }

    // Metadata struct for user achievements
    #[derive(Drop, Serde)]
    struct UserAchievement {
        user: ContractAddress,
        hunt_id: u64,
        challenge_id: u64,
        timestamp: u64,
        achievement_text: felt252,
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

    // Contract functions
    #[external(v0)]
    impl SocialMetadataImpl of super::ISocialMetadata<ContractState> {
        /// Sets the hunt factory contract address
        /// 
        /// # Arguments
        /// 
        /// * `hunt_factory_address` - Address of the HuntFactory contract
        fn set_hunt_factory(ref self: ContractState, hunt_factory_address: ContractAddress) {
            // Only admin can set the hunt factory
            self.assert_only_role(ADMIN_ROLE);
            self.hunt_factory.write(hunt_factory_address);
            
            // Grant hunt factory role to the contract
            self.access_control._grant_role(HUNT_FACTORY_ROLE, hunt_factory_address);
        }
        
        /// Sets the challenge manager contract address
        /// 
        /// # Arguments
        /// 
        /// * `challenge_manager_address` - Address of the ChallengeManager contract
        fn set_challenge_manager(ref self: ContractState, challenge_manager_address: ContractAddress) {
            // Only admin can set the challenge manager
            self.assert_only_role(ADMIN_ROLE);
            self.challenge_manager.write(challenge_manager_address);
            
            // Grant challenge manager role to the contract
            self.access_control._grant_role(CHALLENGE_MANAGER_ROLE, challenge_manager_address);
        }
        
        /// Sets the leaderboard contract address
        /// 
        /// # Arguments
        /// 
        /// * `leaderboard_address` - Address of the Leaderboard contract
        fn set_leaderboard(ref self: ContractState, leaderboard_address: ContractAddress) {
            // Only admin can set the leaderboard
            self.assert_only_role(ADMIN_ROLE);
            self.leaderboard.write(leaderboard_address);
        }
        
        /// Sets the base sharing URL
        /// 
        /// # Arguments
        /// 
        /// * `base_url` - Base URL for sharing links
        fn set_base_sharing_url(ref self: ContractState, base_url: felt252) {
            // Only admin can set the base sharing URL
            self.assert_only_role(ADMIN_ROLE);
            self.base_sharing_url.write(base_url);
        }
        
        /// Updates metadata for a hunt
        /// 
        /// # Arguments
        /// 
        /// * `hunt_id` - ID of the hunt
        /// * `description` - Description of the hunt
        /// * `image_url` - URL of the hunt image
        /// * `external_url` - External URL for the hunt
        fn update_hunt_metadata(
            ref self: ContractState,
            hunt_id: u64,
            description: felt252,
            image_url: felt252,
            external_url: felt252
        ) {
            // Get caller address
            let caller = get_caller_address();
            
            // Get hunt factory dispatcher
            let hunt_factory_address = self.hunt_factory.read();
            assert(hunt_factory_address != starknet::contract_address_const::&lt;0>(), 'Hunt factory not set');
            let hunt_factory = IHuntFactoryDispatcher { contract_address: hunt_factory_address };
            
            // Get the hunt to verify ownership
            let hunt = hunt_factory.get_hunt(hunt_id);
            
            // Ensure only the hunt creator or an admin/moderator can update metadata
            assert(
                caller == hunt.admin || 
                self.access_control.has_role(ADMIN_ROLE, caller) || 
                self.access_control.has_role(MODERATOR_ROLE, caller),
                'Not authorized to update metadata'
            );
            
            // Update hunt metadata
            self.hunt_descriptions.write(hunt_id, description);
            self.hunt_images.write(hunt_id, image_url);
            self.hunt_external_urls.write(hunt_id, external_url);
            
            // Emit event
            self.emit(Event::HuntMetadataUpdated(
                HuntMetadataUpdated {
                    hunt_id: hunt_id,
                    description: description,
                    image_url: image_url,
                    external_url: external_url,
                }
            ));
        }
        
        /// Updates metadata for a challenge
        /// 
        /// # Arguments
        /// 
        /// * `hunt_id` - ID of the hunt
        /// * `challenge_id` - ID of the challenge
        /// * `description` - Description of the challenge
        /// * `image_url` - URL of the challenge image
        fn update_challenge_metadata(
            ref self: ContractState,
            hunt_id: u64,
            challenge_id: u64,
            description: felt252,
            image_url: felt252
        ) {
            // Get caller address
            let caller = get_caller_address();
            
            // Get hunt factory dispatcher
            let hunt_factory_address = self.hunt_factory.read();
            assert(hunt_factory_address != starknet::contract_address_const::&lt;0>(), 'Hunt factory not set');
            let hunt_factory = IHuntFactoryDispatcher { contract_address: hunt_factory_address };
            
            // Get the hunt to verify ownership
            let hunt = hunt_factory.get_hunt(hunt_id);
            
            // Ensure only the hunt creator or an admin/moderator can update metadata
            assert(
                caller == hunt.admin || 
                self.access_control.has_role(ADMIN_ROLE, caller) || 
                self.access_control.has_role(MODERATOR_ROLE, caller),
                'Not authorized to update metadata'
            );
            
            // Update challenge metadata
            self.challenge_descriptions.write((hunt_id, challenge_id), description);
            self.challenge_images.write((hunt_id, challenge_id), image_url);
            
            // Emit event
            self.emit(Event::ChallengeMetadataUpdated(
                ChallengeMetadataUpdated {
                    hunt_id: hunt_id,
                    challenge_id: challenge_id,
                    description: description,
                    image_url: image_url,
                }
            ));
        }
        
        /// Adds an achievement for a user
        /// 
        /// # Arguments
        /// 
        /// * `user` - Address of the user
        /// * `hunt_id` - ID of the hunt
        /// * `challenge_id` - ID of the challenge
        /// * `achievement_text` - Text describing the achievement
        fn add_user_achievement(
            ref self: ContractState,
            user: ContractAddress,
            hunt_id: u64,
            challenge_id: u64,
            achievement_text: felt252
        ) {
            // Only challenge manager or admin can add achievements
            let caller = get_caller_address();
            assert(
                self.access_control.has_role(CHALLENGE_MANAGER_ROLE, caller) || 
                self.access_control.has_role(ADMIN_ROLE, caller),
                'Not authorized to add achievement'
            );
            
            // Add achievement to user's achievements
            let mut achievements = self.user_achievements.read((user, hunt_id));
            achievements.append(achievement_text);
            self.user_achievements.write((user, hunt_id), achievements);
            
            // Emit event
            self.emit(Event::UserAchievementAdded(
                UserAchievementAdded {
                    user: user,
                    hunt_id: hunt_id,
                    challenge_id: challenge_id,
                    achievement_text: achievement_text,
                }
            ));
        }
        
        /// Updates a social sharing template
        /// 
        /// # Arguments
        /// 
        /// * `template_type` - Type of template to update (hunt_completion, challenge_completion, leaderboard_position)
        /// * `template` - New template text
        fn update_sharing_template(
            ref self: ContractState,
            template_type: felt252,
            template: felt252
        ) {
            // Only admin or moderator can update sharing templates
            let caller = get_caller_address();
            assert(
                self.access_control.has_role(ADMIN_ROLE, caller) || 
                self.access_control.has_role(MODERATOR_ROLE, caller),
                'Not authorized to update template'
            );
            
            // Update the appropriate template
            if template_type == 'hunt_completion' {
                self.hunt_completion_template.write(template);
            } else if template_type == 'challenge_completion' {
                self.challenge_completion_template.write(template);
            } else if template_type == 'leaderboard_position' {
                self.leaderboard_position_template.write(template);
            } else {
                assert(false, 'Invalid template type');
            }
            
            // Emit event
            self.emit(Event::SharingTemplateUpdated(
                SharingTemplateUpdated {
                    template_type: template_type,
                    template: template,
                }
            ));
        }
        
        /// Gets metadata for a hunt
        /// 
        /// # Arguments
        /// 
        /// * `hunt_id` - ID of the hunt
        /// 
        /// # Returns
        /// 
        /// * `HuntMetadata` - Metadata for the hunt
        fn get_hunt_metadata(self: @ContractState, hunt_id: u64) -> HuntMetadata {
            // Get hunt factory dispatcher
            let hunt_factory_address = self.hunt_factory.read();
            assert(hunt_factory_address != starknet::contract_address_const::&lt;0>(), 'Hunt factory not set');
            let hunt_factory = IHuntFactoryDispatcher { contract_address: hunt_factory_address };
            
            // Get the hunt
            let hunt = hunt_factory.get_hunt(hunt_id);
            
            // Get challenge manager dispatcher
            let challenge_manager_address = self.challenge_manager.read();
            assert(challenge_manager_address != starknet::contract_address_const::&lt;0>(), 'Challenge manager not set');
            let challenge_manager = IChallengeManagerDispatcher { contract_address: challenge_manager_address };
            
            // Get total challenges for the hunt
            let challenges = challenge_manager.get_hunt_challenges(hunt_id);
            
            // Return hunt metadata
            HuntMetadata {
                id: hunt_id,
                name: hunt.name,
                description: self.hunt_descriptions.read(hunt_id),
                image_url: self.hunt_images.read(hunt_id),
                external_url: self.hunt_external_urls.read(hunt_id),
                start_time: hunt.start_time,
                end_time: hunt.end_time,
                total_challenges: challenges.len(),
            }
        }
        
        /// Gets metadata for a challenge
        /// 
        /// # Arguments
        /// 
        /// * `hunt_id` - ID of the hunt
        /// * `challenge_id` - ID of the challenge
        /// 
        /// # Returns
        /// 
        /// * `ChallengeMetadata` - Metadata for the challenge
        fn get_challenge_metadata(self: @ContractState, hunt_id: u64, challenge_id: u64) -> ChallengeMetadata {
            // Get challenge manager dispatcher
            let challenge_manager_address = self.challenge_manager.read();
            assert(challenge_manager_address != starknet::contract_address_const::&lt;0>(), 'Challenge manager not set');
            let challenge_manager = IChallengeManagerDispatcher { contract_address: challenge_manager_address };
            
            // Get the challenge
            let challenge = challenge_manager.get_challenge(hunt_id, challenge_id);
            
            // Return challenge metadata
            ChallengeMetadata {
                id: challenge_id,
                hunt_id: hunt_id,
                question: challenge.question,
                description: self.challenge_descriptions.read((hunt_id, challenge_id)),
                image_url: self.challenge_images.read((hunt_id, challenge_id)),
                points: challenge.points,
            }
        }
        
        /// Gets all achievements for a user in a hunt
        /// 
        /// # Arguments
        /// 
        /// * `user` - Address of the user
        /// * `hunt_id` - ID of the hunt
        /// 
        /// # Returns
        /// 
        /// * `Array<felt252>` - Array of achievement texts
        fn get_user_achievements(self: @ContractState, user: ContractAddress, hunt_id: u64) -> Array<felt252> {
            self.user_achievements.read((user, hunt_id))
        }
        
        /// Generates social sharing content for hunt completion
        /// 
        /// # Arguments
        /// 
        /// * `user` - Address of the user
        /// * `hunt_id` - ID of the hunt
        /// 
        /// # Returns
        /// 
        /// * `SocialShareContent` - Content for social sharing
        fn generate_hunt_completion_share(
            self: @ContractState,
            user: ContractAddress,
            hunt_id: u64
        ) -> SocialShareContent {
            // Get hunt metadata
            let hunt_metadata = self.get_hunt_metadata(hunt_id);
            
            // Get challenge manager dispatcher
            let challenge_manager_address = self.challenge_manager.read();
            assert(challenge_manager_address != starknet::contract_address_const::&lt;0>(), 'Challenge manager not set');
            let challenge_manager = IChallengeManagerDispatcher { contract_address: challenge_manager_address };
            
            // Get user's completed challenges
            let completed_challenges = challenge_manager.get_user_completed_challenges(user, hunt_id);
            
            // Check if user has completed all challenges
            let all_completed = completed_challenges.len() == hunt_metadata.total_challenges;
            
            // Only generate share content if all challenges are completed
            assert(all_completed, 'Hunt not fully completed');
            
            // Get template
            let template = self.hunt_completion_template.read();
            
            // Replace placeholders in template
            // In a real implementation, this would be more sophisticated
            // For now, we'll just use the template as is
            
            // Generate share URL
            let base_url = self.base_sharing_url.read();
            let share_url = base_url; // In a real implementation, we would append parameters
            
            // Return social share content
            SocialShareContent {
                title: hunt_metadata.name,
                description: template,
                image_url: hunt_metadata.image_url,
                share_url: share_url,
            }
        }
        
        /// Generates social sharing content for challenge completion
        /// 
        /// # Arguments
        /// 
        /// * `user` - Address of the user
        /// * `hunt_id` - ID of the hunt
        /// * `challenge_id` - ID of the challenge
        /// 
        /// # Returns
        /// 
        /// * `SocialShareContent` - Content for social sharing
        fn generate_challenge_completion_share(
            self: @ContractState,
            user: ContractAddress,
            hunt_id: u64,
            challenge_id: u64
        ) -> SocialShareContent {
            // Get hunt metadata
            let hunt_metadata = self.get_hunt_metadata(hunt_id);
            
            // Get challenge metadata
            let challenge_metadata = self.get_challenge_metadata(hunt_id, challenge_id);
            
            // Get challenge manager dispatcher
            let challenge_manager_address = self.challenge_manager.read();
            assert(challenge_manager_address != starknet::contract_address_const::&lt;0>(), 'Challenge manager not set');
            let challenge_manager = IChallengeManagerDispatcher { contract_address: challenge_manager_address };
            
            // Check if user has completed the challenge
            let completed = challenge_manager.has_completed_challenge(user, hunt_id, challenge_id);
            assert(completed, 'Challenge not completed');
            
            // Get template
            let template = self.challenge_completion_template.read();
            
            // Replace placeholders in template
            // In a real implementation, this would be more sophisticated
            // For now, we'll just use the template as is
            
            // Generate share URL
            let base_url = self.base_sharing_url.read();
            let share_url = base_url; // In a real implementation, we would append parameters
            
            // Return social share content
            SocialShareContent {
                title: challenge_metadata.question,
                description: template,
                image_url: challenge_metadata.image_url,
                share_url: share_url,
            }
        }
        
        /// Generates social sharing content for leaderboard position
        /// 
        /// # Arguments
        /// 
        /// * `user` - Address of the user
        /// * `hunt_id` - ID of the hunt
        /// 
        /// # Returns
        /// 
        /// * `SocialShareContent` - Content for social sharing
        fn generate_leaderboard_position_share(
            self: @ContractState,
            user: ContractAddress,
            hunt_id: u64
        ) -> SocialShareContent {
            // Get hunt metadata
            let hunt_metadata = self.get_hunt_metadata(hunt_id);
            
            // Get leaderboard dispatcher
            let leaderboard_address = self.leaderboard.read();
            assert(leaderboard_address != starknet::contract_address_const::&lt;0>(), 'Leaderboard not set');
            let leaderboard = ILeaderboardDispatcher { contract_address: leaderboard_address };
            
            // Get leaderboard
            let leaderboard_data = leaderboard.get_leaderboard();
            
            // Find user's position in leaderboard
            // In a real implementation, this would be more efficient
            let mut position: u64 = 0;
            let mut found = false;
            let mut i: u32 = 0;
            
            loop {
                if i >= leaderboard_data.len() {
                    break;
                }
                
                let player = *leaderboard_data.at(i);
                if player.address == user {
                    position = i.into() + 1; // 1-based position
                    found = true;
                    break;
                }
                
                i += 1;
            };
            
            // Ensure user is on the leaderboard
            assert(found, 'User not on leaderboard');
            
            // Get template
            let template = self.leaderboard_position_template.read();
            
            // Replace placeholders in template
            // In a real implementation, this would be more sophisticated
            // For now, we'll just use the template as is
            
            // Generate share URL
            let base_url = self.base_sharing_url.read();
            let share_url = base_url; // In a real implementation, we would append parameters
            
            // Return social share content
            SocialShareContent {
                title: 'Leaderboard Position',
                description: template,
                image_url: hunt_metadata.image_url,
                share_url: share_url,
            }
        }
        
        /// Grants moderator role to an address
        /// 
        /// # Arguments
        /// 
        /// * `account` - Address to grant the role to
        fn grant_moderator_role(ref self: ContractState, account: ContractAddress) {
            // Only admin can grant moderator role
            self.assert_only_role(ADMIN_ROLE);
            self.access_control._grant_role(MODERATOR_ROLE, account);
        }
        
        /// Revokes moderator role from an address
        /// 
        /// # Arguments
        /// 
        /// * `account` - Address to revoke the role from
        fn revoke_moderator_role(ref self: ContractState, account: ContractAddress) {
            // Only admin can revoke moderator role
            self.assert_only_role(ADMIN_ROLE);
            self.access_control._revoke_role(MODERATOR_ROLE, account);
        }
        
        /// Checks if an address has a specific role
        /// 
        /// # Arguments
        /// 
        /// * `role` - Role to check
        /// * `account` - Address to check
        /// 
        /// # Returns
        /// 
        /// * `bool` - True if the address has the role, false otherwise
        fn has_role(self: @ContractState, role: felt252, account: ContractAddress) -> bool {
            self.access_control.has_role(role, account)
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

/// Interface for the SocialMetadata contract
#[starknet::interface]
trait ISocialMetadata<TContractState> {
    fn set_hunt_factory(ref self: TContractState, hunt_factory_address: ContractAddress);
    fn set_challenge_manager(ref self: TContractState, challenge_manager_address: ContractAddress);
    fn set_leaderboard(ref self: TContractState, leaderboard_address: ContractAddress);
    fn set_base_sharing_url(ref self: TContractState, base_url: felt252);
    
    fn update_hunt_metadata(
        ref self: TContractState,
        hunt_id: u64,
        description: felt252,
        image_url: felt252,
        external_url: felt252
    );
    
    fn update_challenge_metadata(
        ref self: TContractState,
        hunt_id: u64,
        challenge_id: u64,
        description: felt252,
        image_url: felt252
    );
    
    fn add_user_achievement(
        ref self: TContractState,
        user: ContractAddress,
        hunt_id: u64,
        challenge_id: u64,
        achievement_text: felt252
    );
    
    fn update_sharing_template(
        ref self: TContractState,
        template_type: felt252,
        template: felt252
    );
    
    fn get_hunt_metadata(self: @TContractState, hunt_id: u64) -> SocialMetadata::HuntMetadata;
    fn get_challenge_metadata(self: @TContractState, hunt_id: u64, challenge_id: u64) -> SocialMetadata::ChallengeMetadata;
    fn get_user_achievements(self: @TContractState, user: ContractAddress, hunt_id: u64) -> Array<felt252>;
    
    fn generate_hunt_completion_share(
        self: @TContractState,
        user: ContractAddress,
        hunt_id: u64
    ) -> SocialMetadata::SocialShareContent;
    
    fn generate_challenge_completion_share(
        self: @TContractState,
        user: ContractAddress,
        hunt_id: u64,
        challenge_id: u64
    ) -> SocialMetadata::SocialShareContent;
    
    fn generate_leaderboard_position_share(
        self: @TContractState,
        user: ContractAddress,
        hunt_id: u64
    ) -> SocialMetadata::SocialShareContent;
    
    fn grant_moderator_role(ref self: TContractState, account: ContractAddress);
    fn revoke_moderator_role(ref self: TContractState, account: ContractAddress);
    fn has_role(self: @TContractState, role: felt252, account: ContractAddress) -> bool;
}
