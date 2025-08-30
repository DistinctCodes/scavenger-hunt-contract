#[cfg(test)]
mod test_system_integration {
    use starknet::ContractAddress;
    use snforge_std::{declare, deploy, start_prank, stop_prank};
    use array::ArrayTrait;
    use option::OptionTrait;
    use traits::Into;

    // Import interface so we can call contract functions
    use src::interfaces::ISystemIntegration;
    use src::SystemIntegration;

    #[test]
    fn test_constructor_and_owner() {
        let class_hash = declare("SystemIntegration");
        let owner: ContractAddress = 0x123.into();

        let contract_address = deploy(class_hash, (owner,));

        // Call get_contract_health_status (empty initially)
        let health = ISystemIntegration::get_contract_health_status(contract_address);
        assert(health.len() == 0, 'expected no health data at start');

        // Owner should be set correctly
        // NOTE: If you expose `get_owner()` in SystemIntegration, you can assert it
        // assert(ISystemIntegration::get_owner(contract_address) == owner, 'owner mismatch');
    }

    #[test]
    #[should_panic]
    fn test_batch_mint_rewards_length_mismatch() {
        let class_hash = declare("SystemIntegration");
        let owner: ContractAddress = 0x123.into();

        let contract_address = deploy(class_hash, (owner,));

        let players: Array<ContractAddress> = ArrayTrait::new();
        let puzzle_ids: Array<u256> = ArrayTrait::new();
        let rarities: Array<u8> = ArrayTrait::new();

        // Push one player only
        players.append(0x999.into());

        // Leave puzzle_ids and rarities empty => should panic
        ISystemIntegration::batch_mint_rewards(contract_address, players, puzzle_ids, rarities);
    }

    #[test]
    fn test_sync_player_data_event() {
        let class_hash = declare("SystemIntegration");
        let owner: ContractAddress = 0x123.into();
        let contract_address = deploy(class_hash, (owner,));

        let player: ContractAddress = 0x888.into();

        // Start as owner (authorized caller simulation)
        start_prank(owner);
        ISystemIntegration::sync_player_data(contract_address, player);
        stop_prank();

        // Ideally check logs for `PlayerDataSynced` event
        // (use snforge_std event inspection utilities here)
    }
}
