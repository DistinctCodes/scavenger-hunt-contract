use snforge_std::ContractClassTrait;
use nft_scavenger_hunt::referral_rewarder::{
    EnhancedReferralRewarder, IEnhancedReferralRewarderDispatcher, 
    IEnhancedReferralRewarderSafeDispatcher, IEnhancedReferralRewarderDispatcherTrait, IEnhancedReferralRewarderSafeDispatcherTrait
};
use snforge_std::{
    declare,
    DeclareResultTrait, start_cheat_caller_address, stop_cheat_caller_address,
};
use starknet::ContractAddress;

// Test addresses (using numeric values)
pub fn ADMIN() -> ContractAddress {
    'ADMIN'.try_into().unwrap()
}

pub fn REFERRER() -> ContractAddress {
    'REFERRER'.try_into().unwrap()
}

pub fn INVITEE() -> ContractAddress {
    'INVITEE'.try_into().unwrap()
}

pub fn CHALLENGE_MANAGER() -> ContractAddress {
    'CHALLENGE_MANAGER'.try_into().unwrap()
}

pub fn UNAUTHORIZED_USER() -> ContractAddress {
    'UNAUTHORIZED'.try_into().unwrap()
}

fn deploy_contract() -> ContractAddress {
    let class_hash = declare("EnhancedReferralRewarder").unwrap().contract_class();
    let mut calldata = array![];
    ADMIN().serialize(ref calldata);
    CHALLENGE_MANAGER().serialize(ref calldata);
    let (contract_address, _) = class_hash.deploy(@calldata).unwrap();
    contract_address
}

#[test]
fn test_register_with_referral_success() {
    let contract_address = deploy_contract();
    let referral = IEnhancedReferralRewarderDispatcher { contract_address };

    start_cheat_caller_address(contract_address, INVITEE());
    referral.register_with_referral(REFERRER());
    stop_cheat_caller_address(contract_address);

    let stored_referrer = referral.get_referrer(INVITEE());
    assert!(stored_referrer == REFERRER(), "Referrer should be stored correctly");
}

#[test]
#[feature("safe_dispatcher")]
fn test_register_with_referral_already_registered() {
    let contract_address = deploy_contract();
    let referral = IEnhancedReferralRewarderSafeDispatcher { contract_address };

    // First registration
    start_cheat_caller_address(contract_address, INVITEE());
    let first_result = referral.register_with_referral(REFERRER());
    assert!(first_result.is_ok(), "First registration should succeed");

    // Second registration attempt should fail
    let second_result = referral.register_with_referral(REFERRER());
    stop_cheat_caller_address(contract_address);

    assert!(second_result.is_err(), "Second registration should fail");
}

#[test]
#[feature("safe_dispatcher")]
fn test_register_with_zero_address_referrer() {
    let contract_address = deploy_contract();
    let referral = IEnhancedReferralRewarderSafeDispatcher { contract_address };

    start_cheat_caller_address(contract_address, INVITEE());
    let zero_address: ContractAddress = 0.try_into().unwrap();
    let result = referral.register_with_referral(zero_address);
    stop_cheat_caller_address(contract_address);

    assert!(result.is_err(), "Registration with zero address should fail");
}

#[test]
#[feature("safe_dispatcher")]
fn test_register_self_referral() {
    let contract_address = deploy_contract();
    let referral = IEnhancedReferralRewarderSafeDispatcher { contract_address };

    start_cheat_caller_address(contract_address, INVITEE());
    let result = referral.register_with_referral(INVITEE()); // Self-referral
    stop_cheat_caller_address(contract_address);

    assert!(result.is_err(), "Self-referral should fail");
}

#[test]
fn test_get_referrer_no_registration() {
    let contract_address = deploy_contract();
    let referral = IEnhancedReferralRewarderDispatcher { contract_address };

    let stored_referrer = referral.get_referrer(INVITEE());
    let zero_address: ContractAddress = 0.try_into().unwrap();
    assert!(stored_referrer == zero_address, "Should return zero address for unregistered user");
}

#[test]
fn test_has_claimed_reward_initially_false() {
    let contract_address = deploy_contract();
    let referral = IEnhancedReferralRewarderDispatcher { contract_address };

    let has_claimed = referral.has_claimed_reward(REFERRER(), INVITEE());
    assert!(!has_claimed, "Should initially return false for unclaimed rewards");
}

#[test]
fn test_get_required_completions_default() {
    let contract_address = deploy_contract();
    let referral = IEnhancedReferralRewarderDispatcher { contract_address };

    let required = referral.get_required_completions();
    assert!(required == 3, "Default required completions should be 3");
}

#[test]
fn test_set_required_completions_as_admin() {
    let contract_address = deploy_contract();
    let referral = IEnhancedReferralRewarderDispatcher { contract_address };

    start_cheat_caller_address(contract_address, ADMIN());
    referral.set_required_completions(5);
    stop_cheat_caller_address(contract_address);

    let required = referral.get_required_completions();
    assert!(required == 5, "Required completions should be updated to 5");
}

#[test]
#[feature("safe_dispatcher")]
fn test_set_required_completions_unauthorized() {
    let contract_address = deploy_contract();
    let referral = IEnhancedReferralRewarderSafeDispatcher { contract_address };

    start_cheat_caller_address(contract_address, UNAUTHORIZED_USER());
    let result = referral.set_required_completions(5);
    stop_cheat_caller_address(contract_address);

    assert!(result.is_err(), "Unauthorized user should not be able to set required completions");
}

#[test]
fn test_set_challenge_manager_as_admin() {
    let contract_address = deploy_contract();
    let referral = IEnhancedReferralRewarderDispatcher { contract_address };

    let new_challenge_manager = 'NEW_CM'.try_into().unwrap();

    start_cheat_caller_address(contract_address, ADMIN());
    referral.set_challenge_manager(new_challenge_manager);
    stop_cheat_caller_address(contract_address);

    // Note: We can't directly test the internal storage, but we can test that the call succeeded
    // In a real test environment, you might emit an event or have a getter function
}

#[test]
#[feature("safe_dispatcher")]
fn test_set_challenge_manager_unauthorized() {
    let contract_address = deploy_contract();
    let referral = IEnhancedReferralRewarderSafeDispatcher { contract_address };

    let new_challenge_manager = 'NEW_CM'.try_into().unwrap();

    start_cheat_caller_address(contract_address, UNAUTHORIZED_USER());
    let result = referral.set_challenge_manager(new_challenge_manager);
    stop_cheat_caller_address(contract_address);

    assert!(result.is_err(), "Unauthorized user should not be able to set challenge manager");
}

#[test]
#[feature("safe_dispatcher")]
fn test_claim_referral_reward_not_referrer() {
    let contract_address = deploy_contract();
    let referral = IEnhancedReferralRewarderSafeDispatcher { contract_address };

    // Register invitee with referrer
    start_cheat_caller_address(contract_address, INVITEE());
    let _ = referral.register_with_referral(REFERRER());
    stop_cheat_caller_address(contract_address);

    // Try to claim reward as unauthorized user
    start_cheat_caller_address(contract_address, UNAUTHORIZED_USER());
    let result = referral.claim_referral_reward(INVITEE(), 1);
    stop_cheat_caller_address(contract_address);

    assert!(result.is_err(), "Only the referrer should be able to claim reward");
}

#[test]
#[feature("safe_dispatcher")]
fn test_claim_referral_reward_no_registration() {
    let contract_address = deploy_contract();
    let referral = IEnhancedReferralRewarderSafeDispatcher { contract_address };

    // Try to claim reward without registration
    start_cheat_caller_address(contract_address, REFERRER());
    let result = referral.claim_referral_reward(INVITEE(), 1);
    stop_cheat_caller_address(contract_address);

    assert!(result.is_err(), "Should fail when no referral record exists");
}

// Note: Testing claim_referral_reward with successful completion would require
// mocking the ChallengeManager contract, which is more complex and would need
// additional setup with mock contracts

#[test]
fn test_multiple_referrals_different_users() {
    let contract_address = deploy_contract();
    let referral = IEnhancedReferralRewarderDispatcher { contract_address };

    let invitee2 = 'INVITEE2'.try_into().unwrap();

    // First user registers with referrer
    start_cheat_caller_address(contract_address, INVITEE());
    referral.register_with_referral(REFERRER());
    stop_cheat_caller_address(contract_address);

    // Second user registers with same referrer
    start_cheat_caller_address(contract_address, invitee2);
    referral.register_with_referral(REFERRER());
    stop_cheat_caller_address(contract_address);

    // Both should have the same referrer
    assert!(referral.get_referrer(INVITEE()) == REFERRER(), "First invitee should have referrer");
    assert!(referral.get_referrer(invitee2) == REFERRER(), "Second invitee should have referrer");
}

#[test]
fn test_referral_reward_tracking() {
    let contract_address = deploy_contract();
    let referral = IEnhancedReferralRewarderDispatcher { contract_address };

    // Initially, no reward should be claimed
    let has_claimed_before = referral.has_claimed_reward(REFERRER(), INVITEE());
    assert!(!has_claimed_before, "Should initially be false");

    // After registration, still should be false
    start_cheat_caller_address(contract_address, INVITEE());
    referral.register_with_referral(REFERRER());
    stop_cheat_caller_address(contract_address);

    let has_claimed_after_registration = referral.has_claimed_reward(REFERRER(), INVITEE());
    assert!(!has_claimed_after_registration, "Should still be false after registration");
}


#[test]
fn test_contract_initialization() {
    let contract_address = deploy_contract();
    let referral = IEnhancedReferralRewarderDispatcher { contract_address };

    // Test that contract was initialized correctly
    let required_completions = referral.get_required_completions();
    assert!(required_completions == 3, "Should be initialized with 3 required completions");

    // Test that zero addresses work for queries
    let zero_address: ContractAddress = 0.try_into().unwrap();
    let referrer = referral.get_referrer(zero_address);
    assert!(referrer == zero_address, "Should return zero address for zero input");
}