#[cfg(test)]
mod tests {
    use super::PuzzleSystem;
    use starknet::testing::{set_caller_address};
    use starknet::ContractAddress;

    #[test]
    fn test_create_and_attempt() {
        let owner = ContractAddress::from_felt(0x1);
        let player = ContractAddress::from_felt(0x10);
        let mut c = PuzzleSystem::default();
        PuzzleSystem::constructor(&mut c, owner, 0xdeadbeef_u128);

        // owner creates puzzle
        set_caller_address(owner);
        let ans: felt252 = 0xabc_u128 as felt252;
        let pid = PuzzleSystem::create_puzzle(&mut c, 0x7469746c_u128 as felt252, 0x64657363_u128 as felt252, PuzzleCategory::GeneralRiddle(()), 3_u8, PuzzleType::TextInput(()), ans, 2_u32);

        // player attempts wrong answer
        set_caller_address(player);
        let r1 = PuzzleSystem::attempt_puzzle(&mut c, pid, player, 0x111_u128 as felt252);
        assert(!r1, 'should be incorrect');

        // correct answer
        let r2 = PuzzleSystem::attempt_puzzle(&mut c, pid, player, ans);
        assert(r2, 'should be correct');
    }
}