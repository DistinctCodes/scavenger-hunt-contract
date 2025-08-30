// SPDX-License-Identifier: MIT
// PuzzleSystem.cairo
// Cairo 1 / StarkNet contract for Puzzle management, player attempts, hints, and session integration

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
// Enums & Structs
// =====================

#[derive(Copy, Drop)]
enum PuzzleCategory {
    BlockchainBasics: (),
    StarkNetSpecific: (),
    Cryptography: (),
    SmartContracts: (),
    DeFi: (),
    GeneralRiddle: (),
    LogicPuzzle: (),
    MathProblem: (),
}

#[derive(Copy, Drop)]
enum PuzzleType {
    MultipleChoice: (),
    TextInput: (),
    NumericInput: (),
    TrueFalse: (),
    CodeCompletion: (),
    HashChallenge: (),
}

#[derive(Copy, Drop)]
struct Puzzle {
    id: u128,
    title: felt252,
    description: felt252,
    category: PuzzleCategory,
    difficulty: u8, // 1..10
    puzzle_type: PuzzleType,
    answer_hash: felt252, // hashed canonical answer
    hints: u32,
    active: bool,
    creator: ContractAddress,
    session_id: u128, // 0 if not assigned
}

#[derive(Copy, Drop)]
struct PuzzleAttempt {
    attempt_id: u128,
    puzzle_id: u128,
    player: ContractAddress,
    submitted_at: u64,
    solved: bool,
    hints_used: u8,
}

// =====================
// Interface Definition
// =====================

#[starknet::interface]
trait IPuzzleSystem<TContractState> {
    fn create_puzzle(self: @TContractState, title: felt252, description: felt252, category: PuzzleCategory, difficulty: u8, puzzle_type: PuzzleType, answer_hash: felt252, hints: u32) -> u128;
    fn update_puzzle(self: @TContractState, puzzle_id: u128, title: felt252, description: felt252, difficulty: u8, active: bool);
    fn activate_puzzle(self: @TContractState, puzzle_id: u128);
    fn deactivate_puzzle(self: @TContractState, puzzle_id: u128);

    fn attempt_puzzle(self: @TContractState, puzzle_id: u128, player: ContractAddress, submission_hash: felt252) -> bool;
    fn use_hint(self: @TContractState, puzzle_id: u128, player: ContractAddress) -> ();
    fn get_puzzle(self: @TContractState, puzzle_id: u128) -> Puzzle;
    fn get_puzzles_by_category(self: @TContractState, category: PuzzleCategory) -> Array<Puzzle>;

    fn assign_puzzle_to_session(self: @TContractState, puzzle_id: u128, session_id: u128);
    fn get_random_puzzles(self: @TContractState, session_id: u128, count: u32) -> Array<Puzzle>;

    fn set_game_contract(self: @TContractState, addr: ContractAddress);
    fn emergency_pause(self: @TContractState);
    fn emergency_unpause(self: @TContractState);
}

// =====================
// Events
// =====================

#[event]
struct PuzzleCreated { puzzle_id: u128, creator: ContractAddress }

#[event]
struct PuzzleUpdated { puzzle_id: u128 }

#[event]
struct PuzzleAttempted { attempt_id: u128, puzzle_id: u128, player: ContractAddress, solved: bool }

#[event]
struct PuzzleSolved { puzzle_id: u128, player: ContractAddress }

#[event]
struct HintUsed { puzzle_id: u128, player: ContractAddress, remaining_hints: u32 }

#[event]
struct PuzzleAssignedToSession { puzzle_id: u128, session_id: u128 }

// =====================
// Storage
// =====================

#[storage]
struct Storage {
    owner: ContractAddress,
    emergency_paused: bool,

    puzzle_counter: u128,
    attempt_counter: u128,
    puzzles: LegacyMap<u128, Puzzle>,

    // category index: category -> list of puzzle ids (length + id_at)
    category_len: LegacyMap<u8, u32>,
    category_at: LegacyMap<(u8, u32), u128>,

    // player attempts mapping (player -> count + attempt_at index)
    player_attempt_count: LegacyMap<ContractAddress, u32>,
    player_attempt_at: LegacyMap<(ContractAddress, u32), PuzzleAttempt>,

    // session assignment: session_id -> list of puzzle ids
    session_len: LegacyMap<u128, u32>,
    session_puzzle_at: LegacyMap<(u128, u32), u128>,

    // random seed
    random_seed: u128,

    // linked contracts
    game_contract: ContractAddress,
}

// =====================
// Contract Implementation
// =====================

#[starknet::contract]
mod PuzzleSystem {
    use super::*;

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, seed: u128) {
        self.owner.write(owner);
        self.emergency_paused.write(false);
        self.puzzle_counter.write(0_u128);
        self.attempt_counter.write(0_u128);
        self.random_seed.write(seed);
    }

    fn only_owner(self: @ContractState) {
        let caller = get_caller_address();
        assert(caller == self.owner.read(), 'ONLY_OWNER');
    }

    fn not_paused(self: @ContractState) {
        let paused = self.emergency_paused.read();
        assert(!paused, 'EMERGENCY_PAUSED');
    }

    // ---- Admin functions ----
    #[external]
    fn set_game_contract(ref self: ContractState, addr: ContractAddress) { self.only_owner(); self.game_contract.write(addr); }

    #[external]
    fn emergency_pause(ref self: ContractState) { self.only_owner(); self.emergency_paused.write(true); }
    #[external]
    fn emergency_unpause(ref self: ContractState) { self.only_owner(); self.emergency_paused.write(false); }

    // ---- Puzzle CRUD ----
    #[external]
    fn create_puzzle(ref self: ContractState, title: felt252, description: felt252, category: PuzzleCategory, difficulty: u8, puzzle_type: PuzzleType, answer_hash: felt252, hints: u32) -> u128 {
        self.not_paused();
        self.only_owner();
        assert(difficulty >= 1_u8 && difficulty <= 10_u8, 'DIFFICULTY_RANGE');
        assert(hints <= 10_u32, 'HINTS_LIMIT');

        let mut id = self.puzzle_counter.read();
        id = id + 1_u128;
        self.puzzle_counter.write(id);

        let creator = get_caller_address();
        let p = Puzzle { id, title, description, category, difficulty, puzzle_type, answer_hash, hints, active: true, creator, session_id: 0_u128 };
        self.puzzles.write(id, p);

        // index by category (cast enum as u8 for storage key)
        let cat_key: u8 = category as u8;
        let mut len = self.category_len.read(cat_key);
        self.category_at.write((cat_key, len), id);
        len = len + 1_u32;
        self.category_len.write(cat_key, len);

        emit(PuzzleCreated { puzzle_id: id, creator });
        id
    }

    #[external]
    fn update_puzzle(ref self: ContractState, puzzle_id: u128, title: felt252, description: felt252, difficulty: u8, active: bool) {
        self.not_paused();
        self.only_owner();
        let mut p = self.puzzles.read(puzzle_id);
        assert(p.id != 0_u128, 'PUZZLE_NOT_FOUND');
        assert(difficulty >= 1_u8 && difficulty <= 10_u8, 'DIFFICULTY_RANGE');
        p.title = title;
        p.description = description;
        p.difficulty = difficulty;
        p.active = active;
        self.puzzles.write(puzzle_id, p);
        emit(PuzzleUpdated { puzzle_id });
    }

    #[external]
    fn activate_puzzle(ref self: ContractState, puzzle_id: u128) { self.only_owner(); let mut p = self.puzzles.read(puzzle_id); p.active = true; self.puzzles.write(puzzle_id, p); }
    #[external]
    fn deactivate_puzzle(ref self: ContractState, puzzle_id: u128) { self.only_owner(); let mut p = self.puzzles.read(puzzle_id); p.active = false; self.puzzles.write(puzzle_id, p); }

    // ---- Attempts & Hints ----
    #[external]
    fn attempt_puzzle(ref self: ContractState, puzzle_id: u128, player: ContractAddress, submission_hash: felt252) -> bool {
        self.not_paused();
        let mut p = self.puzzles.read(puzzle_id);
        assert(p.id != 0_u128 && p.active, 'INVALID_PUZZLE');

        // create attempt record
        let mut aid = self.attempt_counter.read();
        aid = aid + 1_u128;
        self.attempt_counter.write(aid);

        let ts = get_block_timestamp();
        let mut solved = false;
        // check answer hash equality (simple equality; in practice use robust hashing)
        if submission_hash == p.answer_hash {
            solved = true;
            emit(PuzzleSolved { puzzle_id, player });
        }

        let at = PuzzleAttempt { attempt_id: aid, puzzle_id, player, submitted_at: ts, solved, hints_used: 0_u8 };
        // store per-player attempt
        let mut cnt = self.player_attempt_count.read(player);
        self.player_attempt_at.write((player, cnt), at);
        cnt = cnt + 1_u32;
        self.player_attempt_count.write(player, cnt);

        emit(PuzzleAttempted { attempt_id: aid, puzzle_id, player, solved });
        solved
    }

    #[external]
    fn use_hint(ref self: ContractState, puzzle_id: u128, player: ContractAddress) {
        self.not_paused();
        let mut p = self.puzzles.read(puzzle_id);
        assert(p.id != 0_u128 && p.active, 'INVALID_PUZZLE');
        assert(p.hints > 0_u32, 'NO_HINTS_AVAILABLE');
        // decrement hints
        p.hints = p.hints - 1_u32;
        self.puzzles.write(puzzle_id, p);
        emit(HintUsed { puzzle_id, player, remaining_hints: p.hints });
    }

    // ---- Retrieval & Filtering ----
    #[view]
    fn get_puzzle(self: @ContractState, puzzle_id: u128) -> Puzzle { self.puzzles.read(puzzle_id) }

    #[view]
    fn get_puzzles_by_category(self: @ContractState, category: PuzzleCategory) -> Array<Puzzle> {
        let mut out: Array<Puzzle> = ArrayTrait::new();
        let cat_key: u8 = category as u8;
        let len = self.category_len.read(cat_key);
        let mut i: u32 = 0_u32;
        loop {
            if i >= len { break; }
            let id = self.category_at.read((cat_key, i));
            out.append(self.puzzles.read(id));
            i = i + 1_u32;
        };
        out
    }

    // ---- Session Assignment & Random selection ----
    #[external]
    fn assign_puzzle_to_session(ref self: ContractState, puzzle_id: u128, session_id: u128) {
        self.not_paused();
        self.only_owner();
        let mut p = self.puzzles.read(puzzle_id);
        assert(p.id != 0_u128, 'PUZZLE_NOT_FOUND');
        p.session_id = session_id;
        self.puzzles.write(puzzle_id, p);

        // index in session list
        let mut len = self.session_len.read(session_id);
        self.session_puzzle_at.write((session_id, len), puzzle_id);
        len = len + 1_u32;
        self.session_len.write(session_id, len);

        emit(PuzzleAssignedToSession { puzzle_id, session_id });
    }

    #[view]
    fn get_random_puzzles(self: @ContractState, session_id: u128, count: u32) -> Array<Puzzle> {
        let mut out: Array<Puzzle> = ArrayTrait::new();
        let len = self.session_len.read(session_id);
        if len == 0_u32 { return out; }
        // deterministic pseudorandom using stored seed + timestamp
        let seed = self.random_seed.read();
        let ts = get_block_timestamp();
        let mut i: u32 = 0_u32;
        let mut idx_seed = (seed as u64 ^ ts) as u128;
        loop {
            if i >= count { break; }
            let idx = (idx_seed % (len as u128)) as u32;
            let pid = self.session_puzzle_at.read((session_id, idx));
            out.append(self.puzzles.read(pid));
            // mix seed
            idx_seed = ((idx_seed * 1103515245_u128) + 12345_u128) % 0xffff_ffff_ffff_u128;
            i = i + 1_u32;
        };
        out
    }

    // ----------------
    // Helpers
    // ----------------
    fn _hash_answer(answer: felt252) -> felt252 {
        // placeholder hash - in production, use a robust hashing syscall or preimage design
        answer
    }

    fn _create_default_puzzles(ref self: ContractState) {
        // Optional: populate some default puzzles. Owner-only, but not automatic here.
    }
}


