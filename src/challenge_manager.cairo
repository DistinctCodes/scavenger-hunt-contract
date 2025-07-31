// src/challenge_manager.cairo


//! # Challenge Manager Contract
//! 
//! This contract manages challenges for scavenger hunts and tracks user streaks.
//! It provides functionality for creating challenges, solving them, and maintaining
//! daily solving streaks for users.
//! 
//! ## Features
//! 
//! - Create and manage challenges for hunts
//! - Track user progress and completions
//! - Maintain daily solving streaks
//! - Reset streaks after 24+ hours of inactivity

#[starknet::contract]
mod ChallengeManager {
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp};
    use core::traits::Into;
    use core::option::OptionTrait;
    use core::array::ArrayTrait;
    use core::array::SpanTrait;
    use openzeppelin::access::accesscontrol::AccessControl;
    use nft_scavenger_hunt::hunt_factory::{IHuntFactoryDispatcher, IHuntFactoryDispatcherTrait};

    // Constants for roles
    const ADMIN_ROLE: felt252 = 'ADMIN_ROLE';
    const MODERATOR_ROLE: felt252 = 'MODERATOR_ROLE';
    const HUNT_FACTORY_ROLE: felt252 = 'HUNT_FACTORY_ROLE';

    // Constants for streak tracking
    const SECONDS_IN_DAY: u64 = 86400; // 24 * 60 * 60

    // Storage for the contract
    #[storage]
    struct Storage {
        // Access control storage
        #[substorage(v0)]
        access_control: AccessControl::Storage,
        
        // Hunt factory contract address
        hunt_factory: ContractAddress,
        
        // Challenge storage
        challenges: LegacyMap<(u64, u64), Challenge>, // (hunt_id, challenge_id) -> Challenge
        hunt_challenges: LegacyMap<u64, Array<u64>>, // hunt_id -> Array of challenge_ids
        next_challenge_id: LegacyMap<u64, u64>, // hunt_id -> next_challenge_id
        
        // User progress tracking
        user_completed_challenges: LegacyMap<(ContractAddress, u64), Array<u64>>, // (user, hunt_id) -> completed challenge_ids
        challenge_completions: LegacyMap<(ContractAddress, u64, u64), bool>, // (user, hunt_id, challenge_id) -> completed
        
        // Streak tracking storage
        user_streaks: LegacyMap<ContractAddress, u64>, // user -> current streak count
        user_last_solve_timestamp: LegacyMap<ContractAddress, u64>, // user -> last solve timestamp
        
        // Puzzle assignment storage
        user_assigned_puzzles: LegacyMap<(ContractAddress, u64), u64>, // (user, hunt_id) -> assigned_puzzle_id
        user_puzzle_nonce: LegacyMap<ContractAddress, u64>, // user -> nonce for randomness
        puzzle_assignment_status: LegacyMap<(ContractAddress, u64), bool>, // (user, hunt_id) -> has_assigned_puzzle
    }

    // Challenge struct
    #[derive(Drop, Serde, starknet::Store)]
    struct Challenge {
        id: u64,
        hunt_id: u64,
        question: felt252,
        answer_hash: felt252,
        points: u64,
        active: bool,
    }

    // Challenge question struct (without answer hash for public viewing)
    #[derive(Drop, Serde)]
    struct ChallengeQuestion {
        id: u64,
        hunt_id: u64,
        question: felt252,
        points: u64,
    }

    // Events
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        ChallengeAdded: ChallengeAdded,
        ChallengeCompleted: ChallengeCompleted,
        StreakUpdated: StreakUpdated,
        PuzzleAssigned: PuzzleAssigned,
        #[flat]
        AccessControlEvent: AccessControl::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct ChallengeAdded {
        hunt_id: u64,
        challenge_id: u64,
        question: felt252,
        points: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct ChallengeCompleted {
        user: ContractAddress,
        hunt_id: u64,
        challenge_id: u64,
        points: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct StreakUpdated {
        user: ContractAddress,
        streak_count: u64,
    }

    // Constructor
    #[constructor]
    fn constructor(ref self: ContractState, hunt_factory_address: ContractAddress) {
        // Initialize access control
        self.access_control.initializer();
        
        // Set hunt factory address
        self.hunt_factory.write(hunt_factory_address);
        
        // Grant admin role to the deployer
        let deployer = get_caller_address();
        self.access_control._grant_role(ADMIN_ROLE, deployer);
    }

    // External functions
    #[external(v0)]
    impl ChallengeManagerImpl of super::IChallengeManager<ContractState> {
        /// Adds a new challenge to a hunt
        /// 
        /// # Arguments
        /// 
        /// * `hunt_id` - ID of the hunt
        /// * `question` - Challenge question
        /// * `answer_hash` - Hash of the correct answer
        /// * `points` - Points awarded for solving
        /// 
        /// # Returns
        /// 
        /// * `u64` - ID of the created challenge
        fn add_challenge(
            ref self: ContractState,
            hunt_id: u64,
            question: felt252,
            answer_hash: felt252,
            points: u64
        ) -> u64 {
            let caller = get_caller_address();
            
            // Get hunt factory dispatcher
            let hunt_factory_address = self.hunt_factory.read();
            let hunt_factory = IHuntFactoryDispatcher { contract_address: hunt_factory_address };
            
            // Get the hunt to verify ownership
            let hunt = hunt_factory.get_hunt(hunt_id);
            
            // Only hunt creator can add challenges
            assert(caller == hunt.admin, 'Only hunt creator can add');
            
            // Get next challenge ID for this hunt
            let challenge_id = self.next_challenge_id.read(hunt_id);
            
            // Create the challenge
            let challenge = Challenge {
                id: challenge_id,
                hunt_id: hunt_id,
                question: question,
                answer_hash: answer_hash,
                points: points,
                active: true,
            };
            
            // Store the challenge
            self.challenges.write((hunt_id, challenge_id), challenge);
            
            // Add to hunt challenges list
            let mut hunt_challenges = self.hunt_challenges.read(hunt_id);
            hunt_challenges.append(challenge_id);
            self.hunt_challenges.write(hunt_id, hunt_challenges);
            
            // Increment next challenge ID
            self.next_challenge_id.write(hunt_id, challenge_id + 1);
            
            // Emit event
            self.emit(Event::ChallengeAdded(
                ChallengeAdded {
                    hunt_id: hunt_id,
                    challenge_id: challenge_id,
                    question: question,
                    points: points,
                }
            ));
            
            challenge_id
        }
        
        /// Gets a challenge by hunt ID and challenge ID
        /// 
        /// # Arguments
        /// 
        /// * `hunt_id` - ID of the hunt
        /// * `challenge_id` - ID of the challenge
        /// 
        /// # Returns
        /// 
        /// * `Challenge` - The challenge data
        fn get_challenge(self: @ContractState, hunt_id: u64, challenge_id: u64) -> Challenge {
            self.challenges.read((hunt_id, challenge_id))
        }
        
        /// Gets a challenge by index (without answer hash for public viewing)
        /// 
        /// # Arguments
        /// 
        /// * `hunt_id` - ID of the hunt
        /// * `index` - Index of the challenge in the hunt
        /// 
        /// # Returns
        /// 
        /// * `ChallengeQuestion` - The challenge question data
        fn get_challenge_by_index(self: @ContractState, hunt_id: u64, index: u64) -> ChallengeQuestion {
            let hunt_challenges = self.hunt_challenges.read(hunt_id);
            assert(index < hunt_challenges.len(), 'Invalid challenge index');
            
            let challenge_id = *hunt_challenges.at(index.try_into().unwrap());
            let challenge = self.challenges.read((hunt_id, challenge_id));
            
            ChallengeQuestion {
                id: challenge.id,
                hunt_id: challenge.hunt_id,
                question: challenge.question,
                points: challenge.points,
            }
        }
        
        /// Gets all challenge IDs for a hunt
        /// 
        /// # Arguments
        /// 
        /// * `hunt_id` - ID of the hunt
        /// 
        /// # Returns
        /// 
        /// * `Array<u64>` - Array of challenge IDs
        fn get_hunt_challenges(self: @ContractState, hunt_id: u64) -> Array<u64> {
            self.hunt_challenges.read(hunt_id)
        }
        
        /// Submits an answer to a challenge
        /// 
        /// # Arguments
        /// 
        /// * `hunt_id` - ID of the hunt
        /// * `challenge_id` - ID of the challenge
        /// * `answer_hash` - Hash of the submitted answer
        /// 
        /// # Returns
        /// 
        /// * `bool` - True if answer is correct, false otherwise
        fn submit_answer(
            ref self: ContractState,
            hunt_id: u64,
            challenge_id: u64,
            answer_hash: felt252
        ) -> bool {
            let caller = get_caller_address();
            
            // Check if user has an assigned puzzle and if this is the correct one
            let has_assigned = self.puzzle_assignment_status.read((caller, hunt_id));
            if has_assigned {
                let assigned_puzzle_id = self.user_assigned_puzzles.read((caller, hunt_id));
                assert(challenge_id == assigned_puzzle_id, 'Must solve assigned puzzle first');
            }
            
            // Get the challenge
            let challenge = self.challenges.read((hunt_id, challenge_id));
            assert(challenge.active, 'Challenge not active');
            
            // Check if already completed
            let already_completed = self.challenge_completions.read((caller, hunt_id, challenge_id));
            assert(!already_completed, 'Challenge already completed');
            
            // Check if answer is correct
            if answer_hash == challenge.answer_hash {
                // Mark as completed
                self.challenge_completions.write((caller, hunt_id, challenge_id), true);
                
                // Add to user's completed challenges
                let mut completed = self.user_completed_challenges.read((caller, hunt_id));
                completed.append(challenge_id);
                self.user_completed_challenges.write((caller, hunt_id), completed);
                
                // Clear puzzle assignment to allow new assignment
                if has_assigned {
                    self.puzzle_assignment_status.write((caller, hunt_id), false);
                    self.user_assigned_puzzles.write((caller, hunt_id), 0);
                }
                
                // Update streak
                let current_timestamp = get_block_timestamp();
                self.update_streak(caller, current_timestamp);
                
                // Emit event
                self.emit(Event::ChallengeCompleted(
                    ChallengeCompleted {
                        user: caller,
                        hunt_id: hunt_id,
                        challenge_id: challenge_id,
                        points: challenge.points,
                    }
                ));
                
                true
            } else {
                false
            }
        }
        
        /// Gets user's completed challenges for a hunt
        /// 
        /// # Arguments
        /// 
        /// * `user` - User address
        /// * `hunt_id` - ID of the hunt
        /// 
        /// # Returns
        /// 
        /// * `Array<u64>` - Array of completed challenge IDs
        fn get_user_completed_challenges(self: @ContractState, user: ContractAddress, hunt_id: u64) -> Array<u64> {
            self.user_completed_challenges.read((user, hunt_id))
        }
        
        /// Checks if user has completed a specific challenge
        /// 
        /// # Arguments
        /// 
        /// * `user` - User address
        /// * `hunt_id` - ID of the hunt
        /// * `challenge_id` - ID of the challenge
        /// 
        /// # Returns
        /// 
        /// * `bool` - True if completed, false otherwise
        fn has_completed_challenge(self: @ContractState, user: ContractAddress, hunt_id: u64, challenge_id: u64) -> bool {
            self.challenge_completions.read((user, hunt_id, challenge_id))
        }
        
        /// Updates user's daily streak
        /// 
        /// # Arguments
        /// 
        /// * `user` - User address
        /// * `day_timestamp` - Timestamp of the day
        fn update_streak(ref self: ContractState, user: ContractAddress, day_timestamp: u64) {
            let last_solve_timestamp = self.user_last_solve_timestamp.read(user);
            let current_streak = self.user_streaks.read(user);
            
            let new_streak = if last_solve_timestamp == 0 {
                // First time solving
                1
            } else {
                let time_diff = day_timestamp - last_solve_timestamp;
                
                if time_diff <= SECONDS_IN_DAY {
                    // Same day or consecutive day
                    current_streak + 1
                } else if time_diff <= 2 * SECONDS_IN_DAY {
                    // Next day (within 48 hours)
                    current_streak + 1
                } else {
                    // More than 24 hours gap, reset streak
                    1
                }
            };
            
            // Update storage
            self.user_streaks.write(user, new_streak);
            self.user_last_solve_timestamp.write(user, day_timestamp);
            
            // Emit event
            self.emit(Event::StreakUpdated(
                StreakUpdated {
                    user: user,
                    streak_count: new_streak,
                }
            ));
        }
        
        /// Gets user's current streak
        /// 
        /// # Arguments
        /// 
        /// * `user` - User address
        /// 
        /// # Returns
        /// 
        /// * `u64` - Current streak count
        fn get_user_streak(self: @ContractState, user: ContractAddress) -> u64 {
            let last_solve_timestamp = self.user_last_solve_timestamp.read(user);
            let current_timestamp = get_block_timestamp();
            
            // Check if streak should be reset due to inactivity
            if last_solve_timestamp > 0 && (current_timestamp - last_solve_timestamp) > SECONDS_IN_DAY {
                // Streak should be reset, but we don't modify state in a view function
                // The streak will be reset when update_streak is called next time
                0
            } else {
                self.user_streaks.read(user)
            }
        }
        
        /// Gets user's last solve timestamp
        /// 
        /// # Arguments
        /// 
        /// * `user` - User address
        /// 
        /// # Returns
        /// 
        /// * `u64` - Last solve timestamp
        fn get_user_last_solve_timestamp(self: @ContractState, user: ContractAddress) -> u64 {
            self.user_last_solve_timestamp.read(user)
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

/// Interface for the ChallengeManager contract
#[starknet::interface]
trait IChallengeManager<TContractState> {
    fn add_challenge(
        ref self: TContractState,
        hunt_id: u64,
        question: felt252,
        answer_hash: felt252,
        points: u64
    ) -> u64;
    
    fn get_challenge(self: @TContractState, hunt_id: u64, challenge_id: u64) -> ChallengeManager::Challenge;
    fn get_challenge_by_index(self: @TContractState, hunt_id: u64, index: u64) -> ChallengeManager::ChallengeQuestion;
    fn get_hunt_challenges(self: @TContractState, hunt_id: u64) -> Array<u64>;
    
    fn submit_answer(
        ref self: TContractState,
        hunt_id: u64,
        challenge_id: u64,
        answer_hash: felt252
    ) -> bool;
    
    fn get_user_completed_challenges(self: @TContractState, user: ContractAddress, hunt_id: u64) -> Array<u64>;
    fn has_completed_challenge(self: @TContractState, user: ContractAddress, hunt_id: u64, challenge_id: u64) -> bool;
    
    // Streak tracking functions
    fn update_streak(ref self: TContractState, user: ContractAddress, day_timestamp: u64);
    fn get_user_streak(self: @TContractState, user: ContractAddress) -> u64;
    fn get_user_last_solve_timestamp(self: @TContractState, user: ContractAddress) -> u64;
    
    // Puzzle assignment functions
    fn assign_puzzle(ref self: TContractState, hunt_id: u64) -> u64;
    fn get_assigned_puzzle(self: @TContractState, user: ContractAddress, hunt_id: u64) -> u64;
    fn has_assigned_puzzle(self: @TContractState, user: ContractAddress, hunt_id: u64) -> bool;
    
    fn submit_answer(
        ref self: TContractState,
        hunt_id: u64,
        challenge_id: u64,
        answer_hash: felt252
    ) -> bool;
}