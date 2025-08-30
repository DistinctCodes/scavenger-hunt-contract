#[cfg(test)]
mod tests {
    use super::PlayerProgress;
    use starknet::testing::{set_caller_address};
    use starknet::ContractAddress;
    use core::array::ArrayTrait;

    #[test]
    fn test_profile_create_and_xp_levelup() {
        let owner = ContractAddress::from_felt(0x1);
        let player = ContractAddress::from_felt(0x100);
        let mut c = PlayerProgress::default();
        PlayerProgress::constructor(&mut c, owner);

        // create profile
        PlayerProgress::create_profile(&mut c, player, 0x6c6f636b_u128 as felt252, 0x62696f_u128 as felt252);
        let p = PlayerProgress::get_player_profile(&mut c, player);
        assert(p.player == player, 'profile not created');

        // add xp
        PlayerProgress::add_experience(&mut c, player, 1000_u128);
        let (xp, level, _puzzles) = PlayerProgress::get_player_statistics(&mut c, player);
        assert(xp >= 1000_u128, 'xp not added');
        assert(level >= 1_u32, 'level not computed');
    }

    #[test]
    fn test_achievements_awarded() {
        let owner = ContractAddress::from_felt(0x1);
        let player = ContractAddress::from_felt(0x200);
        let mut c = PlayerProgress::default();
        PlayerProgress::constructor(&mut c, owner);
        PlayerProgress::create_profile(&mut c, player, 0x6c6c6f_u128 as felt252, 0x62696f_u128 as felt252);

        // create achievement requiring 500 xp
        set_caller_address(owner);
        let ach_id = PlayerProgress::create_achievement(&mut c, 0x616368_u128 as felt252, 0x64657363_u128 as felt252, AchievementCategory::Learning(()), AchievementRequirement::XP(()), 500_u128);

        // award xp and run check
        PlayerProgress::add_experience(&mut c, player, 600_u128);
        PlayerProgress::check_and_award_achievements(&mut c, player);
        let achs = PlayerProgress::get_player_achievements(&mut c, player);
        assert(achs.len() >= 1_u32, 'achievement not awarded');
    }

    #[test]
    fn test_daily_streaks() {
        let owner = ContractAddress::from_felt(0x1);
        let player = ContractAddress::from_felt(0x300);
        let mut c = PlayerProgress::default();
        PlayerProgress::constructor(&mut c, owner);
        PlayerProgress::create_profile(&mut c, player, 0x6c6c6f_u128 as felt252, 0x62696f_u128 as felt252);

        // record activities multiple times to simulate streak
        PlayerProgress::record_daily_activity(&mut c, player, 1_u32);
        let s1 = PlayerProgress::update_streak(&mut c, player);
        assert(s1 >= 1_u32, 'streak not updated');
    }
}