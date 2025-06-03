// Test file for NFT rewards functionality

use core::option::OptionTrait;
use core::traits::Into;
use core::array::ArrayTrait;
use starknet::{ContractAddress, contract_address_const};
use nft_scavenger_hunt::hunt_factory::{HuntFactory, IHuntFactoryDispatcher, IHuntFactoryDispatcherTrait};
use nft_scavenger_hunt::challenge_manager::{ChallengeManager, IChallengeManagerDispatcher, IChallengeManagerDispatcherTrait};
use nft_scavenger_hunt::reward_nft::{RewardNFT, IRewardNFTDispatcher, IRewardNFTDispatcherTrait};

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
const NFT_NAME: felt252 = 'Scavenger Hunt Rewards';
const NFT_SYMBOL: felt252 = 'SHR';
const NFT_BASE_URI: felt252 = 'https://api.scavengerhunt.com/metadata/';

// Helper function to hash an answer the same way the contract does
fn hash_answer(answer: felt252) -> felt252 {
    let hash = LegacyHash::hash(0, answer);
    hash
}

// Test utilities
fn setup() -> (
    ContractAddress,
    ContractAddress,
    IHuntFactoryDispatcher,
    IChallengeManagerDispatcher,
    IRewardNFTDispatcher
) {
    // Create admin and user addresses
    let admin = contract_address_const::<1>();
    let user = contract_address_const::<2>();
    
    // Set caller as admin
    set_caller_address(admin);
    
    // Deploy the HuntFactory contract
    let hunt_factory_contract = starknet::deploy_syscall(
        HuntFactory::TEST_CLASS_HASH, 0, ArrayTrait::new().span(), false
    ).unwrap();
    
    // Deploy the ChallengeManager contract
    let mut calldata = ArrayTrait::new();
    calldata.append(hunt_factory_contract.into());
    let challenge_manager_contract = starknet::deploy_syscall(
        ChallengeManager::TEST_CLASS_HASH, 0, calldata.span(), false
    ).unwrap();
    
    // Deploy the RewardNFT contract
    calldata = ArrayTrait::new();
    calldata.append(NFT_NAME);
    calldata.append(NFT_SYMBOL);
    calldata.append(NFT_BASE_URI);
    calldata.append(admin.into());
    let reward_nft_contract = starknet::deploy_syscall(
        RewardNFT::TEST_CLASS_HASH, 0, calldata.span(), false
    ).unwrap();
    
    // Create dispatchers
    let hunt_factory = IHuntFactoryDispatcher { contract_address: hunt_factory_contract };
    let challenge_manager = IChallengeManagerDispatcher { contract_address: challenge_manager_contract };
    let reward_nft = IRewardNFTDispatcher { contract_address: reward_nft_contract };
    
    // Set challenge manager in reward NFT
    reward_nft.set_challenge_manager(challenge_manager_contract);
    
    // Set reward NFT in challenge manager
    challenge_manager.set_reward_nft(reward_nft_contract);
    
    (admin, user, hunt_factory, challenge_manager, reward_nft)
}

#[test]
fn test_nft_reward_for_correct_answer() {
    // Setup
    let (admin, user, hunt_factory, challenge_manager, reward_nft) = setup();
    
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
    
    // Verify NFT was minted
    let token_id = challenge_manager.get_challenge_nft_token(user, hunt_id, challenge_id);
    
    // Verify token details
    let (token_hunt_id, token_challenge_id) = reward_nft.get_token_details(token_id);
    assert(token_hunt_id == hunt_id, 'Token hunt ID should match');
    assert(token_challenge_id == challenge_id, 'Token challenge ID should match');
    
    // Verify token ownership
    let token_owner = reward_nft.owner_of(token_id);
    assert(token_owner == user, 'User should own the token');
    
    // Verify challenge is marked as rewarded
    let rewarded = reward_nft.is_challenge_rewarded(hunt_id, challenge_id, user);
    assert(rewarded == true, 'Challenge should be marked as rewarded');
}

#[test]
fn test_no_nft_for_wrong_answer() {
    // Setup
    let (admin, user, hunt_factory, challenge_manager, reward_nft) = setup();
    
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
    
    // Verify user has no NFTs
    let balance = reward_nft.balance_of(user);
    assert(balance == 0, 'User should have no NFTs');
    
    // Verify challenge is not marked as rewarded
    let rewarded = reward_nft.is_challenge_rewarded(hunt_id, challenge_id, user);
    assert(rewarded == false, 'Challenge should not be marked as rewarded');
}

#[test]
#[should_panic(expected: ('Challenge already completed',))]
fn test_prevent_duplicate_submission() {
    // Setup
    let (admin, user, hunt_factory, challenge_manager, reward_nft) = setup();
    
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

#[test]
fn test_multiple_users_same_challenge() {
    // Setup
    let (admin, user1, hunt_factory, challenge_manager, reward_nft) = setup();
    let user2 = contract_address_const::<3>();
    
    // Create a hunt
    let hunt_id = hunt_factory.create_hunt(HUNT_NAME, START_TIME, END_TIME);
    
    // Hash the correct answer
    let answer_hash = hash_answer(CORRECT_ANSWER);
    
    // Add a challenge
    let challenge_id = challenge_manager.add_challenge(hunt_id, QUESTION, answer_hash, POINTS);
    
    // User 1 submits the correct answer
    set_caller_address(user1);
    let result1 = challenge_manager.submit_answer(hunt_id, challenge_id, CORRECT_ANSWER);
    assert(result1 == true, 'User 1 should get correct answer');
    
    // User 2 submits the correct answer
    set_caller_address(user2);
    let result2 = challenge_manager.submit_answer(hunt_id, challenge_id, CORRECT_ANSWER);
    assert(result2 == true, 'User 2 should get correct answer');
    
    // Verify both users got NFTs
    let token_id1 = challenge_manager.get_challenge_nft_token(user1, hunt_id, challenge_id);
    let token_id2 = challenge_manager.get_challenge_nft_token(user2, hunt_id, challenge_id);
    
    // Verify token IDs are different
    assert(token_id1 != token_id2, 'Token IDs should be different');
    
    // Verify token ownership
    let token1_owner = reward_nft.owner_of(token_id1);
    let token2_owner = reward_nft.owner_of(token_id2);
    assert(token1_owner == user1, 'User 1 should own their token');
    assert(token2_owner == user2, 'User 2 should own their token');
    
    // Verify both challenges are marked as rewarded
    let rewarded1 = reward_nft.is_challenge_rewarded(hunt_id, challenge_id, user1);
    let rewarded2 = reward_nft.is_challenge_rewarded(hunt_id, challenge_id, user2);
    assert(rewarded1 == true, 'Challenge should be marked as rewarded for user 1');
    assert(rewarded2 == true, 'Challenge should be marked as rewarded for user 2');
}

#[test]
fn test_user_multiple_challenges() {
    // Setup
    let (admin, user, hunt_factory, challenge_manager, reward_nft) = setup();
    
    // Create a hunt
    let hunt_id = hunt_factory.create_hunt(HUNT_NAME, START_TIME, END_TIME);
    
    // Hash the correct answers
    let answer_hash1 = hash_answer(CORRECT_ANSWER);
    let answer_hash2 = hash_answer('Berlin');
    
    // Add two challenges
    let challenge_id1 = challenge_manager.add_challenge(hunt_id, QUESTION, answer_hash1, POINTS);
    let challenge_id2 = challenge_manager.add_challenge(hunt_id, 'What is the capital of Germany?', answer_hash2, 200);
    
    // Switch to user
    set_caller_address(user);
    
    // Submit correct answers for both challenges
    let result1 = challenge_manager.submit_answer(hunt_id, challenge_id1, CORRECT_ANSWER);
    let result2 = challenge_manager.submit_answer(hunt_id, challenge_id2, 'Berlin');
    
    // Verify both results are true
    assert(result1 == true, 'Should return true for first correct answer');
    assert(result2 == true, 'Should return true for second correct answer');
    
    // Verify NFTs were minted
    let token_id1 = challenge_manager.get_challenge_nft_token(user, hunt_id, challenge_id1);
    let token_id2 = challenge_manager.get_challenge_nft_token(user, hunt_id, challenge_id2);
    
    // Verify token IDs are different
    assert(token_id1 != token_id2, 'Token IDs should be different');
    
    // Verify token details
    let (token1_hunt_id, token1_challenge_id) = reward_nft.get_token_details(token_id1);
    let (token2_hunt_id, token2_challenge_id) = reward_nft.get_token_details(token_id2);
    assert(token1_hunt_id == hunt_id, 'Token 1 hunt ID should match');
    assert(token1_challenge_id == challenge_id1, 'Token 1 challenge ID should match');
    assert(token2_hunt_id == hunt_id, 'Token 2 hunt ID should match');
    assert(token2_challenge_id == challenge_id2, 'Token 2 challenge ID should match');
    
    // Verify user has 2 NFTs
    let balance = reward_nft.balance_of(user);
    assert(balance == 2, 'User should have 2 NFTs');
}

#[test]
#[should_panic(expected: ('Challenge already rewarded',))]
fn test_direct_duplicate_minting_prevention() {
    // Setup
    let (admin, user, hunt_factory, challenge_manager, reward_nft) = setup();
    
    // Create a hunt
    let hunt_id = hunt_factory.create_hunt(HUNT_NAME, START_TIME, END_TIME);
    
    // Hash the correct answer
    let answer_hash = hash_answer(CORRECT_ANSWER);
    
    // Add a challenge
    let challenge_id = challenge_manager.add_challenge(hunt_id, QUESTION, answer_hash, POINTS);
    
    // Set caller as challenge manager to bypass the normal flow
    // This simulates a direct call to mint_reward
    set_caller_address(challenge_manager.contract_address);
    
    // Mint a reward
    reward_nft.mint_reward(user, hunt_id, challenge_id);
    
    // Try to mint another reward for the same challenge (should fail)
    reward_nft.mint_reward(user, hunt_id, challenge_id);
}
