// Test file for challenge completion functionality

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
const WRONG_ANSWER: felt252 = 'London';
const POINTS: u64 = 100;

// Test utilities
fn setup() -> (ContractAddress, ContractAddress, IHuntFactoryDispatcher, IChallengeManagerDispatcher) {
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
    
    // Create admin and user addresses
    let admin = contract_address_const::<1>();
    let user = contract_address_const::<2>();
    
    // Set caller as admin
    set_caller_address(admin);
    
    // Create dispatchers
    let hunt_factory = IHuntFactoryDispatcher { contract_address: hunt_factory_contract };
    let challenge_manager = IChallengeManagerDispatcher { contract_address: challenge_manager_contract };
    
    (admin, user, hunt_factory, challenge_manager)
}

// Helper function to hash an answer the same way the contract does
fn hash_answer(answer: felt252) -> felt252 {
    let hash = LegacyHash::hash(0, answer);
    hash
}

#[test]
fn test_submit_correct_answer() {
    // Setup
    let (admin, user, hunt_factory, challenge_manager) = setup();
    
    // Create a hunt
    let hunt_id = hunt_factory.create_hunt(HUNT_NAME, START_TIME, END_TIME);
    
    // Hash the correct answer
    let answer_hash = hash_answer(CORRECT_ANSWER);
    
    // Add a challenge
    let challenge_id = challenge_manager.add_challenge(hunt_id, QUESTION, answer_hash, POINTS);
    
    // Switch to user
    set_caller_address(user);
    
    // Submit the correct answer
    let result = challenge_manager.submit_answer(hunt_id, challenge_id, CORRECT_ANSWER);
    
    // Verify the result is true (correct answer)
    assert(result == true, 'Should return true for correct answer');
    
    // Verify the challenge is marked as completed
    let completed = challenge_manager.has_completed_challenge(user, hunt_id, challenge_id);
    assert(completed == true, 'Challenge should be marked completed');
    
    // Verify the challenge is in the user's completed challenges
    let completed_challenges = challenge_manager.get_user_completed_challenges(user, hunt_id);
    assert(completed_challenges.len() == 1, 'User should have 1 completed challenge');
    assert(*completed_challenges.at(0) == challenge_id, 'Completed challenge ID should match');
}

#[test]
fn test_submit_wrong_answer() {
    // Setup
    let (admin, user, hunt_factory, challenge_manager) = setup();
    
    // Create a hunt
    let hunt_id = hunt_factory.create_hunt(HUNT_NAME, START_TIME, END_TIME);
    
    // Hash the correct answer
    let answer_hash = hash_answer(CORRECT_ANSWER);
    
    // Add a challenge
    let challenge_id = challenge_manager.add_challenge(hunt_id, QUESTION, answer_hash, POINTS);
    
    // Switch to user
    set_caller_address(user);
    
    // Submit the wrong answer
    let result = challenge_manager.submit_answer(hunt_id, challenge_id, WRONG_ANSWER);
    
    // Verify the result is false (wrong answer)
    assert(result == false, 'Should return false for wrong answer');
    
    // Verify the challenge is not marked as completed
    let completed = challenge_manager.has_completed_challenge(user, hunt_id, challenge_id);
    assert(completed == false, 'Challenge should not be marked completed');
    
    // Verify the challenge is not in the user's completed challenges
    let completed_challenges = challenge_manager.get_user_completed_challenges(user, hunt_id);
    assert(completed_challenges.len() == 0, 'User should have 0 completed challenges');
}

#[test]
#[should_panic(expected: ('Challenge already completed',))]
fn test_submit_answer_already_completed() {
    // Setup
    let (admin, user, hunt_factory, challenge_manager) = setup();
    
    // Create a hunt
    let hunt_id = hunt_factory.create_hunt(HUNT_NAME, START_TIME, END_TIME);
    
    // Hash the correct answer
    let answer_hash = hash_answer(CORRECT_ANSWER);
    
    // Add a challenge
    let challenge_id = challenge_manager.add_challenge(hunt_id, QUESTION, answer_hash, POINTS);
    
    // Switch to user
    set_caller_address(user);
    
    // Submit the correct answer
    let result = challenge_manager.submit_answer(hunt_id, challenge_id, CORRECT_ANSWER);
    
    // Try to submit the answer again (should fail)
    challenge_manager.submit_answer(hunt_id, challenge_id, CORRECT_ANSWER);
}
