// Create a new test file for the ChallengeManager contract

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
const ANSWER_HASH: felt252 = 0x1234567890abcdef; // Example hash
const POINTS: u64 = 100;

// Test utilities
fn setup() -> (ContractAddress, IHuntFactoryDispatcher, IChallengeManagerDispatcher) {
    // Deploy the HuntFactory contract
    let hunt_factory_contract = starknet::deploy_syscall(
        HuntFactory::TEST_CLASS_HASH, 0, ArrayTrait::new().span(), false
    ).unwrap();
    
    // Deploy the ChallengeManager contract
    let calldata = ArrayTrait::new();
    calldata.append(hunt_factory_contract.into());
    let challenge_manager_contract = starknet::deploy_syscall(
        ChallengeManager::TEST_CLASS_HASH, 0, calldata.span(), false
    ).unwrap();
    
    // Create admin address
    let admin = contract_address_const::<1>();
    
    // Set caller as admin
    set_caller_address(admin);
    
    // Create dispatchers
    let hunt_factory = IHuntFactoryDispatcher { contract_address: hunt_factory_contract };
    let challenge_manager = IChallengeManagerDispatcher { contract_address: challenge_manager_contract };
    
    (admin, hunt_factory, challenge_manager)
}

#[test]
fn test_add_challenge() {
    // Setup
    let (admin, hunt_factory, challenge_manager) = setup();
    
    // Create a hunt
    let hunt_id = hunt_factory.create_hunt(HUNT_NAME, START_TIME, END_TIME);
    
    // Add a challenge
    let challenge_id = challenge_manager.add_challenge(hunt_id, QUESTION, ANSWER_HASH, POINTS);
    
    // Verify challenge was added correctly
    let challenge = challenge_manager.get_challenge(hunt_id, challenge_id);
    assert(challenge.id == 0, 'Challenge ID should be 0');
    assert(challenge.hunt_id == hunt_id, 'Hunt ID should match');
    assert(challenge.question == QUESTION, 'Question should match');
    assert(challenge.answer_hash == ANSWER_HASH, 'Answer hash should match');
    assert(challenge.points == POINTS, 'Points should match');
    assert(challenge.active == true, 'Challenge should be active');
    
    // Verify hunt challenges
    let hunt_challenges = challenge_manager.get_hunt_challenges(hunt_id);
    assert(hunt_challenges.len() == 1, 'Hunt should have 1 challenge');
    assert(*hunt_challenges.at(0) == challenge_id, 'Challenge ID should match');
}

#[test]
fn test_get_challenge_by_index() {
    // Setup
    let (admin, hunt_factory, challenge_manager) = setup();
    
    // Create a hunt
    let hunt_id = hunt_factory.create_hunt(HUNT_NAME, START_TIME, END_TIME);
    
    // Add multiple challenges
    let challenge_id1 = challenge_manager.add_challenge(hunt_id, QUESTION, ANSWER_HASH, POINTS);
    let challenge_id2 = challenge_manager.add_challenge(hunt_id, 'Second question', ANSWER_HASH, 200);
    
    // Get challenge by index
    let challenge_question = challenge_manager.get_challenge_by_index(hunt_id, 1);
    
    // Verify we get the correct challenge question without answer hash
    assert(challenge_question.id == 1, 'Challenge ID should be 1');
    assert(challenge_question.hunt_id == hunt_id, 'Hunt ID should match');
    assert(challenge_question.question == 'Second question', 'Question should match');
    assert(challenge_question.points == 200, 'Points should match');
}

#[test]
#[should_panic(expected: ('Only hunt creator can add',))]
fn test_add_challenge_not_creator() {
    // Setup
    let (admin, hunt_factory, challenge_manager) = setup();
    
    // Create a hunt
    let hunt_id = hunt_factory.create_hunt(HUNT_NAME, START_TIME, END_TIME);
    
    // Set a different caller
    let other_user = contract_address_const::<2>();
    set_caller_address(other_user);
    
    // Try to add a challenge (should fail)
    challenge_manager.add_challenge(hunt_id, QUESTION, ANSWER_HASH, POINTS);
}

#[test]
#[should_panic(expected: ('Invalid challenge index',))]
fn test_get_challenge_by_invalid_index() {
    // Setup
    let (admin, hunt_factory, challenge_manager) = setup();
    
    // Create a hunt
    let hunt_id = hunt_factory.create_hunt(HUNT_NAME, START_TIME, END_TIME);
    
    // Add a challenge
    let challenge_id = challenge_manager.add_challenge(hunt_id, QUESTION, ANSWER_HASH, POINTS);
    
    // Try to get a challenge with an invalid index (should fail)
    challenge_manager.get_challenge_by_index(hunt_id, 1);
}
