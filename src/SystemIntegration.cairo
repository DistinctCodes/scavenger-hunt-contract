// SPDX-License-Identifier: MIT
// SystemIntegration.cairo
// Cairo 1 / StarkNet contract acting as a central integration hub for Scavenger Hunt modules.
// Contains: ISystemIntegration interface, SystemIntegration contract, and unit tests.

%lang starknet

use core::array::ArrayTrait;
use core::array::Array;
use core::option::Option;
use core::option::OptionTrait;
use core::num::traits::Zero;
use starknet::ContractAddress;
use starknet::get_caller_address;
use starknet::get_block_timestamp;
use starknet::storage::LegacyMap;

// =====================
// External module stubs
// =====================
extern contract IScavengerHuntNFT {
    fn mint(to: ContractAddress, token_id: u128, rarity: u8) -> ();
}

extern contract IGameManagement {
    fn sync_player_data(player: ContractAddress) -> ();
}

extern contract IPuzzleSystem {
    fn verify_solution(challenge_id: u128, player: ContractAddress, proof_len: u32, proof: felt252*) -> (bool);
}

extern contract IPlayerProgress {
    fn add_experience(player: ContractAddress, amount: u128) -> ();
}

extern contract IChallengeVerification {
    fn verify(challenge_id: u128, player: ContractAddress, proof_len: u32, proof: felt252*) -> (bool);
}

// =====================
// Interface Definition
// =====================

#[starknet::interface]
trait ISystemIntegration<TContractState> {
    fn sync_player_data(self: @TContractState, player: ContractAddress);
    fn validate_cross_contract_call(self: @TContractState, caller: ContractAddress, target: ContractAddress) -> bool;
    fn get_contract_health_status(self: @TContractState) -> Array<(ContractAddress, bool)>;

    fn batch_mint_rewards(self: @TContractState, players: Array<ContractAddress>, puzzle_ids: Array<u128>, rarities: Array<u8>);
    fn batch_update_progress(self: @TContractState, players: Array<ContractAddress>, experiences: Array<u128>);
    fn batch_verify_solutions(self: @TContractState, challenge_ids: Array<u128>, players: Array<ContractAddress>, proofs: Array<Array<felt252>>) -> Array<bool>;

    fn get_recent_system_events(self: @TContractState, limit: u32) -> Array<felt252>;
    fn get_player_activity_feed(self: @TContractState, player: ContractAddress, limit: u32) -> Array<felt252>;
}

// ================
// Events
// ================

#[event]
struct CrossContractCallMade {
    caller: ContractAddress,
    target: ContractAddress,
    success: bool,
}

#[event]
struct BatchOperationCompleted {
    op_name: felt252,
    count: u32,
}

#[event]
struct ContractHealthUpdated {
    contract: ContractAddress,
    healthy: bool,
}

#[event]
struct PlayerDataSynced {
    player: ContractAddress,
    timestamp: u64,
}

// =================
// Storage
// =================

#[storage]
struct Storage {
    owner: ContractAddress,

    // integrated contracts
    nft_contract: ContractAddress,
    game_contract: ContractAddress,
    puzzle_contract: ContractAddress,
    progress_contract: ContractAddress,
    verification_contract: ContractAddress,

    // auth & health maps
    authorized_callers: LegacyMap<ContractAddress, bool>,
    contract_health: LegacyMap<ContractAddress, bool>,
    last_sync_time: LegacyMap<ContractAddress, u64>,

    // recent events (capped circular buffer)
    recent_events_len: u32,
    recent_events_cap: u32,
    recent_event_at: LegacyMap<u32, felt252>,

    // player activities: map player -> (len + capped entries stored by index)
    player_activity_len: LegacyMap<ContractAddress, u32>,
    player_activity_cap: u32,
    player_activity_at: LegacyMap<(ContractAddress, u32), felt252>,
}

// ======================
// Contract Implementation
// ======================

#[starknet::contract]
mod SystemIntegration {
    use super::*;

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, recent_events_cap: u32, player_activity_cap: u32) {
        self.owner.write(owner);
        self.nft_contract.write(ContractAddress::from_felt(0));
        self.game_contract.write(ContractAddress::from_felt(0));
        self.puzzle_contract.write(ContractAddress::from_felt(0));
        self.progress_contract.write(ContractAddress::from_felt(0));
        self.verification_contract.write(ContractAddress::from_felt(0));

        self.recent_events_len.write(0_u32);
        self.recent_events_cap.write(recent_events_cap);

        self.player_activity_cap.write(player_activity_cap);
    }

    // ---------------------------------
    // Access control helpers
    // ---------------------------------
    fn only_owner(self: @ContractState) {
        let caller = get_caller_address();
        assert(caller == self.owner.read(), 'ONLY_OWNER');
    }

    fn _emit_recent_event(ref self: ContractState, raw: felt252) {
        let mut len = self.recent_events_len.read();
        let cap = self.recent_events_cap.read();
        // insert at len % cap
        if cap == 0_u32 { return (); }
        let idx = len % cap;
        self.recent_event_at.write(idx, raw);
        // increment length until reaching cap, then keep cap but rotate index
        if len < cap { len = len + 1_u32; self.recent_events_len.write(len); } else { self.recent_events_len.write(len); }
    }

    fn _push_player_activity(ref self: ContractState, player: ContractAddress, raw: felt252) {
        let cap = self.player_activity_cap.read();
        if cap == 0_u32 { return (); }
        let mut len = self.player_activity_len.read(player);
        let idx = len % cap;
        self.player_activity_at.write((player, idx), raw);
        if len < cap { len = len + 1_u32; self.player_activity_len.write(player, len); } else { self.player_activity_len.write(player, len); }
    }

    // -------------------------------
    // External admin helpers
    // -------------------------------
    #[external]
    fn set_integrations(ref self: ContractState, nft: ContractAddress, game: ContractAddress, puzzle: ContractAddress, progress: ContractAddress, verification: ContractAddress) {
        self.only_owner();
        self.nft_contract.write(nft);
        self.game_contract.write(game);
        self.puzzle_contract.write(puzzle);
        self.progress_contract.write(progress);
        self.verification_contract.write(verification);

        // mark contracts healthy by default
        self.contract_health.write(nft, true);
        self.contract_health.write(game, true);
        self.contract_health.write(puzzle, true);
        self.contract_health.write(progress, true);
        self.contract_health.write(verification, true);
    }

    #[external]
    fn set_authorized_caller(ref self: ContractState, addr: ContractAddress, enabled: bool) {
        self.only_owner();
        self.authorized_callers.write(addr, enabled);
    }

    #[external]
    fn update_contract_health(ref self: ContractState, addr: ContractAddress, healthy: bool) {
        self.only_owner();
        self.contract_health.write(addr, healthy);
        emit(ContractHealthUpdated { contract: addr, healthy });
    }

    // -------------------------------
    // Core Interface Implementation
    // -------------------------------
    #[external]
    fn sync_player_data(ref self: ContractState, player: ContractAddress) {
        // call game_contract.sync_player_data(player) if set
        let game = self.game_contract.read();
        if game != ContractAddress::from_felt(0) {
            // best-effort external call
            let _ = IGameManagement::sync_player_data(game, player);
            self.last_sync_time.write(player, get_block_timestamp());
            emit(PlayerDataSynced { player, timestamp: get_block_timestamp() });
            self._emit_recent_event(0xfeed_c0ffee_u128 as felt252);
            self._push_player_activity(player, 0xfeed_c0ffee_u128 as felt252);
        }
    }

    #[external]
    fn validate_cross_contract_call(ref self: ContractState, caller: ContractAddress, target: ContractAddress) -> bool {
        let auth = self.authorized_callers.read(caller);
        let healthy = self.contract_health.read(target);
        let ok = auth && healthy;
        emit(CrossContractCallMade { caller, target, success: ok });
        ok
    }

    #[external]
    fn get_contract_health_status(ref self: ContractState) -> Array<(ContractAddress, bool)> {
        let mut out: Array<(ContractAddress, bool)> = ArrayTrait::new();
        let nft = self.nft_contract.read();
        if nft != ContractAddress::from_felt(0) { out.append((nft, self.contract_health.read(nft))); }
        let game = self.game_contract.read();
        if game != ContractAddress::from_felt(0) { out.append((game, self.contract_health.read(game))); }
        let puzzle = self.puzzle_contract.read();
        if puzzle != ContractAddress::from_felt(0) { out.append((puzzle, self.contract_health.read(puzzle))); }
        let progress = self.progress_contract.read();
        if progress != ContractAddress::from_felt(0) { out.append((progress, self.contract_health.read(progress))); }
        let ver = self.verification_contract.read();
        if ver != ContractAddress::from_felt(0) { out.append((ver, self.contract_health.read(ver))); }
        out
    }

    #[external]
    fn batch_mint_rewards(ref self: ContractState, players: Array<ContractAddress>, puzzle_ids: Array<u128>, rarities: Array<u8>) {
        // Array length checks
        let len_players = players.len();
        let len_pids = puzzle_ids.len();
        let len_r = rarities.len();
        assert(len_players == len_pids, 'LEN_MISMATCH');
        assert(len_players == len_r, 'LEN_MISMATCH');

        let nft = self.nft_contract.read();
        assert(nft != ContractAddress::from_felt(0), 'NFT_NOT_SET');

        let mut i: u32 = 0_u32;
        loop {
            if i >= len_players { break; }
            let p = players.get(i);
            let pid = puzzle_ids.get(i);
            let r = rarities.get(i);
            let _ = IScavengerHuntNFT::mint(nft, p, pid, r);
            i = i + 1_u32;
        };

        emit(BatchOperationCompleted { op_name: 'batch_mint_rewards' , count: len_players });
    }

    #[external]
    fn batch_update_progress(ref self: ContractState, players: Array<ContractAddress>, experiences: Array<u128>) {
        let len_players = players.len();
        let len_exp = experiences.len();
        assert(len_players == len_exp, 'LEN_MISMATCH');

        let progress = self.progress_contract.read();
        assert(progress != ContractAddress::from_felt(0), 'PROGRESS_NOT_SET');

        let mut i: u32 = 0_u32;
        loop {
            if i >= len_players { break; }
            let p = players.get(i);
            let xp = experiences.get(i);
            let _ = IPlayerProgress::add_experience(progress, p, xp);
            self._push_player_activity(p, 0xadd_xp_u128 as felt252);
            i = i + 1_u32;
        };
        emit(BatchOperationCompleted { op_name: 'batch_update_progress', count: len_players });
    }

    #[external]
    fn batch_verify_solutions(ref self: ContractState, challenge_ids: Array<u128>, players: Array<ContractAddress>, proofs: Array<Array<felt252>>) -> Array<bool> {
        let len_ch = challenge_ids.len();
        let len_p = players.len();
        let len_pf = proofs.len();
        assert(len_ch == len_p, 'LEN_MISMATCH');
        assert(len_ch == len_pf, 'LEN_MISMATCH');

        let puzzle = self.puzzle_contract.read();
        assert(puzzle != ContractAddress::from_felt(0), 'PUZZLE_NOT_SET');

        let mut results: Array<bool> = ArrayTrait::new();
        let mut i: u32 = 0_u32;
        loop {
            if i >= len_ch { break; }
            let cid = challenge_ids.get(i);
            let p = players.get(i);
            let proof_arr = proofs.get(i);
            // prepare raw pointer
            let proof_len = proof_arr.len();
            // In Cairo, passing array pointer to extern may require special handling — using a best-effort call
            let ptr = proof_arr.as_ptr();
            let verified = IPuzzleSystem::verify_solution(puzzle, cid, p, proof_len, ptr);
            results.append(verified);
            i = i + 1_u32;
        };

        emit(BatchOperationCompleted { op_name: 'batch_verify_solutions', count: len_ch });
        results
    }

    #[external]
    fn get_recent_system_events(ref self: ContractState, limit: u32) -> Array<felt252> {
        let mut out: Array<felt252> = ArrayTrait::new();
        let cap = self.recent_events_cap.read();
        if cap == 0_u32 { return out; }
        let mut len = self.recent_events_len.read();
        if len > cap { len = cap; }
        // produce reverse chronological order — newest first
        let mut i: u32 = 0_u32;
        while i < limit {
            if i >= len { break; }
            // newest index = (len - 1 - i) % cap
            let idx = (len - 1_u32 - i) % cap;
            let e = self.recent_event_at.read(idx);
            out.append(e);
            i = i + 1_u32;
        }
        out
    }

    #[external]
    fn get_player_activity_feed(ref self: ContractState, player: ContractAddress, limit: u32) -> Array<felt252> {
        let mut out: Array<felt252> = ArrayTrait::new();
        let cap = self.player_activity_cap.read();
        if cap == 0_u32 { return out; }
        let mut len = self.player_activity_len.read(player);
        if len > cap { len = cap; }
        let mut i: u32 = 0_u32;
        while i < limit {
            if i >= len { break; }
            let idx = (len - 1_u32 - i) % cap;
            let e = self.player_activity_at.read((player, idx));
            out.append(e);
            i = i + 1_u32;
        }
        out
    }
}

// =====================
// Unit Tests (snforge_std style placeholders)
// =====================

#[cfg(test)]
mod tests {
    use super::SystemIntegration;
    use starknet::testing::{set_caller_address};
    use starknet::ContractAddress;

    #[test]
    fn test_constructor_and_setters() {
        let owner = ContractAddress::from_felt(0x1);
        let mut c = SystemIntegration::default();
        // Simulate constructor call
        SystemIntegration::constructor(&mut c, owner, 10_u32, 10_u32);
        // only owner can set integrations
        set_caller_address(owner);
        SystemIntegration::set_integrations(&mut c, ContractAddress::from_felt(0x10), ContractAddress::from_felt(0x11), ContractAddress::from_felt(0x12), ContractAddress::from_felt(0x13), ContractAddress::from_felt(0x14));

        let status = SystemIntegration::get_contract_health_status(&mut c);
        assert(status.len() == 5_u32, 'Expected 5 integrated contracts');
    }

    #[test]
    fn test_authorization_and_validate() {
        let owner = ContractAddress::from_felt(0x1);
        let caller = ContractAddress::from_felt(0x2);
        let mut c = SystemIntegration::default();
        SystemIntegration::constructor(&mut c, owner, 5_u32, 5_u32);
        set_caller_address(owner);
        SystemIntegration::set_authorized_caller(&mut c, caller, true);
        // validate: caller authorized but target not set (health default false)
        let res = SystemIntegration::validate_cross_contract_call(&mut c, caller, ContractAddress::from_felt(0x99));
        // res should be false because target health is false (not set)
        assert(!res, 'expected false');
    }

    #[test]
    fn test_batch_length_checks() {
        let owner = ContractAddress::from_felt(0x1);
        let mut c = SystemIntegration::default();
        SystemIntegration::constructor(&mut c, owner, 5_u32, 5_u32);
        set_caller_address(owner);
        SystemIntegration::set_integrations(&mut c, ContractAddress::from_felt(0x10), ContractAddress::from_felt(0x11), ContractAddress::from_felt(0x12), ContractAddress::from_felt(0x13), ContractAddress::from_felt(0x14));

        // Prepare mismatched arrays
        let mut players: Array<ContractAddress> = ArrayTrait::new();
        let mut puzzle_ids: Array<u128> = ArrayTrait::new();
        players.append(ContractAddress::from_felt(0x21));
        // puzzle_ids left empty to cause LEN_MISMATCH

        // Expect assertion when calling batch_mint_rewards
        // Using a try/catch pattern is not shown; in real tests you should assert the failure.
    }
}
