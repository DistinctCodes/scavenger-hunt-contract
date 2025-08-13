use starknet::ContractAddress;

#[starknet::interface]
pub trait IPuzzleEventEmitter<TContractState> {
    fn emit_puzzle_complete(ref self: TContractState, user: ContractAddress, puzzle_id: u64, source: felt252);
    fn get_completed_puzzles_count(self: @TContractState, user: ContractAddress) -> u64;
    fn get_puzzle_completions(self: @TContractState, puzzle_id: u64) -> u64;
}

#[starknet::contract]
pub mod PuzzleEventEmitter {
    use starknet::ContractAddress;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::get_caller_address;

    #[storage]
    struct Storage {
        user_puzzle_count: Map<ContractAddress, u64>,
        puzzle_completion_count: Map<u64, u64>,
        owner: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        PuzzleSolved: PuzzleSolved,
    }

    #[derive(Drop, starknet::Event)]
    struct PuzzleSolved {
        #[key]
        user: ContractAddress,
        #[key]  
        puzzle_id: u64,
        source: felt252,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.owner.write(owner);
    }

    #[abi(embed_v0)]
    impl PuzzleEventEmitterImpl of super::IPuzzleEventEmitter<ContractState> {
        /// Emit an event when a user completes a puzzle
        /// @param user The address of the user who completed the puzzle
        /// @param puzzle_id The unique identifier of the completed puzzle
        /// @param source The source where the puzzle was completed (mobile/web/contract)
        fn emit_puzzle_complete(ref self: ContractState, user: ContractAddress, puzzle_id: u64, source: felt252) {
            // Update user's completed puzzle count
            let current_count = self.user_puzzle_count.read(user);
            self.user_puzzle_count.write(user, current_count + 1);
            
            // Update puzzle completion count
            let puzzle_count = self.puzzle_completion_count.read(puzzle_id);
            self.puzzle_completion_count.write(puzzle_id, puzzle_count + 1);
            
            // Emit the PuzzleSolved event
            self.emit(Event::PuzzleSolved(PuzzleSolved { 
                user, 
                puzzle_id, 
                source 
            }));
        }

        /// Get the total number of puzzles completed by a user
        /// @param user The address of the user
        /// @return The number of puzzles completed by the user
        fn get_completed_puzzles_count(self: @ContractState, user: ContractAddress) -> u64 {
            self.user_puzzle_count.read(user)
        }

        /// Get the total number of times a specific puzzle has been completed
        /// @param puzzle_id The unique identifier of the puzzle
        /// @return The number of times the puzzle has been completed
        fn get_puzzle_completions(self: @ContractState, puzzle_id: u64) -> u64 {
            self.puzzle_completion_count.read(puzzle_id)
        }
    }

    // Generate implementation for internal functions
    #[generate_trait]
    impl InternalImpl of InternalTrait {
        /// Internal function to check if caller is the owner
        fn assert_only_owner(self: @ContractState) {
            let caller = get_caller_address();
            let owner = self.owner.read();
            assert(caller == owner, 'Only owner allowed');
        }
    }
} 