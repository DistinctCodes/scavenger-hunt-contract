// SPDX-License-Identifier: MIT
// PlayerProgress.cairo
// Cairo 1 / StarkNet contract for managing player profiles, achievements, learning paths,
// daily progress, streaks and analytics for a gamified learning system.
//
// NOTE: This is a best-effort full implementation. Some external-call signatures are
// represented as stubs and may require minor adjustments to fit your actual environment.

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

// --------------------
// Enums & Structs
// --------------------

#[derive(Copy, Drop)]
enum AchievementCategory {
    Learning: (),
    Puzzle: (),
    Social: (),
    Milestone: (),
}

#[derive(Copy, Drop)]
enum AchievementRequirement {
    XP: (),
    PuzzlesSolved: (),
    DaysStreak: (),
    Custom: (),
}

#[derive(Copy, Drop)]
struct PlayerProfile {
    player: ContractAddress,
    display_name: felt252,
    bio: felt252,
    created_at: u64,
    last_active: u64,
    xp: u128,
    level: u32,
    total_puzzles_solved: u64,
    total_sessions: u32,
}

#[derive(Copy, Drop)]
struct Achievement {
    id: u128,
    name: felt252,
    description: felt252,
    category: AchievementCategory,
    requirement: AchievementRequirement,
    requirement_value: u128,
    active: bool,
    created_by: ContractAddress,
}

#[derive(Copy, Drop)]
struct PlayerAchievement {
    player: ContractAddress,
    achievement_id: u128,
    awarded_at: u64,
}

#[derive(Copy, Drop)]
struct LearningPath {
    id: u128,
    title: felt252,
    description: felt252,
    steps: u32,
    reward_xp: u128,
    active: bool,
}

#[derive(Copy, Drop)]
struct PlayerPathProgress {
    player: ContractAddress,
    path_id: u128,
    current_step: u32,
    started_at: u64,
    completed: bool,
    completed_at: u64,
}

#[derive(Copy, Drop)]
struct DailyProgress {
    player: ContractAddress,
    day_ts: u64, // normalized day timestamp (e.g., midnight UTC)
    completed_tasks: u32,
    goal: u32,
}

// --------------------
// Interface Definition
// --------------------

#[starknet::interface]
trait IPlayerProgress<TContractState> {
    // Profile management
    fn create_profile(self: @TContractState, player: ContractAddress, display_name: felt252, bio: felt252);
    fn update_profile(self: @TContractState, player: ContractAddress, display_name: felt252, bio: felt252);
    fn get_player_profile(self: @TContractState, player: ContractAddress) -> PlayerProfile;
    fn update_last_active(self: @TContractState, player: ContractAddress);

    // Experience & leveling
    fn add_experience(self: @TContractState, player: ContractAddress, amount: u128);
    fn calculate_level(self: @TContractState, xp: u128) -> u32;
    fn get_level_requirements(self: @TContractState, level: u32) -> u128;

    // Achievements
    fn create_achievement(self: @TContractState, name: felt252, description: felt252, category: AchievementCategory, requirement: AchievementRequirement, requirement_value: u128) -> u128;
    fn check_and_award_achievements(self: @TContractState, player: ContractAddress);
    fn get_player_achievements(self: @TContractState, player: ContractAddress) -> Array<PlayerAchievement>;
    fn deactivate_achievement(self: @TContractState, achievement_id: u128);

    // Learning paths
    fn create_learning_path(self: @TContractState, title: felt252, description: felt252, steps: u32, reward_xp: u128) -> u128;
    fn start_learning_path(self: @TContractState, player: ContractAddress, path_id: u128);
    fn update_path_progress(self: @TContractState, player: ContractAddress, path_id: u128, step_completed: u32);
    fn get_player_path_progress(self: @TContractState, player: ContractAddress, path_id: u128) -> PlayerPathProgress;

    // Daily progress & streaks
    fn record_daily_activity(self: @TContractState, player: ContractAddress, tasks_completed: u32);
    fn update_streak(self: @TContractState, player: ContractAddress) -> u32;

    // Analytics & insights
    fn get_player_statistics(self: @TContractState, player: ContractAddress) -> (u128, u32, u64); // xp, level, puzzles solved
    fn get_category_mastery(self: @TContractState, player: ContractAddress, category: AchievementCategory) -> u32;

    // Integration functions
    fn record_puzzle_completion(self: @TContractState, player: ContractAddress, points: u128);
    fn record_session_participation(self: @TContractState, player: ContractAddress);
    fn record_nft_earned(self: @TContractState, player: ContractAddress, token_id: u128);

    // Admin
    fn set_level_requirements(self: @TContractState, level: u32, xp_required: u128);
    fn emergency_pause(self: @TContractState);
    fn emergency_unpause(self: @TContractState);
}

// --------------------
// Events
// --------------------

#[event]
struct ProfileCreated { player: ContractAddress, display_name: felt252 }

#[event]
struct ExperienceGained { player: ContractAddress, amount: u128, new_xp: u128 }

#[event]
struct LevelUp { player: ContractAddress, new_level: u32 }

#[event]
struct AchievementEarned { player: ContractAddress, achievement_id: u128 }

#[event]
struct StreakUpdated { player: ContractAddress, streak_days: u32 }

#[event]
struct PathStarted { player: ContractAddress, path_id: u128 }

#[event]
struct PathCompleted { player: ContractAddress, path_id: u128 }

#[event]
struct DailyGoalReached { player: ContractAddress, day_ts: u64 }

// --------------------
// Storage
// --------------------

#[storage]
struct Storage {
    owner: ContractAddress,
    emergency_paused: bool,

    // player profiles
    profiles: LegacyMap<ContractAddress, PlayerProfile>,

    // achievements
    achievement_counter: u128,
    achievements: LegacyMap<u128, Achievement>,
    player_ach_count: LegacyMap<ContractAddress, u32>,
    player_achievement_at: LegacyMap<(ContractAddress, u32), PlayerAchievement>,
    player_has_achievement: LegacyMap<(ContractAddress, u128), bool>,

    // learning paths
    path_counter: u128,
    learning_paths: LegacyMap<u128, LearningPath>,
    path_progress_count: LegacyMap<ContractAddress, u32>,
    path_progress_at: LegacyMap<(ContractAddress, u32), PlayerPathProgress>,

    // daily progress & streaks
    daily_progress_count: LegacyMap<ContractAddress, u32>,
    daily_progress_at: LegacyMap<(ContractAddress, u32), DailyProgress>,
    current_streak: LegacyMap<ContractAddress, u32>,
    last_activity_day: LegacyMap<ContractAddress, u64>,

    // level requirements
    level_requirement: LegacyMap<u32, u128>,

    // integration references
    game_contract: ContractAddress,
    puzzle_contract: ContractAddress,
    nft_contract: ContractAddress,

    // leaderboards / analytics
    leaderboard_top_count: u32,
    leaderboard_player_at: LegacyMap<u32, ContractAddress>,
    leaderboard_score_at: LegacyMap<u32, u128>,
}

// --------------------
// Contract Implementation
// --------------------

#[starknet::contract]
mod PlayerProgress {
    use super::*;

    const DEFAULT_LEADERBOARD_SIZE: u32 = 100_u32;

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.owner.write(owner);
        self.emergency_paused.write(false);
        self.achievement_counter.write(0_u128);
        self.path_counter.write(0_u128);
        self.leaderboard_top_count.write(DEFAULT_LEADERBOARD_SIZE);

        // initialize simple level requirements (quadratic)
        let mut lvl: u32 = 1_u32;
        loop {
            if lvl > 100_u32 { break; }
            let l: u128 = lvl.into();
            let req = l * l * 100_u128;
            self.level_requirement.write(lvl, req);
            lvl = lvl + 1_u32;
        };
    }

    // ---------
    // Modifiers
    // ---------
    fn only_owner(self: @ContractState) {
        let caller = get_caller_address();
        assert(caller == self.owner.read(), 'ONLY_OWNER');
    }

    fn not_paused(self: @ContractState) {
        let paused = self.emergency_paused.read();
        assert(!paused, 'EMERGENCY_PAUSED');
    }

    // ----------------
    // Profile methods
    // ----------------
    #[external]
    fn create_profile(ref self: ContractState, player: ContractAddress, display_name: felt252, bio: felt252) {
        self.not_paused();
        let now = get_block_timestamp();
        let prof = PlayerProfile { player, display_name, bio, created_at: now, last_active: now, xp: 0_u128, level: 1_u32, total_puzzles_solved: 0_u64, total_sessions: 0_u32 };
        self.profiles.write(player, prof);
        emit(ProfileCreated { player, display_name });
    }

    #[external]
    fn update_profile(ref self: ContractState, player: ContractAddress, display_name: felt252, bio: felt252) {
        self.not_paused();
        let mut p = self.profiles.read(player);
        p.display_name = display_name;
        p.bio = bio;
        p.last_active = get_block_timestamp();
        self.profiles.write(player, p);
    }

    #[view]
    fn get_player_profile(self: @ContractState, player: ContractAddress) -> PlayerProfile { self.profiles.read(player) }

    #[external]
    fn update_last_active(ref self: ContractState, player: ContractAddress) {
        let mut p = self.profiles.read(player);
        p.last_active = get_block_timestamp();
        self.profiles.write(player, p);
    }

    // ----------------
    // Experience & Leveling
    // ----------------
    #[external]
    fn add_experience(ref self: ContractState, player: ContractAddress, amount: u128) {
        self.not_paused();
        let mut p = self.profiles.read(player);
        let new_xp = p.xp + amount;
        p.xp = new_xp;
        let new_level = self.calculate_level(new_xp);
        if new_level > p.level {
            p.level = new_level;
            emit(LevelUp { player, new_level });
        }
        self.profiles.write(player, p);
        emit(ExperienceGained { player, amount, new_xp });

        // update leaderboards (best-effort)
        _update_leaderboard(ref self, player, new_xp);
    }

    #[view]
    fn calculate_level(self: @ContractState, xp: u128) -> u32 {
        // naive scan of level_requirement (small levels only)
        let mut lvl: u32 = 1_u32;
        loop {
            if lvl > 100_u32 { break; }
            let req = self.level_requirement.read(lvl);
            if xp < req { break; }
            lvl = lvl + 1_u32;
        };
        lvl
    }

    #[view]
    fn get_level_requirements(self: @ContractState, level: u32) -> u128 { self.level_requirement.read(level) }

    // ----------------
    // Achievements
    // ----------------
    #[external]
    fn create_achievement(ref self: ContractState, name: felt252, description: felt252, category: AchievementCategory, requirement: AchievementRequirement, requirement_value: u128) -> u128 {
        self.only_owner();
        let mut id = self.achievement_counter.read();
        id = id + 1_u128;
        self.achievement_counter.write(id);
        let creator = get_caller_address();
        let a = Achievement { id, name, description, category, requirement, requirement_value, active: true, created_by: creator };
        self.achievements.write(id, a);
        id
    }

    #[external]
    fn check_and_award_achievements(ref self: ContractState, player: ContractAddress) {
        self.not_paused();
        let mut i: u128 = 1_u128;
        let max = self.achievement_counter.read();
        loop {
            if i > max { break; }
            let a = self.achievements.read(i);
            if a.active {
                let already = self.player_has_achievement.read((player, a.id));
                if !already {
                    let qualifies = _player_meets_requirement(ref self, player, a.requirement, a.requirement_value);
                    if qualifies {
                        let now = get_block_timestamp();
                        let mut cnt = self.player_ach_count.read(player);
                        let pa = PlayerAchievement { player, achievement_id: a.id, awarded_at: now };
                        self.player_achievement_at.write((player, cnt), pa);
                        self.player_has_achievement.write((player, a.id), true);
                        cnt = cnt + 1_u32;
                        self.player_ach_count.write(player, cnt);
                        emit(AchievementEarned { player, achievement_id: a.id });
                    }
                }
            }
            i = i + 1_u128;
        };
    }

    #[view]
    fn get_player_achievements(self: @ContractState, player: ContractAddress) -> Array<PlayerAchievement> {
        let mut out: Array<PlayerAchievement> = ArrayTrait::new();
        let mut i: u32 = 0_u32;
        let cnt = self.player_ach_count.read(player);
        loop {
            if i >= cnt { break; }
            out.append(self.player_achievement_at.read((player, i)));
            i = i + 1_u32;
        };
        out
    }

    #[external]
    fn deactivate_achievement(ref self: ContractState, achievement_id: u128) {
        self.only_owner();
        let mut a = self.achievements.read(achievement_id);
        a.active = false;
        self.achievements.write(achievement_id, a);
    }

    // ----------------
    // Learning Paths
    // ----------------
    #[external]
    fn create_learning_path(ref self: ContractState, title: felt252, description: felt252, steps: u32, reward_xp: u128) -> u128 {
        self.only_owner();
        let mut id = self.path_counter.read();
        id = id + 1_u128;
        self.path_counter.write(id);
        let lp = LearningPath { id, title, description, steps, reward_xp, active: true };
        self.learning_paths.write(id, lp);
        id
    }

    #[external]
    fn start_learning_path(ref self: ContractState, player: ContractAddress, path_id: u128) {
        self.not_paused();
        let lp = self.learning_paths.read(path_id);
        assert(lp.active, 'PATH_INACTIVE');
        let now = get_block_timestamp();
        let mut cnt = self.path_progress_count.read(player);
        let pp = PlayerPathProgress { player, path_id, current_step: 0_u32, started_at: now, completed: false, completed_at: 0_u64 };
        self.path_progress_at.write((player, cnt), pp);
        cnt = cnt + 1_u32;
        self.path_progress_count.write(player, cnt);
        emit(PathStarted { player, path_id });
    }

    #[external]
    fn update_path_progress(ref self: ContractState, player: ContractAddress, path_id: u128, step_completed: u32) {
        self.not_paused();
        // find progress entry
        let mut i: u32 = 0_u32;
        let mut found = Option::None(());
        let cnt = self.path_progress_count.read(player);
        loop {
            if i >= cnt { break; }
            let mut pp = self.path_progress_at.read((player, i));
            if pp.path_id == path_id { found = Option::Some(i); break; }
            i = i + 1_u32;
        };
        match found {
            Option::Some(idx) => {
                let mut pp = self.path_progress_at.read((player, idx));
                pp.current_step = pp.current_step + step_completed;
                let lp = self.learning_paths.read(path_id);
                if pp.current_step >= lp.steps {
                    pp.completed = true;
                    pp.completed_at = get_block_timestamp();
                    // award XP
                    self.add_experience(player, lp.reward_xp);
                    emit(PathCompleted { player, path_id });
                }
                self.path_progress_at.write((player, idx), pp);
            },
            Option::None(()) => { assert(false, 'PATH_NOT_STARTED'); }
        }
    }

    #[view]
    fn get_player_path_progress(self: @ContractState, player: ContractAddress, path_id: u128) -> PlayerPathProgress {
        let mut i: u32 = 0_u32;
        let cnt = self.path_progress_count.read(player);
        loop {
            if i >= cnt { break; }
            let pp = self.path_progress_at.read((player, i));
            if pp.path_id == path_id { return pp; }
            i = i + 1_u32;
        };
        // return empty default if not found
        PlayerPathProgress { player, path_id, current_step: 0_u32, started_at: 0_u64, completed: false, completed_at: 0_u64 }
    }

    // ----------------
    // Daily Progress & Streaks
    // ----------------
    #[external]
    fn record_daily_activity(ref self: ContractState, player: ContractAddress, tasks_completed: u32) {
        self.not_paused();
        // normalize day timestamp to 00:00 UTC (approx) by dividing by 86400
        let ts = get_block_timestamp();
        let day = ts / 86400_u64;
        let day_ts = day * 86400_u64;
        let mut cnt = self.daily_progress_count.read(player);
        let dp = DailyProgress { player, day_ts, completed_tasks: tasks_completed, goal: 1_u32 };
        self.daily_progress_at.write((player, cnt), dp);
        cnt = cnt + 1_u32;
        self.daily_progress_count.write(player, cnt);

        // check goal
        if tasks_completed >= 1_u32 {
            emit(DailyGoalReached { player, day_ts });
        }

        // update streak
        let streak = self.update_streak(player);
        emit(StreakUpdated { player, streak_days: streak });
    }

    #[external]
    fn update_streak(ref self: ContractState, player: ContractAddress) -> u32 {
        let ts = get_block_timestamp();
        let day = ts / 86400_u64;
        let last = self.last_activity_day.read(player);
        let mut streak = self.current_streak.read(player);
        if last == 0_u64 {
            streak = 1_u32;
        } else {
            let last_day = last / 86400_u64;
            if day == last_day { /* same day, no change */ }
            else if day == last_day + 1_u64 {
                streak = streak + 1_u32;
            } else {
                streak = 1_u32; // reset
            }
        }
        self.current_streak.write(player, streak);
        self.last_activity_day.write(player, ts);
        streak
    }

    // ----------------
    // Analytics & Insights
    // ----------------
    #[view]
    fn get_player_statistics(self: @ContractState, player: ContractAddress) -> (u128, u32, u64) {
        let p = self.profiles.read(player);
        (p.xp, p.level, p.total_puzzles_solved)
    }

    #[view]
    fn get_category_mastery(self: @ContractState, player: ContractAddress, category: AchievementCategory) -> u32 {
        // simple metric: number of achievements in that category
        let mut count: u32 = 0_u32;
        let mut i: u32 = 0_u32;
        let total = self.player_ach_count.read(player);
        loop {
            if i >= total { break; }
            let pa = self.player_achievement_at.read((player, i));
            let a = self.achievements.read(pa.achievement_id);
            if a.category == category { count = count + 1_u32; }
            i = i + 1_u32;
        };
        count
    }

    // ----------------
    // Integration functions
    // ----------------
    #[external]
    fn record_puzzle_completion(ref self: ContractState, player: ContractAddress, points: u128) {
        self.not_paused();
        // increment player's puzzles & award xp
        let mut p = self.profiles.read(player);
        p.total_puzzles_solved = p.total_puzzles_solved + 1_u64;
        p.xp = p.xp + points;
        self.profiles.write(player, p);
        emit(ExperienceGained { player, amount: points, new_xp: p.xp });

        _update_leaderboard(ref self, player, p.xp);
        self.check_and_award_achievements(player);
    }

    #[external]
    fn record_session_participation(ref self: ContractState, player: ContractAddress) {
        self.not_paused();
        let mut p = self.profiles.read(player);
        p.total_sessions = p.total_sessions + 1_u32;
        self.profiles.write(player, p);
    }

    #[external]
    fn record_nft_earned(ref self: ContractState, player: ContractAddress, token_id: u128) {
        self.not_paused();
        // placeholder: award xp when NFT earned
        self.add_experience(player, 50_u128);
    }

    // ----------------
    // Admin
    // ----------------
    #[external]
    fn set_level_requirements(ref self: ContractState, level: u32, xp_required: u128) {
        self.only_owner();
        self.level_requirement.write(level, xp_required);
    }

    #[external]
    fn emergency_pause(ref self: ContractState) { self.only_owner(); self.emergency_paused.write(true); }
    #[external]
    fn emergency_unpause(ref self: ContractState) { self.only_owner(); self.emergency_paused.write(false); }

    // ----------------
    // Internal helpers
    // ----------------
    fn _player_meets_requirement(self: @ContractState, player: ContractAddress, req: AchievementRequirement, value: u128) -> bool {
        let p = self.profiles.read(player);
        match req {
            AchievementRequirement::XP(()) => { p.xp >= value }
            AchievementRequirement::PuzzlesSolved(()) => { p.total_puzzles_solved as u128 >= value }
            AchievementRequirement::DaysStreak(()) => { self.current_streak.read(player) as u128 >= value }
            AchievementRequirement::Custom(()) => { false }
        }
    }

    fn _update_leaderboard(ref self: ContractState, player: ContractAddress, score: u128) {
        // Simple top-N leaderboard update by linear insert (size DEFAULT_LEADERBOARD_SIZE)
        let mut n = self.leaderboard_top_count.read();
        if n == 0_u32 { n = DEFAULT_LEADERBOARD_SIZE; }

        let mut i: u32 = 0_u32;
        let mut inserted = false;
        loop {
            if i >= n { break; }
            let cur = self.leaderboard_score_at.read(i);
            if score > cur {
                // shift down
                let mut j = n - 1_u32;
                while j > i {
                    let prev = j - 1_u32;
                    let paddr = self.leaderboard_player_at.read(prev);
                    let s = self.leaderboard_score_at.read(prev);
                    self.leaderboard_player_at.write(j, paddr);
                    self.leaderboard_score_at.write(j, s);
                    j = prev;
                }
                self.leaderboard_player_at.write(i, player);
                self.leaderboard_score_at.write(i, score);
                inserted = true;
                break;
            }
            i = i + 1_u32;
        };
        if !inserted {
            // not in leaderboard
        }
    }
}

