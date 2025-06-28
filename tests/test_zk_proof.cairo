// Test file for ZK proof functionality

use core::option::OptionTrait;
use core::traits::Into;
use core::array::ArrayTrait;
use starknet::{ContractAddress, contract_address_const};
use nft_scavenger_hunt::hunt_factory::{HuntFactory, IHuntFactoryDispatcher, IHuntFactoryDispatcherTrait};
use nft_scavenger_hunt::challenge_manager::{ChallengeManager, IChallengeManagerDispatcher, IChallengeManagerDispatcherTrait};
use nft_scavenger_hunt::zk_verifier::{ZKVerifier, IZKVerifierDispatcher, IZKVerifierDispatcherTrait};

// Import test utilities
use starknet::testing::{set_caller_address, set_contract_address, set_block_timestamp};

// Test constants
const HUNT_NAME: felt252 = 'Test Hunt';
const START_TIME: u64 = 1000;
const END_TIME: u64 = 2000;
const QUESTION: felt252 = 'What is the capital of France?';
const POINTS: u64 = 100;

// Test utilities
fn setup() -> (
    ContractAddress,
    ContractAddress,
    IHuntFactoryDispatcher,
    IChallengeManagerDispatcher,
    IZKVerifierDispatcher
) {
    // Create admin and user addresses
    let admin = contract_address_const::<1>();
    let user = contract_address_const::<2>();
    
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
    
    // Deploy the ZKVerifier contract
    calldata = ArrayTrait::new();
    calldata.append(admin.into());
    let zk_verifier_contract = starknet::deploy_syscall(
        ZKVerifier::TEST_CLASS_HASH, 0, calldata.span(), false
    ).unwrap();
    
    // Create dispatchers
    let hunt_factory = IHuntFactoryDispatcher { contract_address: hunt_factory_contract };
    let challenge_manager = IChallengeManagerDispatcher { contract_address: challenge_manager_contract };
    let zk_verifier = IZKVerifierDispatcher { contract_address: zk_verifier_contract };
    
    // Set ZK verifier in challenge manager
    challenge_manager.set_zk_verifier(zk_verifier_contract);
    
    (admin, user, hunt_factory, challenge_manager, zk_verifier)
}

// Helper function to create a sample verification key
fn create_sample_verification_key() -> ZKVerifier::VerificationKey {
    ZKVerifier::VerificationKey {
        alpha1_x: 1,
        alpha1_y: 2,
        beta2_x: (3, 4),
        beta2_y: (5, 6),
        gamma2_x: (7, 8),
        gamma2_y: (9, 10),
        delta2_x: (11, 12),
        delta2_y: (13, 14),
        ic_length: 2,
    }
}

// Helper function to create a sample proof
fn create_sample_proof() -> ZKVerifier::Proof {
    let mut public_inputs = ArrayTrait::new();
    public_inputs.append(42);
    
    ZKVerifier::Proof {
        a_x: 1,
        a_y: 2,
        b_x: (3, 4),
        b_y: (5, 6),
        c_x: 7,
        c_y: 8,
        public_inputs: public_inputs,
    }
}

#[test]
fn test_add_zk_challenge() {
    // Setup
    let (admin, user, hunt_factory, challenge_manager, zk_verifier) = setup();
    
    // Create a hunt
    let hunt_id = hunt_factory.create_hunt(HUNT_NAME, START_TIME, END_TIME);
    
    // Add a ZK challenge
    let challenge_id = challenge_manager.add_challenge(hunt_id, QUESTION, 0, POINTS, true);
    
    // Verify challenge was added correctly
    let challenge = challenge_manager.get_challenge(hunt_id, challenge_id);
    assert(challenge.id == 0, 'Challenge ID should be 0');
    assert(challenge.hunt_id == hunt_id, 'Hunt ID should match');
    assert(challenge.question == QUESTION, 'Question should match');
    assert(challenge.points == POINTS, 'Points should match');
    assert(challenge.active == true, 'Challenge should be active');
    assert(challenge.uses_zk_proof == true, 'Challenge should use ZK proofs');
    
    // Verify challenge uses ZK proofs
    let uses_zk_proof = challenge_manager.challenge_uses_zk_proof(hunt_id, challenge_id);
    assert(uses_zk_proof == true, 'Challenge should use ZK proofs');
}

#[test]
fn test_set_verification_key() {
    // Setup
    let (admin, user, hunt_factory, challenge_manager, zk_verifier) = setup();
    
    // Create a hunt
    let hunt_id = hunt_factory.create_hunt(HUNT_NAME, START_TIME, END_TIME);
    
    // Add a ZK challenge
    let challenge_id = challenge_manager.add_challenge(hunt_id, QUESTION, 0, POINTS, true);
    
    // Create a sample verification key
    let vk = create_sample_verification_key();
    
    // Set verification key
    challenge_manager.set_verification_key(hunt_id, challenge_id, vk);
    
    // Verify verification key was set
    let has_vk = zk_verifier.has_verification_key(hunt_id, challenge_id);
    assert(has_vk == true, 'Verification key should be set');
    
    // Get verification key
    let stored_vk = zk_verifier.get_verification_key(hunt_id, challenge_id);
    assert(stored_vk.alpha1_x == vk.alpha1_x, 'Alpha1 x should match');
    assert(stored_vk.alpha1_y == vk.alpha1_y, 'Alpha1 y should match');
}

#[test]
#[should_panic(expected: ('Challenge does not use ZK proofs',))]
fn test_set_verification_key_non_zk_challenge() {
    // Setup
    let (admin, user, hunt_factory, challenge_manager, zk_verifier) = setup();
    
    // Create a hunt
    let hunt_id = hunt_factory.create_hunt(HUNT_NAME, START_TIME, END_TIME);
    
    // Add a non-ZK challenge
    let challenge_id = challenge_manager.add_challenge(hunt_id, QUESTION, 0, POINTS, false);
    
    // Create a sample verification key
    let vk = create_sample_verification_key();
    
    // Try to set verification key for a non-ZK challenge (should fail)
    challenge_manager.set_verification_key(hunt_id, challenge_id, vk);
}

#[test]
fn test_submit_zk_proof() {
    // Setup
    let (admin, user, hunt_factory, challenge_manager, zk_verifier) = setup();
    
    // Create a hunt
    let hunt_id = hunt_factory.create_hunt(HUNT_NAME, START_TIME, END_TIME);
    
    // Add a ZK challenge
    let challenge_id = challenge_manager.add_challenge(hunt_id, QUESTION, 0, POINTS, true);
    
    // Create a sample verification key
    let vk = create_sample_verification_key();
    
    // Set verification key
    challenge_manager.set_verification_key(hunt_id, challenge_id, vk);
    
    // Create a sample proof
    let proof = create_sample_proof();
    
    // Switch to user
    set_caller_address(user);
    
    // Submit proof
    let result = challenge_manager.submit_zk_proof(hunt_id, challenge_id, proof);
    
    // Verify result (should be true since our mock verifier always returns true)
    assert(result == true, 'Proof should be verified');
    
    // Verify challenge is marked as completed
    let completed = challenge_manager.has_completed_challenge(user, hunt_id, challenge_id);
    assert(completed == true, 'Challenge should be marked completed');
}

#[test]
#[should_panic(expected: ('Challenge does not use ZK proofs',))]
fn test_submit_zk_proof_non_zk_challenge() {
    // Setup
    let (admin, user, hunt_factory, challenge_manager, zk_verifier) = setup();
    
    // Create a hunt
    let hunt_id = hunt_factory.create_hunt(HUNT_NAME, START_TIME, END_TIME);
    
    // Add a non-ZK challenge
    let challenge_id = challenge_manager.add_challenge(hunt_id, QUESTION, 0, POINTS, false);
    
    // Create a sample proof
    let proof = create_sample_proof();
    
    // Switch to user
    set_caller_address(user);
    
    // Try to submit proof for a non-ZK challenge (should fail)
    challenge_manager.submit_zk_proof(hunt_id, challenge_id, proof);
}

#[test]
#[should_panic(expected: ('Challenge uses ZK proofs',))]
fn test_submit_answer_zk_challenge() {
    // Setup
    let (admin, user, hunt_factory, challenge_manager, zk_verifier) = setup();
    
    // Create a hunt
    let hunt_id = hunt_factory.create_hunt(HUNT_NAME, START_TIME, END_TIME);
    
    // Add a ZK challenge
    let challenge_id = challenge_manager.add_challenge(hunt_id, QUESTION, 0, POINTS, true);
    
    // Switch to user
    set_caller_address(user);
    
    // Try to submit a regular answer for a ZK challenge (should fail)
    challenge_manager.submit_answer(hunt_id, challenge_id, 'Paris');
}

#[test]
#[should_panic(expected: ('Challenge already completed',))]
fn test_prevent_duplicate_zk_proof_submission() {
    // Setup
    let (admin, user, hunt_factory, challenge_manager, zk_verifier) = setup();
    
    // Create a hunt
    let hunt_id = hunt_factory.create_hunt(HUNT_NAME, START_TIME, END_TIME);
    
    // Add a ZK challenge
    let challenge_id = challenge_manager.add_challenge(hunt_id, QUESTION, 0, POINTS, true);
    
    // Create a sample verification key
    let vk = create_sample_verification_key();
    
    // Set verification key
    challenge_manager.set_verification_key(hunt_id, challenge_id, vk);
    
    // Create a sample proof
    let proof = create_sample_proof();
    
    // Switch to user
    set_caller_address(user);
    
    // Submit proof
    let result = challenge_manager.submit_zk_proof(hunt_id, challenge_id, proof);
    
    // Try to submit proof again (should fail)
    challenge_manager.submit_zk_proof(hunt_id, challenge_id, proof);
}
