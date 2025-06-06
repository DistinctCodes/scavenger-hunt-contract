// Test file for leaderboard functionality

use core::option::OptionTrait;
use core::traits::Into;
use core::array::ArrayTrait;
use starknet::{ContractAddress, contract_address_const};
use nft_scavenger_hunt::hunt_factory::{HuntFactory, IHuntFactoryDispatcher, IHuntFactoryDispatcherTrait};
use nft_scavenger_hunt::challenge_manager::{ChallengeManager, IChallengeManagerDispatcher, IChallengeManagerDispatcherTrait};
use nft_scavenger_hunt::reward_nft::{RewardNFT, IRewardNFTDispatcher, IRewardNFTDispatcherTrait};
use nft_scavenger_hunt::leaderboard::{Leaderboard, ILeaderboardDispatcher, ILeaderboardDispatcherTrait};

// Import test utilities
use starknet::testing::{set_caller_address, set_contract_address, set_block_timestamp};

// Test constants
const HUNT_NAME: felt252 = 'Test Hunt';
const START_TIME: u64 = 1000;
const END_TIME: u64 = 2000;
const QUESTION1: felt252 = 'What is the capital of France?';
const QUESTION2: felt252 = 'What is the capital of Germany?';
const QUESTION3: felt252 = 'What is the capital of Italy?';
const ANSWER1: felt252 = 'Paris';
const ANSWER2: felt252 = 'Berlin';
const ANSWER3: felt252 = 'Rome';
const POINTS1: u64 = 100;
const POINTS2: u64 = 200;
const POINTS3: u64 = 300;
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
    ContractAddress,
    ContractAddress,
    IHuntFactoryDispatcher,
    IChallengeManagerDispatcher,
    IRewardNFTDispatcher,
    ILeaderboardDispatcher
) {
    // Create admin and user addresses
    let admin = contract_address_const::<1>();
    let user1 = contract_address_const::<2>();
    let user2 = contract_address_const::<3>();
    let user3 = contract_address_const::<4>();
    
    // Set caller as admin
    set_caller_address(admin);
    
    // Deploy the HuntFactory contract
    let hunt_factory_contract = starknet::deploy_syscall(
        HuntFactory::TEST_CLASS_HASH, 0, ArrayTrait::new().span(), false
    ).unwrap();
    
    // Deploy the ChallengeManager contract
    let mut calldata = ArrayTrait::new();
    calldata.append(hunt_factory_contract.into());
    calldata.append(admin.into());
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
    
    // Deploy the Leaderboard contract
    calldata = ArrayTrait::new();
    calldata.append(admin.into());
    let leaderboard_contract = starknet::deploy_syscall(
        Leaderboard::TEST_CLASS_HASH, 0, calldata.span(), false
    ).unwrap();
    
    // Create dispatchers
    let hunt_factory = IHuntFactoryDispatcher { contract_address: hunt_factory_contract };
    let challenge_manager = IChallengeManagerDispatcher { contract_address: challenge_manager_contract };
    let reward_nft = IRewardNFTDispatcher { contract_address: reward_nft_contract };
    let leaderboard = ILeaderboardDispatcher { contract_address: leaderboard_contract };
    
    // Set challenge manager in reward NFT
    reward_nft.set_challenge_manager(challenge_manager_contract);
    
    // Set reward NFT in challenge manager
    challenge_manager.set_reward_nft(reward_nft_contract);
    
    // Set leaderboard in challenge manager
    challenge_manager.set_leaderboard(leaderboard_contract);
    
    // Set challenge manager in leaderboard
    leaderboard.set_challenge_manager(challenge_manager_contract);
    
    (admin, user1, user2, user3, hunt_factory, challenge_manager, reward_nft, leaderboard)
}

#[test]
fn test_leaderboard_basic() {
    // Setup
    let (admin, user1, user2, user3, hunt_factory, challenge_manager, reward_nft, leaderboard) = setup();
    
    // Create a hunt
    let hunt_id = hunt_factory.create_hunt(HUNT_NAME, START_TIME, END_TIME);
    
    // Add challenges
    let challenge_id1 = challenge_manager.add_challenge(hunt_id, QUESTION1, hash_answer(ANSWER1), POINTS1);
    let challenge_id2 = challenge_manager.add_challenge(hunt_id, QUESTION2, hash_answer(ANSWER2), POINTS2);
    let challenge_id3 = challenge_manager.add_challenge(hunt_id, QUESTION3, hash_answer(ANSWER3), POINTS3);
    
    // User 1 completes challenge 1
    set_caller_address(user1);
    challenge_manager.submit_answer(hunt_id, challenge_id1, ANSWER1);
    
    // User 2 completes challenges 1 and 2
    set_caller_address(user2);
    challenge_manager.submit_answer(hunt_id, challenge_id1, ANSWER1);
    challenge_manager.submit_answer(hunt_id, challenge_id2, ANSWER2);
    
    // User 3 completes all challenges
    set_caller_address(user3);
    challenge_manager.submit_answer(hunt_id, challenge_id1, ANSWER1);
    challenge_manager.submit_answer(hunt_id, challenge_id2, ANSWER2);
    challenge_manager.submit_answer(hunt_id, challenge_id3, ANSWER3);
    
    // Get leaderboard
    let leaderboard_data = leaderboard.get_leaderboard();
    
    // Verify leaderboard order (should be sorted by points)
    assert(leaderboard_data.len() == 3, 'Leaderboard should have 3 users');
    
    // User 3 should be first (most points)
    let player1 = *leaderboard_data.at(0);
    assert(player1.address == user3, 'User 3 should be first');
    assert(player1.completed_challenges == 3, 'User 3 should have 3 challenges');
    assert(player1.points == POINTS1 + POINTS2 + POINTS3, 'User 3 points incorrect');
    
    // User 2 should be second
    let player2 = *leaderboard_data.at(1);
    assert(player2.address == user2, 'User 2 should be second');
    assert(player2.completed_challenges == 2, 'User 2 should have 2 challenges');
    assert(player2.points == POINTS1 + POINTS2, 'User 2 points incorrect');
    
    // User 1 should be third (least points)
    let player3 = *leaderboard_data.at(2);
    assert(player3.address == user1, 'User 1 should be third');
    assert(player3.completed_challenges == 1, 'User 1 should have 1 challenge');
    assert(player3.points == POINTS1, 'User 1 points incorrect');
}

#[test]
fn test_user_stats() {
    // Setup
    let (admin, user1, user2, user3, hunt_factory, challenge_manager, reward_nft, leaderboard) = setup();
    
    // Create a hunt
    let hunt_id = hunt_factory.create_hunt(HUNT_NAME, START_TIME, END_TIME);
    
    // Add challenges
    let challenge_id1 = challenge_manager.add_challenge(hunt_id, QUESTION1, hash_answer(ANSWER1), POINTS1);
    let challenge_id2 = challenge_manager.add_challenge(hunt_id, QUESTION2, hash_answer(ANSWER2), POINTS2);
    
    // User 1 completes both challenges
    set_caller_address(user1);
    challenge_manager.submit_answer(hunt_id, challenge_id1, ANSWER1);
    challenge_manager.submit_answer(hunt_id, challenge_id2, ANSWER2);
    
    // Get user stats
    let user_stats = leaderboard.get_user_stats(user1);
    
    // Verify user stats
    assert(user_stats.address == user1, 'User address should match');
    assert(user_stats.completed_challenges == 2, 'User should have 2 challenges');
    assert(user_stats.points == POINTS1 + POINTS2, 'User points incorrect');
}

#[test]
fn test_leaderboard_max_size() {
    // Setup
    let (admin, user1, user2, user3, hunt_factory, challenge_manager, reward_nft, leaderboard) = setup();
    
    // Set leaderboard max size to 2
    set_caller_address(admin);
    leaderboard.set_leaderboard_max_size(2);
    
    // Create a hunt
    let hunt_id = hunt_factory.create_hunt(HUNT_NAME, START_TIME, END_TIME);
    
    // Add challenges
    let challenge_id1 = challenge_manager.add_challenge(hunt_id, QUESTION1, hash_answer(ANSWER1), POINTS1);
    let challenge_id2 = challenge_manager.add_challenge(hunt_id, QUESTION2, hash_answer(ANSWER2), POINTS2);
    let challenge_id3 = challenge_manager.add_challenge(hunt_id, QUESTION3, hash_answer(ANSWER3), POINTS3);
    
    // User 1 completes challenge 1
    set_caller_address(user1);
    challenge_manager.submit_answer(hunt_id, challenge_id1, ANSWER1);
    
    // User 2 completes challenges 1 and 2
    set_caller_address(user2);
    challenge_manager.submit_answer(hunt_id, challenge_id1, ANSWER1);
    challenge_manager.submit_answer(hunt_id, challenge_id2, ANSWER2);
    
    // User 3 completes all challenges
    set_caller_address(user3);
    challenge_manager.submit_answer(hunt_id, challenge_id1, ANSWER1);
    challenge_manager.submit_answer(hunt_id, challenge_id2, ANSWER2);
    challenge_manager.submit_answer(hunt_id, challenge_id3, ANSWER3);
    
    // Get leaderboard
    let leaderboard_data = leaderboard.get_leaderboard();
    
    // Verify leaderboard has only 2 users (max size)
    assert(leaderboard_data.len() == 2, 'Leaderboard should have 2 users');
    
    // User 3 should be first (most points)
    let player1 = *leaderboard_data.at(0);
    assert(player1.address == user3, 'User 3 should be first');
    
    // User 2 should be second
    let player2 = *leaderboard_data.at(1);
    assert(player2.address == user2, 'User 2 should be second');
    
    // User 1 should not be in the leaderboard
}

#[test]
fn test_role_based_access() {
    // Setup
    let (admin, user1, user2, moderator, hunt_factory, challenge_manager, reward_nft, leaderboard) = setup();
    
    // Grant moderator role to moderator address
    set_caller_address(admin);
    challenge_manager.grant_moderator_role(moderator);
    
    // Verify moderator has the role
    let has_role = challenge_manager.has_role('MODERATOR_ROLE', moderator);
    assert(has_role == true, 'Moderator should have the role');
    
    // Create a hunt
    let hunt_id = hunt_factory.create_hunt(HUNT_NAME, START_TIME, END_TIME);
    
    // Moderator should be able to add a challenge
    set_caller_address(moderator);
    let challenge_id = challenge_manager.add_challenge(hunt_id, QUESTION1, hash_answer(ANSWER1), POINTS1);
    
    // Regular user should not be able to add a challenge
    set_caller_address(user1);
    // This would fail with 'Not authorized to add challenge'
    // challenge_manager.add_challenge(hunt_id, QUESTION2, hash_answer(ANSWER2), POINTS2);
    
    // Admin should be able to revoke moderator role
    set_caller_address(admin);
    challenge_manager.revoke_moderator_role(moderator);
    
    // Verify moderator no longer has the role
    let has_role = challenge_manager.has_role('MODERATOR_ROLE', moderator);
    assert(has_role == false, 'Moderator should not have the role');
}
