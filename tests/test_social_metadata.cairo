// Test file for social metadata functionality

use core::option::OptionTrait;
use core::traits::Into;
use core::array::ArrayTrait;
use starknet::{ContractAddress, contract_address_const};
use nft_scavenger_hunt::hunt_factory::{HuntFactory, IHuntFactoryDispatcher, IHuntFactoryDispatcherTrait};
use nft_scavenger_hunt::challenge_manager::{ChallengeManager, IChallengeManagerDispatcher, IChallengeManagerDispatcherTrait};
use nft_scavenger_hunt::reward_nft::{RewardNFT, IRewardNFTDispatcher, IRewardNFTDispatcherTrait};
use nft_scavenger_hunt::leaderboard::{Leaderboard, ILeaderboardDispatcher, ILeaderboardDispatcherTrait};
use nft_scavenger_hunt::social_metadata::{SocialMetadata, ISocialMetadataDispatcher, ISocialMetadataDispatcherTrait};

// Import test utilities
use starknet::testing::{set_caller_address, set_contract_address, set_block_timestamp};

// Test constants
const HUNT_NAME: felt252 = 'Test Hunt';
const START_TIME: u64 = 1000;
const END_TIME: u64 = 2000;
const QUESTION: felt252 = 'What is the capital of France?';
const CORRECT_ANSWER: felt252 = 'Paris';
const POINTS: u64 = 100;
const NFT_NAME: felt252 = 'Scavenger Hunt Rewards';
const NFT_SYMBOL: felt252 = 'SHR';
const NFT_BASE_URI: felt252 = 'https://api.scavengerhunt.com/metadata/';
const HUNT_DESCRIPTION: felt252 = 'A test scavenger hunt';
const HUNT_IMAGE: felt252 = 'https://example.com/hunt.png';
const HUNT_EXTERNAL_URL: felt252 = 'https://example.com/hunt';
const CHALLENGE_DESCRIPTION: felt252 = 'A test challenge';
const CHALLENGE_IMAGE: felt252 = 'https://example.com/challenge.png';

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
    IRewardNFTDispatcher,
    ILeaderboardDispatcher,
    ISocialMetadataDispatcher
) {
    // Create admin and user addresses
    let admin = contract_address_const::&lt;1>();
    let user = contract_address_const::&lt;2>();
    
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
    
    // Deploy the SocialMetadata contract
    calldata = ArrayTrait::new();
    calldata.append(admin.into());
    let social_metadata_contract = starknet::deploy_syscall(
        SocialMetadata::TEST_CLASS_HASH, 0, calldata.span(), false
    ).unwrap();
    
    // Create dispatchers
    let hunt_factory = IHuntFactoryDispatcher { contract_address: hunt_factory_contract };
    let challenge_manager = IChallengeManagerDispatcher { contract_address: challenge_manager_contract };
    let reward_nft = IRewardNFTDispatcher { contract_address: reward_nft_contract };
    let leaderboard = ILeaderboardDispatcher { contract_address: leaderboard_contract };
    let social_metadata = ISocialMetadataDispatcher { contract_address: social_metadata_contract };
    
    // Set up contract references
    reward_nft.set_challenge_manager(challenge_manager_contract);
    reward_nft.set_social_metadata(social_metadata_contract);
    challenge_manager.set_reward_nft(reward_nft_contract);
    challenge_manager.set_leaderboard(leaderboard_contract);
    social_metadata.set_hunt_factory(hunt_factory_contract);
    social_metadata.set_challenge_manager(challenge_manager_contract);
    social_metadata.set_leaderboard(leaderboard_contract);
    leaderboard.set_challenge_manager(challenge_manager_contract);
    
    (admin, user, hunt_factory, challenge_manager, reward_nft, leaderboard, social_metadata)
}

#[test]
fn test_update_hunt_metadata() {
    // Setup
    let (admin, user, hunt_factory, challenge_manager, reward_nft, leaderboard, social_metadata) = setup();
    
    // Create a hunt
    let hunt_id = hunt_factory.create_hunt(HUNT_NAME, START_TIME, END_TIME);
    
    // Update hunt metadata
    social_metadata.update_hunt_metadata(
        hunt_id,
        HUNT_DESCRIPTION,
        HUNT_IMAGE,
        HUNT_EXTERNAL_URL
    );
    
    // Get hunt metadata
    let metadata = social_metadata.get_hunt_metadata(hunt_id);
    
    // Verify metadata
    assert(metadata.id == hunt_id, 'Hunt ID should match');
    assert(metadata.name == HUNT_NAME, 'Hunt name should match');
    assert(metadata.description == HUNT_DESCRIPTION, 'Description should match');
    assert(metadata.image_url == HUNT_IMAGE, 'Image URL should match');
    assert(metadata.external_url == HUNT_EXTERNAL_URL, 'External URL should match');
    assert(metadata.start_time == START_TIME, 'Start time should match');
    assert(metadata.end_time == END_TIME, 'End time should match');
    assert(metadata.total_challenges == 0, 'Total challenges should be 0');
}

#[test]
fn test_update_challenge_metadata() {
    // Setup
    let (admin, user, hunt_factory, challenge_manager, reward_nft, leaderboard, social_metadata) = setup();
    
    // Create a hunt
    let hunt_id = hunt_factory.create_hunt(HUNT_NAME, START_TIME, END_TIME);
    
    // Add a challenge
    let challenge_id = challenge_manager.add_challenge(
        hunt_id,
        QUESTION,
        hash_answer(CORRECT_ANSWER),
        POINTS,
        false
    );
    
    // Update challenge metadata
    social_metadata.update_challenge_metadata(
        hunt_id,
        challenge_id,
        CHALLENGE_DESCRIPTION,
        CHALLENGE_IMAGE
    );
    
    // Get challenge metadata
    let metadata = social_metadata.get_challenge_metadata(hunt_id, challenge_id);
    
    // Verify metadata
    assert(metadata.id == challenge_id, 'Challenge ID should match');
    assert(metadata.hunt_id == hunt_id, 'Hunt ID should match');
    assert(metadata.question == QUESTION, 'Question should match');
    assert(metadata.description == CHALLENGE_DESCRIPTION, 'Description should match');
    assert(metadata.image_url == CHALLENGE_IMAGE, 'Image URL should match');
    assert(metadata.points == POINTS, 'Points should match');
}

#[test]
fn test_user_achievements() {
    // Setup
    let (admin, user, hunt_factory, challenge_manager, reward_nft, leaderboard, social_metadata) = setup();
    
    // Create a hunt
    let hunt_id = hunt_factory.create_hunt(HUNT_NAME, START_TIME, END_TIME);
    
    // Add a challenge
    let challenge_id = challenge_manager.add_challenge(
        hunt_id,
        QUESTION,
        hash_answer(CORRECT_ANSWER),
        POINTS,
        false
    );
    
    // Add an achievement
    let achievement_text = 'Completed a challenge!';
    social_metadata.add_user_achievement(user, hunt_id, challenge_id, achievement_text);
    
    // Get user achievements
    let achievements = social_metadata.get_user_achievements(user, hunt_id);
    
    // Verify achievements
    assert(achievements.len() == 1, 'Should have 1 achievement');
    assert(*achievements.at(0) == achievement_text, 'Achievement text should match');
}

#[test]
fn test_social_sharing_templates() {
    // Setup
    let (admin, user, hunt_factory, challenge_manager, reward_nft, leaderboard, social_metadata) = setup();
    
    // Update sharing templates
    let hunt_template = 'I finished {hunt_name}!';
    let challenge_template = 'I solved {challenge_name}!';
    let leaderboard_template = 'I\'m #{position} on the leaderboard!';
    
    social_metadata.update_sharing_template('hunt_completion', hunt_template);
    social_metadata.update_sharing_template('challenge_completion', challenge_template);
    social_metadata.update_sharing_template('leaderboard_position', leaderboard_template);
    
    // Create a hunt
    let hunt_id = hunt_factory.create_hunt(HUNT_NAME, START_TIME, END_TIME);
    
    // Update hunt metadata
    social_metadata.update_hunt_metadata(
        hunt_id,
        HUNT_DESCRIPTION,
        HUNT_IMAGE,
        HUNT_EXTERNAL_URL
    );
    
    // Add a challenge
    let challenge_id = challenge_manager.add_challenge(
        hunt_id,
        QUESTION,
        hash_answer(CORRECT_ANSWER),
        POINTS,
        false
    );
    
    // Update challenge metadata
    social_metadata.update_challenge_metadata(
        hunt_id,
        challenge_id,
        CHALLENGE_DESCRIPTION,
        CHALLENGE_IMAGE
    );
    
    // Switch to user
    set_caller_address(user);
    
    // Complete the challenge
    challenge_manager.submit_answer(hunt_id, challenge_id, CORRECT_ANSWER);
    
    // Try to generate challenge completion share
    let share = social_metadata.generate_challenge_completion_share(user, hunt_id, challenge_id);
    
    // Verify share content
    assert(share.title == QUESTION, 'Title should match question');
    assert(share.description == challenge_template, 'Description should match template');
    assert(share.image_url == CHALLENGE_IMAGE, 'Image URL should match');
}

#[test]
fn test_nft_social_sharing() {
    // Setup
    let (admin, user, hunt_factory, challenge_manager, reward_nft, leaderboard, social_metadata) = setup();
    
    // Create a hunt
    let hunt_id = hunt_factory.create_hunt(HUNT_NAME, START_TIME, END_TIME);
    
    // Update hunt metadata
    social_metadata.update_hunt_metadata(
        hunt_id,
        HUNT_DESCRIPTION,
        HUNT_IMAGE,
        HUNT_EXTERNAL_URL
    );
    
    // Add a challenge
    let challenge_id = challenge_manager.add_challenge(
        hunt_id,
        QUESTION,
        hash_answer(CORRECT_ANSWER),
        POINTS,
        false
    );
    
    // Update challenge metadata
    social_metadata.update_challenge_metadata(
        hunt_id,
        challenge_id,
        CHALLENGE_DESCRIPTION,
        CHALLENGE_IMAGE
    );
    
    // Switch to user
    set_caller_address(user);
    
    // Complete the challenge
    challenge_manager.submit_answer(hunt_id, challenge_id, CORRECT_ANSWER);
    
    // Get the NFT token ID
    let token_id = challenge_manager.get_challenge_nft_token(user, hunt_id, challenge_id);
    
    // Generate token share
    let share = reward_nft.generate_token_share(token_id);
    
    // Verify share content
    assert(share.title == QUESTION, 'Title should match question');
    assert(share.image_url == CHALLENGE_IMAGE, 'Image URL should match');
}
