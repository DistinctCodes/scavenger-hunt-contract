// SPDX-License-Identifier: MIT
// GameManagement.cairo — Puzzle-Based NFT Game Session Manager
// Cairo 1.0 compatible
//
// Notes:
// - This contract manages game session lifecycle, player registration, basic per-session
//   leaderboards, XP/leveling, and fee accounting.
// - Token/NFT transfers and refunds are intentionally left as TODOs with clear comments.
// - Uses simple storage patterns (double-key maps) to avoid unsupported nested maps.
// - Public getters are provided for most entities, plus array-returning helpers
//   (players per session, leaderboard entries) with safe loops.
// - Access control: owner + game masters. Emergency pause supported.
//
// ==========================
// = Imports & Declarations =
// ==========================

%lang starknet

use core::array::ArrayTrait;
use core::array::Array;
use core::bool::BoolTrait;
use core::traits::Into;
use core::option::Option;
use core::option::OptionTrait;
use core::result::ResultTrait;
use core::serde::Serde;
use core::num::traits::Zero;
use starknet::ContractAddress;
use starknet::get_caller_address;
use starknet::get_block_timestamp;
use starknet::storage::LegacyMap;

#[derive(Copy, Drop, Serde, PartialEq, Eq)]
enum GameStatus {
    Created: (),
    Active: (),
    Paused: (),
    Completed: (),
    Cancelled: (),
}

#[derive(Copy, Drop, Serde)]
struct GameSession {
    id: u128,
    name: felt252,
    start_time: u64,
    end_time: u64,
    max_players: u32,
    entry_fee: u128,         // In the platform's ERC20 unit (e.g., 10^18)
    prize_pool: u128,        // Accumulated from entry fees (minus platform fee) or sponsorships
    status: GameStatus,
    creator: ContractAddress,
}

#[derive(Copy, Drop, Serde)]
struct PlayerStats {
    total_games: u32,
    games_won: u32,
    puzzles_solved: u64,
    rewards_earned: u128,
    xp: u128,
    level: u32,
}

#[starknet::interface]
trait IGameManagement<TContractState> {
    // ---- Game Session Management ----
    fn create_session(self: @TContractState, name: felt252, max_players: u32, entry_fee: u128) -> u128;
    fn start_session(self: @TContractState, session_id: u128);
    fn end_session(self: @TContractState, session_id: u128);
    fn pause_session(self: @TContractState, session_id: u128);
    fn resume_session(self: @TContractState, session_id: u128);
    fn cancel_session(self: @TContractState, session_id: u128);

    // ---- Player Management ----
    fn register_player(self: @TContractState, session_id: u128, player: ContractAddress);
    fn unregister_player(self: @TContractState, session_id: u128, player: ContractAddress);
    fn is_registered(self: @TContractState, session_id: u128, player: ContractAddress) -> bool;
    fn get_session_player_count(self: @TContractState, session_id: u128) -> u32;
    fn get_session_players(self: @TContractState, session_id: u128) -> Array<ContractAddress>;

    // ---- Queries ----
    fn get_session(self: @TContractState, session_id: u128) -> GameSession;
    fn get_latest_session_id(self: @TContractState) -> u128;
    fn get_player_stats(self: @TContractState, player: ContractAddress) -> PlayerStats;
    fn get_player_score(self: @TContractState, session_id: u128, player: ContractAddress) -> u128;
    fn get_completion_time(self: @TContractState, session_id: u128, player: ContractAddress) -> u64;

    // Leaderboard (per session)
    fn get_leaderboard_len(self: @TContractState, session_id: u128) -> u32;
    fn get_leaderboard_entry(self: @TContractState, session_id: u128, index: u32) -> (player: ContractAddress, score: u128);
    fn get_leaderboard(self: @TContractState, session_id: u128) -> (players: Array<ContractAddress>, scores: Array<u128>);

    // ---- Puzzle Completion Handling ----
    fn record_puzzle_completion(self: @TContractState, session_id: u128, player: ContractAddress, points: u128, completion_time: u64);

    // ---- Integrations ----
    fn set_nft_contract(self: @TContractState, addr: ContractAddress);
    fn set_puzzle_contract(self: @TContractState, addr: ContractAddress);
    fn set_verification_contract(self: @TContractState, addr: ContractAddress);

    // ---- Admin ----
    fn set_game_master(self: @TContractState, gm: ContractAddress, enabled: bool);
    fn set_platform_fee_bps(self: @TContractState, bps: u16);
    fn withdraw_platform_fees(self: @TContractState, to: ContractAddress, amount: u128);
    fn update_level_requirement(self: @TContractState, level: u32, xp_required: u128);
    fn emergency_pause(self: @TContractState);
    fn emergency_unpause(self: @TContractState);
}

// ======================
// = Events Definition  =
// ======================

#[event]
#[derive(Drop, Serde)]
enum Event {
    SessionCreated: SessionCreated,
    SessionStarted: SessionId,
    SessionEnded: SessionEnded,
    SessionPaused: SessionId,
    SessionResumed: SessionId,
    SessionCancelled: SessionId,

    PlayerRegistered: PlayerReg,
    PlayerUnregistered: PlayerReg,

    PuzzleCompleted: PuzzleCompleted,
    XpAwarded: XpAwarded,
    PlayerLevelUp: PlayerLevelUp,

    PlatformFeeUpdated: PlatformFeeUpdated,
    PlatformFeesWithdrawn: FeesWithdrawn,
    LevelRequirementUpdated: LevelRequirementUpdated,

    EmergencyPaused: Empty,
    EmergencyUnpaused: Empty,
}

#[derive(Drop, Serde)]
struct Empty {}

#[derive(Drop, Serde)]
struct SessionId { session_id: u128 }

#[derive(Drop, Serde)]
struct SessionCreated {
    session_id: u128,
    name: felt252,
    creator: ContractAddress,
}

#[derive(Drop, Serde)]
struct SessionEnded {
    session_id: u128,
    winner: ContractAddress,
    prize: u128,
}

#[derive(Drop, Serde)]
struct PlayerReg {
    session_id: u128,
    player: ContractAddress,
}

#[derive(Drop, Serde)]
struct PuzzleCompleted {
    session_id: u128,
    player: ContractAddress,
    points: u128,
    new_score: u128,
}

#[derive(Drop, Serde)]
struct XpAwarded {
    player: ContractAddress,
    xp_added: u128,
    new_xp: u128,
}

#[derive(Drop, Serde)]
struct PlayerLevelUp {
    player: ContractAddress,
    new_level: u32,
}

#[derive(Drop, Serde)]
struct PlatformFeeUpdated { bps: u16 }

#[derive(Drop, Serde)]
struct FeesWithdrawn { to: ContractAddress, amount: u128 }

#[derive(Drop, Serde)]
struct LevelRequirementUpdated { level: u32, xp_required: u128 }

// =====================
// = Storage Layout    =
// =====================

#[storage]
struct Storage {
    // Ownership & Roles
    owner: ContractAddress,
    game_masters: LegacyMap<ContractAddress, bool>,
    emergency_paused: bool,

    // Sessions & counters
    session_counter: u128,
    sessions: LegacyMap<u128, GameSession>,

    // Players per session (indexable)
    session_player_count: LegacyMap<u128, u32>,
    session_player_at: LegacyMap<(u128, u32), ContractAddress>,
    session_player_flag: LegacyMap<(u128, ContractAddress), bool>,

    // Stats & scores
    player_stats: LegacyMap<ContractAddress, PlayerStats>,
    player_score: LegacyMap<(u128, ContractAddress), u128>,
    completion_time: LegacyMap<(u128, ContractAddress), u64>,

    // Leaderboards (per session, indexable by rank)
    leaderboard_len: LegacyMap<u128, u32>,
    leaderboard_player_at: LegacyMap<(u128, u32), ContractAddress>,
    leaderboard_score_at: LegacyMap<(u128, u32), u128>,

    // Level requirements: level -> required_xp
    level_requirement: LegacyMap<u32, u128>,

    // External contracts
    nft_contract: ContractAddress,
    puzzle_contract: ContractAddress,
    verification_contract: ContractAddress,

    // Fees
    platform_fee_bps: u16,      // e.g., 250 = 2.5%
    accumulated_fees: u128,
}

// ==========================
// = Contract Implementation =
// ==========================

#[starknet::contract]
mod GameManagement {
    use super::*;

    const MAX_LEADERBOARD_SIZE: u32 = 100_u32;

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, platform_fee_bps: u16) {
        self.owner.write(owner);
        self.platform_fee_bps.write(platform_fee_bps);
        self.emergency_paused.write(false);

        _initialize_level_system(ref self);
    }

    // -------------
    //  Access Ctrl
    // -------------

    fn only_owner(self: @ContractState) {
        let caller = get_caller_address();
        assert(caller == self.owner.read(), 'ONLY_OWNER');
    }

    fn only_owner_or_gm(self: @ContractState) {
        let caller = get_caller_address();
        if (caller == self.owner.read()) { return (); }
        let is_gm = self.game_masters.read(caller);
        assert(is_gm, 'ONLY_GM_OR_OWNER');
    }

    fn not_emergency_paused(self: @ContractState) {
        let paused = self.emergency_paused.read();
        assert(!paused, 'EMERGENCY_PAUSED');
    }

    // -------------
    //  Interfaces
    // -------------

    #[external]
    impl IGameManagementImpl of IGameManagement<ContractState> {
        // ---- Game Session Management ----
        fn create_session(ref self: ContractState, name: felt252, max_players: u32, entry_fee: u128) -> u128 {
            self.not_emergency_paused();
            self.only_owner_or_gm();

            assert(max_players > 0_u32, 'MAX_PLAYERS_ZERO');

            let mut id = self.session_counter.read();
            id = id + 1_u128;
            self.session_counter.write(id);

            let creator = get_caller_address();
            let session = GameSession { id: id, name: name, start_time: 0_u64, end_time: 0_u64,
                max_players: max_players, entry_fee: entry_fee, prize_pool: 0_u128,
                status: GameStatus::Created(()), creator: creator };
            self.sessions.write(id, session);

            emit(Event::SessionCreated(SessionCreated { session_id: id, name: name, creator: creator }));
            id
        }

        fn start_session(ref self: ContractState, session_id: u128) {
            self.not_emergency_paused();
            self.only_owner_or_gm();

            let mut s = self.sessions.read(session_id);
            assert(matches!(s.status, GameStatus::Created(_)) || matches!(s.status, GameStatus::Paused(_)), 'BAD_STATUS');
            s.status = GameStatus::Active(());
            s.start_time = get_block_timestamp();
            self.sessions.write(session_id, s);
            emit(Event::SessionStarted(SessionId { session_id: session_id }));
        }

        fn end_session(ref self: ContractState, session_id: u128) {
            self.only_owner_or_gm();

            let mut s = self.sessions.read(session_id);
            assert(matches!(s.status, GameStatus::Active(_)) || matches!(s.status, GameStatus::Paused(_)), 'BAD_STATUS');

            let (winner, prize) = _determine_session_winner(@self, session_id, s.prize_pool);
            // Distribute prizes (TODO: token transfer logic) — see helper below.
            _distribute_prizes(ref self, session_id, winner, prize);

            s.status = GameStatus::Completed(());
            s.end_time = get_block_timestamp();
            self.sessions.write(session_id, s);

            // Update winner stats
            let mut wstats = self.player_stats.read(winner);
            wstats.games_won = wstats.games_won + 1_u32;
            self.player_stats.write(winner, wstats);

            emit(Event::SessionEnded(SessionEnded { session_id: session_id, winner: winner, prize: prize }));
        }

        fn pause_session(ref self: ContractState, session_id: u128) {
            self.only_owner_or_gm();
            let mut s = self.sessions.read(session_id);
            assert(matches!(s.status, GameStatus::Active(_)), 'BAD_STATUS');
            s.status = GameStatus::Paused(());
            self.sessions.write(session_id, s);
            emit(Event::SessionPaused(SessionId { session_id }));
        }

        fn resume_session(ref self: ContractState, session_id: u128) {
            self.only_owner_or_gm();
            let mut s = self.sessions.read(session_id);
            assert(matches!(s.status, GameStatus::Paused(_)), 'BAD_STATUS');
            s.status = GameStatus::Active(());
            self.sessions.write(session_id, s);
            emit(Event::SessionResumed(SessionId { session_id }));
        }

        fn cancel_session(ref self: ContractState, session_id: u128) {
            self.only_owner_or_gm();
            let mut s = self.sessions.read(session_id);
            assert(matches!(s.status, GameStatus::Created(_)) || matches!(s.status, GameStatus::Active(_)) || matches!(s.status, GameStatus::Paused(_)), 'BAD_STATUS');
            s.status = GameStatus::Cancelled(());
            self.sessions.write(session_id, s);
            // TODO: consider refunds on cancel (see _refund_entry_fees)
            _refund_entry_fees(ref self, session_id);
            emit(Event::SessionCancelled(SessionId { session_id }));
        }

        // ---- Player Management ----
        fn register_player(ref self: ContractState, session_id: u128, player: ContractAddress) {
            self.not_emergency_paused();

            let s = self.sessions.read(session_id);
            assert(matches!(s.status, GameStatus::Created(_)) || matches!(s.status, GameStatus::Active(_)), 'REG_BAD_STATUS');

            // prevent duplicate
            let already = self.session_player_flag.read((session_id, player));
            assert(!already, 'ALREADY_REGISTERED');

            // capacity check
            let mut count = self.session_player_count.read(session_id);
            assert(count < s.max_players, 'SESSION_FULL');

            // fee handling — accumulate prize pool & platform fee
            let fee = s.entry_fee;
            if fee > 0_u128 {
                let bps: u128 = self.platform_fee_bps.read().into();
                let platform_cut = fee * bps / 10_000_u128;
                let prize_add = fee - platform_cut;

                // NOTE: Real token transfer logic must deduct from player and send to contract.
                // TODO: Integrate ERC20.CollectFrom(player, fee) pattern via an approved allowance.
                // For now, we only mutate accounting fields.
                let mut prize_pool = s.prize_pool + prize_add;
                let mut s2 = s;
                s2.prize_pool = prize_pool;
                self.sessions.write(session_id, s2);

                let acc = self.accumulated_fees.read();
                self.accumulated_fees.write(acc + platform_cut);
            }

            // index the player
            let idx = count; // 0-based index
            self.session_player_at.write((session_id, idx), player);
            self.session_player_flag.write((session_id, player), true);
            count = count + 1_u32;
            self.session_player_count.write(session_id, count);

            // increment player total games
            let mut st = self.player_stats.read(player);
            st.total_games = st.total_games + 1_u32;
            self.player_stats.write(player, st);

            emit(Event::PlayerRegistered(PlayerReg { session_id: session_id, player: player }));
        }

        fn unregister_player(ref self: ContractState, session_id: u128, player: ContractAddress) {
            self.only_owner_or_gm();
            let s = self.sessions.read(session_id);
            assert(matches!(s.status, GameStatus::Created(_)), 'UNREG_BAD_STATUS');

            let is_reg = self.session_player_flag.read((session_id, player));
            assert(is_reg, 'NOT_REGISTERED');

            // We don't compact the array for simplicity. We just clear the flag.
            self.session_player_flag.write((session_id, player), false);
            emit(Event::PlayerUnregistered(PlayerReg { session_id, player }));

            // TODO: Optionally refund entry fee (see _refund_entry_fees)
        }

        fn is_registered(self: @ContractState, session_id: u128, player: ContractAddress) -> bool {
            self.session_player_flag.read((session_id, player))
        }

        fn get_session_player_count(self: @ContractState, session_id: u128) -> u32 {
            self.session_player_count.read(session_id)
        }

        fn get_session_players(self: @ContractState, session_id: u128) -> Array<ContractAddress> {
            let mut out: Array<ContractAddress> = ArrayTrait::new();
            let count = self.session_player_count.read(session_id);
            let mut i: u32 = 0_u32;
            loop {
                if i >= count { break; }
                let p = self.session_player_at.read((session_id, i));
                // Only include still-registered players
                if self.session_player_flag.read((session_id, p)) { out.append(p); }
                i = i + 1_u32;
            };
            out
        }

        // ---- Queries ----
        fn get_session(self: @ContractState, session_id: u128) -> GameSession { self.sessions.read(session_id) }
        fn get_latest_session_id(self: @ContractState) -> u128 { self.session_counter.read() }
        fn get_player_stats(self: @ContractState, player: ContractAddress) -> PlayerStats { self.player_stats.read(player) }
        fn get_player_score(self: @ContractState, session_id: u128, player: ContractAddress) -> u128 { self.player_score.read((session_id, player)) }
        fn get_completion_time(self: @ContractState, session_id: u128, player: ContractAddress) -> u64 { self.completion_time.read((session_id, player)) }

        fn get_leaderboard_len(self: @ContractState, session_id: u128) -> u32 {
            self.leaderboard_len.read(session_id)
        }
        fn get_leaderboard_entry(self: @ContractState, session_id: u128, index: u32) -> (player: ContractAddress, score: u128) {
            let p = self.leaderboard_player_at.read((session_id, index));
            let s = self.leaderboard_score_at.read((session_id, index));
            (p, s)
        }
        fn get_leaderboard(self: @ContractState, session_id: u128) -> (players: Array<ContractAddress>, scores: Array<u128>) {
            let mut ps: Array<ContractAddress> = ArrayTrait::new();
            let mut sc: Array<u128> = ArrayTrait::new();
            let len = self.leaderboard_len.read(session_id);
            let mut i: u32 = 0_u32;
            loop {
                if i >= len { break; }
                ps.append(self.leaderboard_player_at.read((session_id, i)));
                sc.append(self.leaderboard_score_at.read((session_id, i)));
                i = i + 1_u32;
            };
            (ps, sc)
        }

        // ---- Puzzle Completion Handling ----
        fn record_puzzle_completion(ref self: ContractState, session_id: u128, player: ContractAddress, points: u128, completion_time: u64) {
            self.not_emergency_paused();
            self.only_owner_or_gm(); // In production, you might restrict to verification_contract

            let s = self.sessions.read(session_id);
            assert(matches!(s.status, GameStatus::Active(_)), 'COMP_BAD_STATUS');
            assert(self.session_player_flag.read((session_id, player)), 'PLAYER_NOT_REGISTERED');

            // Update per-session score
            let mut cur = self.player_score.read((session_id, player));
            cur = cur + points;
            self.player_score.write((session_id, player), cur);
            self.completion_time.write((session_id, player), completion_time);

            emit(Event::PuzzleCompleted(PuzzleCompleted { session_id, player, points, new_score: cur }));

            // Award XP (1:1 with points for simplicity)
            _award_xp_and_maybe_level_up(ref self, player, points);

            // Update session leaderboard
            _update_session_leaderboard(ref self, session_id, player, cur);
        }

        // ---- Integrations ----
        fn set_nft_contract(ref self: ContractState, addr: ContractAddress) { self.only_owner(); self.nft_contract.write(addr); }
        fn set_puzzle_contract(ref self: ContractState, addr: ContractAddress) { self.only_owner(); self.puzzle_contract.write(addr); }
        fn set_verification_contract(ref self: ContractState, addr: ContractAddress) { self.only_owner(); self.verification_contract.write(addr); }

        // ---- Admin ----
        fn set_game_master(ref self: ContractState, gm: ContractAddress, enabled: bool) {
            self.only_owner();
            self.game_masters.write(gm, enabled);
        }

        fn set_platform_fee_bps(ref self: ContractState, bps: u16) {
            self.only_owner();
            assert(bps.into() <= 10000_u128, 'BPS_TOO_HIGH');
            self.platform_fee_bps.write(bps);
            emit(Event::PlatformFeeUpdated(PlatformFeeUpdated { bps }));
        }

        fn withdraw_platform_fees(ref self: ContractState, to: ContractAddress, amount: u128) {
            self.only_owner();
            let acc = self.accumulated_fees.read();
            assert(amount <= acc, 'INSUFFICIENT_FEES');
            self.accumulated_fees.write(acc - amount);
            // TODO: transfer ERC20 tokens to `to` for `amount`.
            // e.g., call IERC20.transfer(to, amount)
            emit(Event::PlatformFeesWithdrawn(FeesWithdrawn { to, amount }));
        }

        fn update_level_requirement(ref self: ContractState, level: u32, xp_required: u128) {
            self.only_owner();
            assert(level > 0_u32, 'LEVEL_ZERO');
            self.level_requirement.write(level, xp_required);
            emit(Event::LevelRequirementUpdated(LevelRequirementUpdated { level, xp_required }));
        }

        fn emergency_pause(ref self: ContractState) { self.only_owner(); self.emergency_paused.write(true); emit(Event::EmergencyPaused(Empty {})); }
        fn emergency_unpause(ref self: ContractState) { self.only_owner(); self.emergency_paused.write(false); emit(Event::EmergencyUnpaused(Empty {})); }
    }

    // =====================
    // = Internal Helpers  =
    // =====================

    fn _initialize_level_system(ref self: ContractState) {
        // Levels 1..10 — simple quadratic requirement for demo purposes
        // Level 1: 0 XP (already achieved when xp >= 0)
        // Level n: n^2 * 100 XP
        let mut lvl: u32 = 1_u32;
        loop {
            if lvl > 10_u32 { break; }
            let l: u128 = lvl.into();
            let req = l * l * 100_u128;
            self.level_requirement.write(lvl, req);
            lvl = lvl + 1_u32;
        };
    }

    fn _award_xp_and_maybe_level_up(ref self: ContractState, player: ContractAddress, xp_gain: u128) {
        let mut st = self.player_stats.read(player);
        let new_xp = st.xp + xp_gain;
        st.xp = new_xp;
        emit(Event::XpAwarded(XpAwarded { player, xp_added: xp_gain, new_xp }));

        // Determine new level
        let mut lvl = st.level;
        if lvl == 0_u32 { lvl = 1_u32; }
        // Attempt to increase while requirement is met
        loop {
            let next = lvl + 1_u32;
            if next > 100_u32 { break; } // hard cap for safety
            let req = self.level_requirement.read(next);
            if new_xp >= req { lvl = next; } else { break; }
        };
        if lvl != st.level { st.level = lvl; emit(Event::PlayerLevelUp(PlayerLevelUp { player, new_level: lvl })); }
        self.player_stats.write(player, st);
    }

    fn _determine_session_winner(self: @ContractState, session_id: u128, prize_pool: u128) -> (ContractAddress, u128) {
        // Winner = highest score; tiebreaker: earliest completion time among tied max scorers.
        let count = self.session_player_count.read(session_id);
        let mut i: u32 = 0_u32;
        let mut best_player = ContractAddress::from_felt(0);
        let mut best_score: u128 = 0_u128;
        let mut best_time: u64 = u64::MAX;
        loop {
            if i >= count { break; }
            let p = self.session_player_at.read((session_id, i));
            if self.session_player_flag.read((session_id, p)) {
                let sc = self.player_score.read((session_id, p));
                let ct = self.completion_time.read((session_id, p));
                if sc > best_score || (sc == best_score && ct < best_time) {
                    best_score = sc; best_time = ct; best_player = p;
                }
            }
            i = i + 1_u32;
        };
        (best_player, prize_pool)
    }

    fn _distribute_prizes(ref self: ContractState, session_id: u128, winner: ContractAddress, amount: u128) {
        if amount == 0_u128 { return (); }
        // TODO: Transfer ERC20 prize tokens from contract to winner.
        // e.g., IERC20.transfer(winner, amount)
        // Also: increment rewards_earned in player stats
        let mut st = self.player_stats.read(winner);
        st.rewards_earned = st.rewards_earned + amount;
        self.player_stats.write(winner, st);

        // Zero out prize pool after distribution
        let mut s = self.sessions.read(session_id);
        s.prize_pool = 0_u128;
        self.sessions.write(session_id, s);
    }

    fn _refund_entry_fees(ref self: ContractState, session_id: u128) {
        // TODO: Iterate registered players and refund entry fees.
        // For each player with session_player_flag == true:
        //   call IERC20.transfer(player, s.entry_fee - platform_cut?)
        // Depending on product policy, either full refund or (entry_fee - platform fee).
        // Current implementation is a placeholder (accounting-only).
    }

    fn _update_session_leaderboard(ref self: ContractState, session_id: u128, player: ContractAddress, new_score: u128) {
        // Maintain a simple sorted array by score (descending). Cap at MAX_LEADERBOARD_SIZE.
        // Approach: linear insert/find position (sufficient for <=100 entries).
        let mut len = self.leaderboard_len.read(session_id);

        // Find existing index (if any)
        let mut existing: Option<u32> = Option::None(());
        let mut i: u32 = 0_u32;
        loop {
            if i >= len { break; }
            let p = self.leaderboard_player_at.read((session_id, i));
            if p == player { existing = Option::Some(i); break; }
            i = i + 1_u32;
        };

        // Remove existing entry (compact by shifting left)
        match existing {
            Option::Some(idx) => {
                let mut j = idx;
                loop {
                    if j + 1_u32 >= len { break; }
                    let np = self.leaderboard_player_at.read((session_id, j + 1_u32));
                    let ns = self.leaderboard_score_at.read((session_id, j + 1_u32));
                    self.leaderboard_player_at.write((session_id, j), np);
                    self.leaderboard_score_at.write((session_id, j), ns);
                    j = j + 1_u32;
                };
                len = len - 1_u32;
                self.leaderboard_len.write(session_id, len);
            },
            Option::None(()) => {}
        };

        // Find insert position for new_score (descending)
        let mut pos: u32 = 0_u32;
        let mut k: u32 = 0_u32;
        loop {
            if k >= len { break; }
            let s = self.leaderboard_score_at.read((session_id, k));
            if new_score > s { break; } else { pos = pos + 1_u32; }
            k = k + 1_u32;
        };

        // If at capacity, check if should insert
        let cap = MAX_LEADERBOARD_SIZE;
        if len == cap {
            let last_score = self.leaderboard_score_at.read((session_id, len - 1_u32));
            if new_score <= last_score { return (); }
            // else we will drop the last by overwriting after shifting
        } else {
            len = len + 1_u32;
            self.leaderboard_len.write(session_id, len);
        }

        // Shift right from end to pos
        let mut j2: u32 = len;
        loop {
            if j2 == 0_u32 || j2 - 1_u32 < pos { break; }
            let from = j2 - 1_u32;
            let fp = self.leaderboard_player_at.read((session_id, from));
            let fs = self.leaderboard_score_at.read((session_id, from));
            self.leaderboard_player_at.write((session_id, from + 1_u32), fp);
            self.leaderboard_score_at.write((session_id, from + 1_u32), fs);
            j2 = from;
        };

        // Insert
        self.leaderboard_player_at.write((session_id, pos), player);
        self.leaderboard_score_at.write((session_id, pos), new_score);
    }
}
