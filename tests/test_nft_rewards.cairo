// Test file for the NFTRewards contract

use core::option::OptionTrait;
use core::traits::Into;
use core::array::ArrayTrait;
use starknet::{ContractAddress, contract_address_const};
use nft_scavenger_hunt::nft_rewards::{NFTRewards, INFTRewardsDispatcher, INFTRewardsDispatcherTrait};
use openzeppelin::token::erc721::interface::{IERC721Dispatcher, IERC721DispatcherTrait};

// Import test utilities
use starknet::testing::{set_caller_address, set_contract_address};

// Test constants
const NFT_NAME: ByteArray = "Scavenger Hunt NFT";
const NFT_SYMBOL: ByteArray = "SHNFT";
const BASE_URI: ByteArray = "https://api.scavengerhunt.io/metadata/";
const HUNT_ID: u64 = 1;

// Test utilities
fn setup() -> (ContractAddress, ContractAddress, ContractAddress, INFTRewardsDispatcher, IERC721Dispatcher) {
    // Create addresses
    let admin = contract_address_const::<1>();
    let backend = contract_address_const::<2>();
    let user = contract_address_const::<3>();
    
    // Deploy the NFTRewards contract
    let mut calldata = ArrayTrait::new();
    calldata.append(admin.into());
    calldata.append(backend.into());
    calldata.append(NFT_NAME.clone());
    calldata.append(NFT_SYMBOL.clone());
    calldata.append(BASE_URI.clone());
    
    let nft_contract = starknet::deploy_syscall(
        NFTRewards::TEST_CLASS_HASH, 0, calldata.span(), false
    ).unwrap();
    
    // Create dispatchers
    let nft_rewards = INFTRewardsDispatcher { contract_address: nft_contract };
    let erc721 = IERC721Dispatcher { contract_address: nft_contract };
    
    (admin, backend, user, nft_rewards, erc721)
}

#[test]
fn test_mint_reward() {
    // Setup
    let (admin, backend, user, nft_rewards, erc721) = setup();
    
    // Set caller as backend
    set_caller_address(backend);
    
    // Mint a reward NFT
    let token_id = nft_rewards.mint_reward(user, HUNT_ID);
    
    // Verify NFT was minted correctly
    assert(token_id == 1, 'Token ID should be 1');
    assert(erc721.owner_of(token_id) == user, 'User should own the NFT');
    assert(nft_rewards.get_nft_level(token_id) == 1, 'Should start at Bronze level');
    assert(nft_rewards.get_user_hunt_completions(user) == 1, 'Should have 1 completion');
    
    // Verify user tokens
    let user_tokens = nft_rewards.get_user_tokens(user);
    assert(user_tokens.len() == 1, 'User should have 1 token');
    assert(*user_tokens.at(0) == token_id, 'Token ID should match');
}

#[test]
fn test_upgrade_nft() {
    // Setup
    let (admin, backend, user, nft_rewards, erc721) = setup();
    
    // Set caller as backend
    set_caller_address(backend);
    
    // Mint a reward NFT
    let token_id = nft_rewards.mint_reward(user, HUNT_ID);
    
    // Verify initial level
    assert(nft_rewards.get_nft_level(token_id) == 1, 'Should start at Bronze');
    assert(nft_rewards.can_upgrade(token_id), 'Should be upgradeable');
    
    // Upgrade to Silver
    nft_rewards.upgrade_nft(token_id);
    assert(nft_rewards.get_nft_level(token_id) == 2, 'Should be Silver level');
    assert(nft_rewards.can_upgrade(token_id), 'Should still be upgradeable');
    
    // Upgrade to Gold
    nft_rewards.upgrade_nft(token_id);
    assert(nft_rewards.get_nft_level(token_id) == 3, 'Should be Gold level');
    assert(!nft_rewards.can_upgrade(token_id), 'Should not be upgradeable');
}

#[test]
#[should_panic(expected: ('Already at maximum level',))]
fn test_upgrade_nft_max_level() {
    // Setup
    let (admin, backend, user, nft_rewards, erc721) = setup();
    
    // Set caller as backend
    set_caller_address(backend);
    
    // Mint and upgrade to max level
    let token_id = nft_rewards.mint_reward(user, HUNT_ID);
    nft_rewards.upgrade_nft(token_id); // Bronze -> Silver
    nft_rewards.upgrade_nft(token_id); // Silver -> Gold
    
    // Try to upgrade beyond Gold (should fail)
    nft_rewards.upgrade_nft(token_id);
}

#[test]
#[should_panic(expected: ('Caller does not have role',))]
fn test_upgrade_nft_unauthorized() {
    // Setup
    let (admin, backend, user, nft_rewards, erc721) = setup();
    
    // Set caller as backend to mint
    set_caller_address(backend);
    let token_id = nft_rewards.mint_reward(user, HUNT_ID);
    
    // Set caller as user (unauthorized)
    set_caller_address(user);
    
    // Try to upgrade (should fail)
    nft_rewards.upgrade_nft(token_id);
}

#[test]
fn test_backend_role_management() {
    // Setup
    let (admin, backend, user, nft_rewards, erc721) = setup();
    
    // Set caller as admin
    set_caller_address(admin);
    
    // Verify backend has role
    assert(nft_rewards.has_backend_role(backend), 'Backend should have role');
    assert(!nft_rewards.has_backend_role(user), 'User should not have role');
    
    // Grant role to user
    nft_rewards.grant_backend_role(user);
    assert(nft_rewards.has_backend_role(user), 'User should now have role');
    
    // Revoke role from user
    nft_rewards.revoke_backend_role(user);
    assert(!nft_rewards.has_backend_role(user), 'User should not have role');
}

#[test]
fn test_multiple_nfts() {
    // Setup
    let (admin, backend, user, nft_rewards, erc721) = setup();
    
    // Set caller as backend
    set_caller_address(backend);
    
    // Mint multiple NFTs
    let token_id1 = nft_rewards.mint_reward(user, HUNT_ID);
    let token_id2 = nft_rewards.mint_reward(user, HUNT_ID + 1);
    let token_id3 = nft_rewards.mint_reward(user, HUNT_ID + 2);
    
    // Verify user has 3 tokens
    let user_tokens = nft_rewards.get_user_tokens(user);
    assert(user_tokens.len() == 3, 'User should have 3 tokens');
    assert(nft_rewards.get_user_hunt_completions(user) == 3, 'Should have 3 completions');
    
    // Upgrade different tokens to different levels
    nft_rewards.upgrade_nft(token_id1); // Bronze -> Silver
    nft_rewards.upgrade_nft(token_id2); // Bronze -> Silver
    nft_rewards.upgrade_nft(token_id2); // Silver -> Gold
    
    // Verify levels
    assert(nft_rewards.get_nft_level(token_id1) == 2, 'Token 1 should be Silver');
    assert(nft_rewards.get_nft_level(token_id2) == 3, 'Token 2 should be Gold');
    assert(nft_rewards.get_nft_level(token_id3) == 1, 'Token 3 should be Bronze');
}