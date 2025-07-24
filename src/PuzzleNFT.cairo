use starknet::ContractAddress;

#[starknet::interface]
pub trait IPuzzleNFT<TContractState> {
    fn mint(ref self: TContractState, to: ContractAddress) -> u256;
    fn get_backend_address(self: @TContractState) -> ContractAddress;
}

#[starknet::contract]
mod PuzzleNFT {
    use openzeppelin::token::erc721::ERC721Component;
    use openzeppelin::introspection::src5::SRC5Component;
    use starknet::{ContractAddress, get_caller_address};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use super::IPuzzleNFT;

    component!(path: ERC721Component, storage: erc721, event: ERC721Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl ERC721MixinImpl = ERC721Component::ERC721MixinImpl<ContractState>;
    impl ERC721InternalImpl = ERC721Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc721: ERC721Component::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        backend_address: ContractAddress,
        next_token_id: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC721Event: ERC721Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        PuzzleCompleted: PuzzleCompleted,
    }

    #[derive(Drop, starknet::Event)]
    pub struct PuzzleCompleted {
        pub player: ContractAddress,
        pub token_id: u256,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: ByteArray,
        symbol: ByteArray,
        base_uri: ByteArray,
        backend_address: ContractAddress,
    ) {
        // Initialize ERC721 - this handles the base_uri internally
        self.erc721.initializer(name, symbol, base_uri);

        self.backend_address.write(backend_address);
        self.next_token_id.write(1);
    }

    #[abi(embed_v0)]
    impl PuzzleNFTImpl of IPuzzleNFT<ContractState> {
        fn mint(ref self: ContractState, to: ContractAddress) -> u256 {
            let caller = get_caller_address();
            assert(caller == self.backend_address.read(), 'Only backend can mint');

            let token_id = self.next_token_id.read();

            self.erc721._mint(to, token_id);

            self.next_token_id.write(token_id + 1);

            self.emit(PuzzleCompleted { player: to, token_id });

            token_id
        }

        fn get_backend_address(self: @ContractState) -> ContractAddress {
            self.backend_address.read()
        }
    }
}
