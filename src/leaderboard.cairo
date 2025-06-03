#[starknet::contract]
mod Leaderboard {
    use starknet::{ContractAddress, get_caller_address};
    use core::traits::Into;
    use core::option::OptionTrait;
    use core::array::ArrayTrait;
    use core::array::SpanTrait;
    use core::integer::BoundedInt;
    use openzeppelin::access::accesscontrol::AccessControl;

    // Constants for roles
    const ADMIN_ROLE: felt252 = 'ADMIN_ROLE';
    const MODERATOR_ROLE: felt252 = 'MODERATOR_ROLE';
    const CHALLENGE_MANAGER_ROLE: felt252 = 'CHALLENGE_MANAGER_ROLE';

    // Storage for the contract
    #[storage]
    struct Storage {
        // Access control storage
        #[substorage(v0)]
        access_control: AccessControl::Storage,
        
        // Challenge manager contract address
        challenge_manager: ContractAddress,
        
        // Mapping from user address to total points
        user_points: LegacyMap<ContractAddress, u64>,
        
        // Mapping from user address to number of completed challenges
        user_completed_challenges: LegacyMap<ContractAddress, u64>,
        
        // Array of all users who have completed challenges
        all_users: Array<ContractAddress>,
        
        // Flag to track if a user is already in the all_users array
        user_registered: LegacyMap<ContractAddress, bool>,
        
        // Maximum number of users to return in leaderboard
        leaderboard_max_size: u64,
    }

    // Player struct for leaderboard
    #[derive(Drop, Serde)]
    struct Player {
        address: ContractAddress,
        completed_challenges: u64,
        points: u64,
    }

    // Events
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        PointsAdded: PointsAdded,
        ChallengeCompleted: ChallengeCompleted,
        #[flat]
        AccessControlEvent: AccessControl::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct PointsAdded {
        user: ContractAddress,
        points: u64,
        total_points: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct ChallengeCompleted {
        user: ContractAddress,
        hunt_id: u64,
        challenge_id: u64,
        total_completed: u64,
    }

    // Constructor
    #[constructor]
    fn constructor(ref self: ContractState, admin: ContractAddress) {
        // Initialize access control
        self.access_control.initializer();
        
        // Grant admin role to the deployer
        self.access_control._grant_role(ADMIN_ROLE, admin);
        
        // Set default leaderboard size
        self.leaderboard_max_size.write(10);
    }

    // Contract functions
    #[external(v0)]
    impl LeaderboardImpl of super::ILeaderboard<ContractState> {
        // Set the challenge manager contract address
        fn set_challenge_manager(ref self: ContractState, challenge_manager: ContractAddress) {
            // Only admin can set the challenge manager
            self.assert_only_role(ADMIN_ROLE);
            self.challenge_manager.write(challenge_manager);
            
            // Grant challenge manager role to the contract
            self.access_control._grant_role(CHALLENGE_MANAGER_ROLE, challenge_manager);
        }
        
        // Add points for a user when they complete a challenge
        fn add_points(
            ref self: ContractState,
            user: ContractAddress,
            hunt_id: u64,
            challenge_id: u64,
            points: u64
        ) {
            // Only challenge manager can add points
            self.assert_only_role(CHALLENGE_MANAGER_ROLE);
            
            // Register user if not already registered
            if !self.user_registered.read(user) {
                let mut users = self.all_users.read();
                users.append(user);
                self.all_users.write(users);
                self.user_registered.write(user, true);
            }
            
            // Update user points
            let current_points = self.user_points.read(user);
            let new_points = current_points + points;
            self.user_points.write(user, new_points);
            
            // Update completed challenges count
            let completed = self.user_completed_challenges.read(user);
            let new_completed = completed + 1;
            self.user_completed_challenges.write(user, new_completed);
            
            // Emit events
            self.emit(Event::PointsAdded(
                PointsAdded {
                    user: user,
                    points: points,
                    total_points: new_points,
                }
            ));
            
            self.emit(Event::ChallengeCompleted(
                ChallengeCompleted {
                    user: user,
                    hunt_id: hunt_id,
                    challenge_id: challenge_id,
                    total_completed: new_completed,
                }
            ));
        }
        
        // Get the leaderboard (top players by points)
        fn get_leaderboard(self: @ContractState) -> Array<Player> {
            let mut leaderboard = ArrayTrait::new();
            let users = self.all_users.read();
            let max_size = self.leaderboard_max_size.read();
            
            // Create array of players
            let mut i: u32 = 0;
            let users_len = users.len();
            
            // Add all users to the leaderboard
            loop {
                if i >= users_len {
                    break;
                }
                
                let user = *users.at(i);
                let completed = self.user_completed_challenges.read(user);
                let points = self.user_points.read(user);
                
                leaderboard.append(
                    Player {
                        address: user,
                        completed_challenges: completed,
                        points: points,
                    }
                );
                
                i += 1;
            };
            
            // Sort the leaderboard by points (simple bubble sort)
            // Note: In a production environment, you might want to use a more efficient sorting algorithm
            // or implement pagination to avoid gas limits
            let mut sorted = false;
            let leaderboard_len = leaderboard.len();
            
            if leaderboard_len <= 1 {
                return leaderboard;
            }
            
            let mut i: u32 = 0;
            loop {
                if i >= leaderboard_len - 1 {
                    break;
                }
                
                let mut j: u32 = 0;
                loop {
                    if j >= leaderboard_len - i - 1 {
                        break;
                    }
                    
                    let player1 = *leaderboard.at(j);
                    let player2 = *leaderboard.at(j + 1);
                    
                    if player1.points < player2.points {
                        // Swap players
                        leaderboard.set(j, player2);
                        leaderboard.set(j + 1, player1);
                    }
                    
                    j += 1;
                };
                
                i += 1;
            };
            
            // Return top N players
            let mut top_players = ArrayTrait::new();
            let mut i: u32 = 0;
            
            loop {
                if i >= leaderboard_len || i >= max_size.into() {
                    break;
                }
                
                top_players.append(*leaderboard.at(i));
                i += 1;
            };
            
            top_players
        }
        
        // Get a specific user's stats
        fn get_user_stats(self: @ContractState, user: ContractAddress) -> Player {
            Player {
                address: user,
                completed_challenges: self.user_completed_challenges.read(user),
                points: self.user_points.read(user),
            }
        }
        
        // Set the maximum size of the leaderboard
        fn set_leaderboard_max_size(ref self: ContractState, max_size: u64) {
            // Only admin or moderator can set the leaderboard size
            self.assert_only_role_or_admin(MODERATOR_ROLE);
            self.leaderboard_max_size.write(max_size);
        }
        
        // Grant moderator role to an address
        fn grant_moderator_role(ref self: ContractState, account: ContractAddress) {
            // Only admin can grant moderator role
            self.assert_only_role(ADMIN_ROLE);
            self.access_control._grant_role(MODERATOR_ROLE, account);
        }
        
        // Revoke moderator role from an address
        fn revoke_moderator_role(ref self: ContractState, account: ContractAddress) {
            // Only admin can revoke moderator role
            self.assert_only_role(ADMIN_ROLE);
            self.access_control._revoke_role(MODERATOR_ROLE, account);
        }
        
        // Check if an address has a specific role
        fn has_role(self: @ContractState, role: felt252, account: ContractAddress) -> bool {
            self.access_control.has_role(role, account)
        }
    }
    
    // Internal functions
    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        // Assert that the caller has a specific role
        fn assert_only_role(self: @ContractState, role: felt252) {
            let caller = get_caller_address();
            assert(self.access_control.has_role(role, caller), 'Caller does not have role');
        }
        
        // Assert that the caller has a specific role or is an admin
        fn assert_only_role_or_admin(self: @ContractState, role: felt252) {
            let caller = get_caller_address();
            assert(
                self.access_control.has_role(role, caller) || self.access_control.has_role(ADMIN_ROLE, caller),
                'Caller does not have permission'
            );
        }
    }
}

// Interface for the Leaderboard contract
#[starknet::interface]
trait ILeaderboard<TContractState> {
    fn set_challenge_manager(ref self: TContractState, challenge_manager: ContractAddress);
    fn add_points(
        ref self: TContractState,
        user: ContractAddress,
        hunt_id: u64,
        challenge_id: u64,
        points: u64
    );
    fn get_leaderboard(self: @TContractState) -> Array<Leaderboard::Player>;
    fn get_user_stats(self: @TContractState, user: ContractAddress) -> Leaderboard::Player;
    fn set_leaderboard_max_size(ref self: TContractState, max_size: u64);
    fn grant_moderator_role(ref self: TContractState, account: ContractAddress);
    fn revoke_moderator_role(ref self: TContractState, account: ContractAddress);
    fn has_role(self: @TContractState, role: felt252, account: ContractAddress) -> bool;
}
