#[cfg(test)]
mod test {
    use super::game_management::GameManagement;
    use starknet::testing::{set_caller_address, set_contract_address};
    use starknet::ContractAddress;

    #[test]
    fn test_full_game_flow() {
        // ----------------------------
        // 1. Deploy & Setup
        // ----------------------------
        let mut contract = GameManagement::default();
        let creator: ContractAddress = ContractAddress::from_felt(0x111);
        let player1: ContractAddress = ContractAddress::from_felt(0x222);
        let player2: ContractAddress = ContractAddress::from_felt(0x333);

        set_caller_address(creator);

        // ----------------------------
        // 2. Create a Session
        // ----------------------------
        let session_id = contract.create_session(
            "Puzzle Session #1",   // session name
            1000,                  // start_time
            2000,                  // end_time
            2,                     // max_players
            5                      // entry_fee
        );

        let session = contract.get_session(session_id);
        assert(session.id == session_id, 'Invalid session id');
        assert(session.creator == creator, 'Creator mismatch');
        assert(session.max_players == 2, 'Wrong max players');

        // ----------------------------
        // 3. Register Players
        // ----------------------------
        set_caller_address(player1);
        contract.register_player(session_id);

        set_caller_address(player2);
        contract.register_player(session_id);

        let players = contract.get_registered_players(session_id);
        assert(players.len() == 2, 'Expected 2 players');

        // ----------------------------
        // 4. Complete Puzzle
        // ----------------------------
        set_caller_address(player1);
        contract.complete_puzzle(session_id, 1234); // puzzle_id = 1234

        let progress = contract.get_player_progress(session_id, player1);
        assert(progress.completed_puzzles.len() == 1, 'Puzzle not recorded');
        assert(progress.xp == 10, 'XP not awarded');

        // ----------------------------
        // 5. End Session
        // ----------------------------
        set_caller_address(creator);
        contract.end_session(session_id);

        let ended = contract.get_session(session_id);
        assert(ended.active == false, 'Session not ended');
    }

    // ----------------------------
    // Negative Test Cases
    // ----------------------------

    #[test]
    #[should_panic(expected: 'Max players reached')]
    fn test_register_exceeds_limit() {
        let mut contract = GameManagement::default();
        let creator: ContractAddress = ContractAddress::from_felt(0x111);
        let player1: ContractAddress = ContractAddress::from_felt(0x222);
        let player2: ContractAddress = ContractAddress::from_felt(0x333);
        let player3: ContractAddress = ContractAddress::from_felt(0x444);

        set_caller_address(creator);
        let session_id = contract.create_session("Small Session", 1000, 2000, 2, 5);

        set_caller_address(player1);
        contract.register_player(session_id);

        set_caller_address(player2);
        contract.register_player(session_id);

        // should fail
        set_caller_address(player3);
        contract.register_player(session_id);
    }

    #[test]
    #[should_panic(expected: 'Player not registered')]
    fn test_complete_without_register() {
        let mut contract = GameManagement::default();
        let creator: ContractAddress = ContractAddress::from_felt(0x111);
        let player: ContractAddress = ContractAddress::from_felt(0x222);

        set_caller_address(creator);
        let session_id = contract.create_session("Test Session", 1000, 2000, 2, 5);

        // not registered yet
        set_caller_address(player);
        contract.complete_puzzle(session_id, 55);
    }
}
