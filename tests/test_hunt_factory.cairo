use core::option::OptionTrait;
use core::traits::Into;
use core::array::ArrayTrait;
use starknet::{ContractAddress, contract_address_const};
use nft_scavenger_hunt::hunt_factory::{HuntFactory, IHuntFactoryDispatcher, IHuntFactoryDispatcherTrait};

// Import test utilities
use starknet::testing::{set_caller_address, set_contract_address, set_block_timestamp};

// Test constants
const NAME: felt252 = 'Test Hunt';
const START_TIME: u64 = 1000;
const END_TIME: u64 = 2000;
const NEW_NAME: felt252 = 'Updated Hunt';
const NEW_END_TIME: u64 = 3000;

// Test utilities
fn setup() -> (ContractAddress, IHuntFactoryDispatcher) {
    // Deploy the contract
    let contract = starknet::deploy_syscall(
        HuntFactory::TEST_CLASS_HASH, 0, ArrayTrait::new().span(), false
    ).unwrap();
    
    // Create admin address
    let admin = contract_address_const::<1>();
    
    // Set caller as admin
    set_caller_address(admin);
    
    // Create dispatcher
    let dispatcher = IHuntFactoryDispatcher { contract_address: contract };
    
    (admin, dispatcher)
}

#[test]
fn test_create_hunt() {
    // Setup
    let (admin, dispatcher) = setup();
    
    // Create a hunt
    let hunt_id = dispatcher.create_hunt(NAME, START_TIME, END_TIME);
    
    // Verify hunt was created correctly
    let hunt = dispatcher.get_hunt(hunt_id);
    assert(hunt.id == 0, 'Hunt ID should be 0');
    assert(hunt.name == NAME, 'Hunt name should match');
    assert(hunt.admin == admin, 'Hunt admin should be caller');
    assert(hunt.start_time == START_TIME, 'Start time should match');
    assert(hunt.end_time == END_TIME, 'End time should match');
    assert(hunt.active == true, 'Hunt should be active');
    
    // Verify admin hunts
    let admin_hunts = dispatcher.get_admin_hunts(admin);
    assert(admin_hunts.len() == 1, 'Admin should have 1 hunt');
    assert(*admin_hunts.at(0) == hunt_id, 'Hunt ID should match');
}

#[test]
fn test_update_hunt() {
    // Setup
    let (admin, dispatcher) = setup();
    
    // Create a hunt
    let hunt_id = dispatcher.create_hunt(NAME, START_TIME, END_TIME);
    
    // Update the hunt
    dispatcher.update_hunt(hunt_id, NEW_NAME, NEW_END_TIME);
    
    // Verify hunt was updated correctly
    let hunt = dispatcher.get_hunt(hunt_id);
    assert(hunt.name == NEW_NAME, 'Hunt name should be updated');
    assert(hunt.end_time == NEW_END_TIME, 'End time should be updated');
    assert(hunt.start_time == START_TIME, 'Start time should not change');
}

#[test]
#[should_panic(expected: ('Only creator can update hunt',))]
fn test_update_hunt_not_creator() {
    // Setup
    let (admin, dispatcher) = setup();
    
    // Create a hunt
    let hunt_id = dispatcher.create_hunt(NAME, START_TIME, END_TIME);
    
    // Set a different caller
    let other_user = contract_address_const::<2>();
    set_caller_address(other_user);
    
    // Try to update the hunt (should fail)
    dispatcher.update_hunt(hunt_id, NEW_NAME, NEW_END_TIME);
}

#[test]
#[should_panic(expected: ('End time must be after start',))]
fn test_update_hunt_invalid_end_time() {
    // Setup
    let (admin, dispatcher) = setup();
    
    // Create a hunt
    let hunt_id = dispatcher.create_hunt(NAME, START_TIME, END_TIME);
    
    // Try to update with invalid end time (before start time)
    dispatcher.update_hunt(hunt_id, NEW_NAME, START_TIME - 1);
}
