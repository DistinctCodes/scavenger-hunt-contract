// Test file for hunt activation/deactivation functionality

use core::option::OptionTrait;
use core::traits::Into;
use core::array::ArrayTrait;
use starknet::{ContractAddress, contract_address_const};
use nft_scavenger_hunt::hunt_factory::{HuntFactory, IHuntFactoryDispatcher, IHuntFactoryDispatcherTrait};
use nft_scavenger_hunt::challenge_manager::{ChallengeManager, IChallengeManagerDispatcher, IChallengeManagerDispatcherTrait};

// Import test utilities
use starknet::testing::{set_caller_address, set_contract_address, set_block_timestamp};

// Test constants
const HUNT_NAME: felt252 = 'Test Hunt';
const START_TIME: u64 = 1000;
const END_TIME: u64 = 2000;
const QUESTION: felt252 = 'What is the capital of France?';
const CORRECT_ANSWER: felt252 = 'Paris';
const POINTS: u64 = 100;

// Helper function to hash an answer the same way the contract does
fn hash_answer(answer: felt252) -> felt252 {
    let hash = LegacyHash::hash(0, answer);
    hash
}

// Test utilities
fn setup() -> (
    ContractAddress,
    ContractAddress,
    ContractAddress,
    IHuntFactoryDispatcher,
    IChallengeManagerDispatcher
) {
    // Create admin, user, and moderator addresses
    let admin = contract_address_const::<1>();
    let user = contract_address_const::<2>();
    let moderator = contract_address_const::<3>();
    
    // Set caller as admin
    set_caller_address(admin);
    
    // Deploy the HuntFactory contract
    let mut calldata = ArrayTrait::new();
    calldata.append(admin.into());
    let hunt_factory_contract = starknet::deploy_syscall(
        HuntFactory::TEST_CLASS_HASH, 0, calldata.span(), false
    ).unwrap();
    
    // Deploy the ChallengeManager contract
    calldata = ArrayTrait::new();
    calldata.append(hunt_factory_contract.into());
    calldata.append(admin.into());
    let challenge_manager_contract = starknet::deploy_syscall(
        ChallengeManager::TEST_CLASS_HASH, 0, calldata.span(), false
    ).unwrap();
    
    // Create dispatchers
    let hunt_factory = IHuntFactoryDispatcher { contract_address: hunt_factory_contract };
    let challenge_manager = IChallengeManagerDispatcher { contract_address: challenge_manager_contract };
    
    // Grant moderator role to moderator address
    hunt_factory.grant_moderator_role(moderator);
    challenge_manager.grant_moderator_role(moderator);
    
    (admin, user, moderator, hunt_factory, challenge_manager)
}

#[test]
fn test_hunt_activation_deactivation() {
    // Setup
    let (admin, user, moderator, hunt_factory, challenge_manager) = setup();
    
    // Create a hunt
    let hunt_id = hunt_factory.create_hunt(HUNT_NAME, START_TIME, END_TIME);
    
    // Verify hunt is active by default
    let hunt = hunt_factory.get_hunt(hunt_id);
    assert(hunt.active == true, 'Hunt should be active by default');
    
    // Deactivate the hunt
    hunt_factory.set_hunt_active(hunt_id, false);
    
    // Verify hunt is now inactive
    let hunt = hunt_factory.get_hunt(hunt_id);
    assert(hunt.active == false, 'Hunt should be inactive');
    
    // Reactivate the hunt
    hunt_factory.set_hunt_active(hunt_id, true);
    
    // Verify hunt is active again
    let hunt = hunt_factory.get_hunt(hunt_id);
    assert(hunt.active == true, 'Hunt should be active again');
}

#[test]
fn test_moderator_can_activate_deactivate() {
    // Setup
    let (admin, user, moderator, hunt_factory, challenge_manager) = setup();
    
    // Create a hunt
    let hunt_id = hunt_factory.create_hunt(HUNT_NAME, START_TIME, END_TIME);
    
    // Set caller as moderator
    set_caller_address(moderator);
    
    // Moderator should be able to deactivate the hunt
    hunt_factory.set_hunt_active(hunt_id, false);
    
    // Verify hunt is now inactive
    let hunt = hunt_factory.get_hunt(hunt_id);
    assert(hunt.active == false, 'Hunt should be inactive');
    
    // Moderator should be able to reactivate the hunt
    hunt_factory.set_hunt_active(hunt_id, true);
    
    // Verify hunt is active again
    let hunt = hunt_factory.get_hunt(hunt_id);
    assert(hunt.active == true, 'Hunt should be active again');
}

#[test]
#[should_panic(expected: ('Not authorized to manage hunt',))]
fn test_user_cannot_activate_deactivate() {
    // Setup
    let (admin, user, moderator, hunt_factory, challenge_manager) = setup();
    
    // Create a hunt
    let hunt_id = hunt_factory.create_hunt(HUNT_NAME, START_TIME, END_TIME);
    
    // Set caller as regular user
    set_caller_address(user);
    
    // User should not be able to deactivate the hunt (should fail)
    hunt_factory.set_hunt_active(hunt_id, false);
}

#[test]
fn test_prevent_submissions_for_inactive_hunt() {
    // Setup
    let (admin, user, moderator, hunt_factory, challenge_manager) = setup();
    
    // Create a hunt
    let hunt_id = hunt_factory.create_hunt(HUNT_NAME, START_TIME, END_TIME);
    
    // Add a challenge
    let challenge_id = challenge_manager.add_challenge(hunt_id, QUESTION, hash_answer(CORRECT_ANSWER), POINTS);
    
    // Deactivate the hunt
    hunt_factory.set_hunt_active(hunt_id, false);
    
    // Set caller as user
    set_caller_address(user);
    
    // User should not be able to submit an answer to a challenge in an inactive hunt
    let result = challenge_manager.submit_answer(hunt_id, challenge_id, CORRECT_ANSWER);
    
    // This should not be reached because submit_answer should panic
    assert(false, 'Should have panicked');
}

#[test]
#[should_panic(expected: ('Hunt is not active',))]
fn test_submit_answer_inactive_hunt() {
    // Setup
    let (admin, user, moderator, hunt_factory, challenge_manager) = setup();
    
    // Create a hunt
    let hunt_id = hunt_factory.create_hunt(HUNT_NAME, START_TIME, END_TIME);
    
    // Add a challenge
    let challenge_id = challenge_manager.add_challenge(hunt_id, QUESTION, hash_answer(CORRECT_ANSWER), POINTS);
    
    // Deactivate the hunt
    hunt_factory.set_hunt_active(hunt_id, false);
    
    // Set caller as user
    set_caller_address(user);
    
    // User should not be able to submit an answer to a challenge in an inactive hunt
    challenge_manager.submit_answer(hunt_id, challenge_id, CORRECT_ANSWER);
}

#[test]
fn test_challenge_activation_deactivation() {
    // Setup
    let (admin, user, moderator, hunt_factory, challenge_manager) = setup();
    
    // Create a hunt
    let hunt_id = hunt_factory.create_hunt(HUNT_NAME, START_TIME, END_TIME);
    
    // Add a challenge
    let challenge_id = challenge_manager.add_challenge(hunt_id, QUESTION, hash_answer(CORRECT_ANSWER), POINTS);
    
    // Verify challenge is active by default
    let challenge = challenge_manager.get_challenge(hunt_id, challenge_id);
    assert(challenge.active == true, 'Challenge should be active by default');
    
    // Deactivate the challenge
    challenge_manager.set_challenge_active(hunt_id, challenge_id, false);
    
    // Verify challenge is now inactive
    let challenge = challenge_manager.get_challenge(hunt_id, challenge_id);
    assert(challenge.active == false, 'Challenge should be inactive');
    
    // Set caller as user
    set_caller_address(user);
    
    // User should not be able to submit an answer to an inactive challenge
    let result = challenge_manager.submit_answer(hunt_id, challenge_id, CORRECT_ANSWER);
    
    // This should not be reached because submit_answer should panic
    assert(false, 'Should have panicked');
}

#[test]
#[should_panic(expected: ('Challenge is not active',))]
fn test_submit_answer_inactive_challenge() {
    // Setup
    let (admin, user, moderator, hunt_factory, challenge_manager) = setup();
    
    // Create a hunt
    let hunt_id = hunt_factory.create_hunt(HUNT_NAME, START_TIME, END_TIME);
    
    // Add a challenge
    let challenge_id = challenge_manager.add_challenge(hunt_id, QUESTION, hash_answer(CORRECT_ANSWER), POINTS);
    
    // Deactivate the challenge
    challenge_manager.set_challenge_active(hunt_id, challenge_id, false);
    
    // Set caller as user
    set_caller_address(user);
    
    // User should not be able to submit an answer to an inactive challenge
    challenge_manager.submit_answer(hunt_id, challenge_id, CORRECT_ANSWER);
}
