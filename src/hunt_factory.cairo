//! # Hunt Factory Contract
//! 
//! This contract manages the creation and administration of scavenger hunts.
//! It allows users to create hunts, update hunt metadata, and control hunt activation status.
//! 
//! ## Features
//! 
//! - Create new scavenger hunts with name, start time, and end time
//! - Update hunt metadata (name, end time)
//! - Enable/disable hunts
//! - Track hunt creators and their hunts

#[starknet::contract]
mod HuntFactory {
    use starknet::{ContractAddress, get_caller_address};
    use core::traits::Into;
    use core::option::OptionTrait;
    use core::array::ArrayTrait;
    use openzeppelin::access::accesscontrol::AccessControl;

    // Constants for roles
    const ADMIN_ROLE: felt252 = 'ADMIN_ROLE';
    const MODERATOR_ROLE: felt252 = 'MODERATOR_ROLE';

    // Storage for the contract
    #[storage]
    struct Storage {
        // Access control storage
        #[substorage(v0)]
        access_control: AccessControl::Storage,
        
        // Counter for hunt IDs
        hunt_counter: u64,
        // Mapping from hunt ID to Hunt struct
        hunts: LegacyMap<u64, Hunt>,
        // Mapping from address to array of hunt IDs they created
        admin_hunts: LegacyMap<ContractAddress, Array<u64>>,
    }

    /// Hunt struct to store hunt details
    /// 
    /// # Fields
    /// 
    /// * `id` - Unique identifier for the hunt
    /// * `name` - Name of the hunt
    /// * `admin` - Address of the hunt creator/admin
    /// * `start_time` - Timestamp when the hunt starts
    /// * `end_time` - Timestamp when the hunt ends
    /// * `active` - Flag indicating if the hunt is active
    #[derive(Drop, Serde, starknet::Store)]
    struct Hunt {
        id: u64,
        name: felt252,
        admin: ContractAddress,
        start_time: u64,
        end_time: u64,
        active: bool,
    }

    // Events
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        HuntCreated: HuntCreated,
        HuntUpdated: HuntUpdated,
        HuntStatusChanged: HuntStatusChanged,
        #[flat]
        AccessControlEvent: AccessControl::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct HuntCreated {
        hunt_id: u64,
        name: felt252,
        admin: ContractAddress,
        start_time: u64,
        end_time: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct HuntUpdated {
        hunt_id: u64,
        name: felt252,
        end_time: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct HuntStatusChanged {
        hunt_id: u64,
        active: bool,
    }

    // Constructor
    #[constructor]
    fn constructor(ref self: ContractState, admin: ContractAddress) {
        // Initialize access control
        self.access_control.initializer();
        
        // Grant admin role to the specified admin
        self.access_control._grant_role(ADMIN_ROLE, admin);
        
        // Initialize hunt counter
        self.hunt_counter.write(0);
    }

    // Contract functions
    #[external(v0)]
    impl HuntFactoryImpl of super::IHuntFactory<ContractState> {
        /// Creates a new hunt with the specified parameters
        /// 
        /// # Arguments
        /// 
        /// * `name` - Name of the hunt
        /// * `start_time` - Timestamp when the hunt starts
        /// * `end_time` - Timestamp when the hunt ends
        /// 
        /// # Returns
        /// 
        /// * `u64` - ID of the created hunt
        fn create_hunt(
            ref self: ContractState, 
            name: felt252, 
            start_time: u64, 
            end_time: u64
        ) -> u64 {
            // Get caller address (admin)
            let admin = get_caller_address();
            
            // Validate inputs
            assert(start_time < end_time, 'End time must be after start');
            
            // Get and increment hunt counter
            let hunt_id = self.hunt_counter.read();
            self.hunt_counter.write(hunt_id + 1);
            
            // Create new hunt
            let hunt = Hunt {
                id: hunt_id,
                name: name,
                admin: admin,
                start_time: start_time,
                end_time: end_time,
                active: true, // Hunts are active by default
            };
            
            // Store hunt
            self.hunts.write(hunt_id, hunt);
            
            // Add hunt to admin's hunts
            let mut admin_hunts = self.get_admin_hunts_internal(admin);
            admin_hunts.append(hunt_id);
            self.admin_hunts.write(admin, admin_hunts);
            
            // Emit event
            self.emit(Event::HuntCreated(
                HuntCreated {
                    hunt_id: hunt_id,
                    name: name,
                    admin: admin,
                    start_time: start_time,
                    end_time: end_time,
                }
            ));
            
            hunt_id
        }

        /// Updates an existing hunt's metadata
        /// 
        /// # Arguments
        /// 
        /// * `hunt_id` - ID of the hunt to update
        /// * `name` - New name for the hunt
        /// * `end_time` - New end time for the hunt
        fn update_hunt(
            ref self: ContractState,
            hunt_id: u64,
            name: felt252,
            end_time: u64
        ) {
            // Get caller address
            let caller = get_caller_address();
            
            // Get the hunt
            let mut hunt = self.hunts.read(hunt_id);
            
            // Ensure only the creator or an admin/moderator can update the hunt
            self.assert_can_manage_hunt(caller, hunt);
            
            // Ensure end_time is after start_time
            assert(end_time > hunt.start_time, 'End time must be after start');
            
            // Update hunt metadata
            hunt.name = name;
            hunt.end_time = end_time;
            
            // Save updated hunt
            self.hunts.write(hunt_id, hunt);
            
            // Emit event
            self.emit(Event::HuntUpdated(
                HuntUpdated {
                    hunt_id: hunt_id,
                    name: name,
                    end_time: end_time,
                }
            ));
        }
        
        /// Enables or disables a hunt
        /// 
        /// # Arguments
        /// 
        /// * `hunt_id` - ID of the hunt to update
        /// * `active` - New active status for the hunt
        fn set_hunt_active(
            ref self: ContractState,
            hunt_id: u64,
            active: bool
        ) {
            // Get caller address
            let caller = get_caller_address();
            
            // Get the hunt
            let mut hunt = self.hunts.read(hunt_id);
            
            // Ensure only the creator or an admin/moderator can update the hunt
            self.assert_can_manage_hunt(caller, hunt);
            
            // Update hunt active status
            hunt.active = active;
            
            // Save updated hunt
            self.hunts.write(hunt_id, hunt);
            
            // Emit event
            self.emit(Event::HuntStatusChanged(
                HuntStatusChanged {
                    hunt_id: hunt_id,
                    active: active,
                }
            ));
        }
        
        /// Gets hunt details
        /// 
        /// # Arguments
        /// 
        /// * `hunt_id` - ID of the hunt to get
        /// 
        /// # Returns
        /// 
        /// * `Hunt` - Hunt details
        fn get_hunt(self: @ContractState, hunt_id: u64) -> Hunt {
            self.hunts.read(hunt_id)
        }
        
        /// Gets all hunts created by an admin
        /// 
        /// # Arguments
        /// 
        /// * `admin` - Address of the admin
        /// 
        /// # Returns
        /// 
        /// * `Array<u64>` - Array of hunt IDs created by the admin
        fn get_admin_hunts(self: @ContractState, admin: ContractAddress) -> Array<u64> {
            self.get_admin_hunts_internal(admin)
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
        /// Gets all hunts created by an admin (internal function)
        /// 
        /// # Arguments
        /// 
        /// * `admin` - Address of the admin
        /// 
        /// # Returns
        /// 
        /// * `Array<u64>` - Array of hunt IDs created by the admin
        fn get_admin_hunts_internal(self: @ContractState, admin: ContractAddress) -> Array<u64> {
            self.admin_hunts.read(admin)
        }
        
        /// Asserts that the caller has a specific role
        /// 
        /// # Arguments
        /// 
        /// * `role` - Role to check
        fn assert_only_role(self: @ContractState, role: felt252) {
            let caller = get_caller_address();
            assert(self.access_control.has_role(role, caller), 'Caller does not have role');
        }
        
        /// Asserts that the caller can manage a hunt (is the creator or has admin/moderator role)
        /// 
        /// # Arguments
        /// 
        /// * `caller` - Address of the caller
        /// * `hunt` - Hunt to check
        fn assert_can_manage_hunt(self: @ContractState, caller: ContractAddress, hunt: Hunt) {
            assert(
                caller == hunt.admin || 
                self.access_control.has_role(ADMIN_ROLE, caller) || 
                self.access_control.has_role(MODERATOR_ROLE, caller),
                'Not authorized to manage hunt'
            );
        }
    }
}

/// Interface for the HuntFactory contract
#[starknet::interface]
trait IHuntFactory<TContractState> {
    fn create_hunt(
        ref self: TContractState, 
        name: felt252, 
        start_time: u64, 
        end_time: u64
    ) -> u64;
    
    fn update_hunt(
        ref self: TContractState,
        hunt_id: u64,
        name: felt252,
        end_time: u64
    );
    
    fn set_hunt_active(
        ref self: TContractState,
        hunt_id: u64,
        active: bool
    );
    
    fn get_hunt(self: @TContractState, hunt_id: u64) -> HuntFactory::Hunt;
    fn get_admin_hunts(self: @TContractState, admin: ContractAddress) -> Array<u64>;
    
    fn grant_moderator_role(ref self: TContractState, account: ContractAddress);
    fn revoke_moderator_role(ref self: TContractState, account: ContractAddress);
    fn has_role(self: @TContractState, role: felt252, account: ContractAddress) -> bool;
}
