#[starknet::contract]
mod RewardNFT {
    use starknet::{ContractAddress, get_caller_address};
    use core::traits::Into;
    use core::option::OptionTrait;
    use core::array::ArrayTrait;
    use core::integer::BoundedInt;
    use openzeppelin::token::erc721::ERC721;
    use openzeppelin::introspection::src5::SRC5;
    use openzeppelin::access::ownable::Ownable;
    use nft_scavenger_hunt::social_metadata::{ISocialMetadataDispatcher, ISocialMetadataDispatcherTrait};

    // Storage for the contract
    #[storage]
    struct Storage {
        // ERC721 storage
        #[substorage(v0)]
        erc721: ERC721::Storage,
        #[substorage(v0)]
        ownable: Ownable::Storage,
        // Challenge manager contract address
        challenge_manager: ContractAddress,
        // Social metadata contract address
        social_metadata: ContractAddress,
        // Token counter
        token_counter: u256,
        // Mapping from token ID to hunt ID
        token_hunt_ids: LegacyMap<u256, u64>,
        // Mapping from token ID to challenge ID
        token_challenge_ids: LegacyMap<u256, u64>,
        // Mapping to track which challenges have been rewarded
        // (hunt_id, challenge_id, user) => bool
        challenge_rewarded: LegacyMap<(u64, u64, ContractAddress), bool>,
        // Base URI for token metadata
        base_uri: felt252,
    }

    // Events
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        NFTMinted: NFTMinted,
        SocialMetadataSet: SocialMetadataSet,
        // Include ERC721 events
        #[flat]
        ERC721Event: ERC721::Event,
        #[flat]
        OwnableEvent: Ownable::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct NFTMinted {
        user: ContractAddress,
        token_id: u256,
        hunt_id: u64,
        challenge_id: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct SocialMetadataSet {
        social_metadata_address: ContractAddress,
    }

    // Constructor
    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: felt252,
        symbol: felt252,
        base_uri: felt252,
        owner: ContractAddress
    ) {
        // Initialize ERC721
        self.erc721.initializer(name, symbol);
        
        // Initialize Ownable
        self.ownable.initializer(owner);
        
        // Set base URI
        self.base_uri.write(base_uri);
        
        // Initialize token counter
        self.token_counter.write(0);
    }

    // Contract functions
    #[external(v0)]
    impl RewardNFTImpl of super::IRewardNFT<ContractState> {
        // Set the challenge manager contract address
        fn set_challenge_manager(ref self: ContractState, challenge_manager: ContractAddress) {
            // Only owner can set the challenge manager
            self.ownable.assert_only_owner();
            self.challenge_manager.write(challenge_manager);
        }
        
        // Set the social metadata contract address
        fn set_social_metadata(ref self: ContractState, social_metadata_address: ContractAddress) {
            // Only owner can set the social metadata
            self.ownable.assert_only_owner();
            self.social_metadata.write(social_metadata_address);
            
            // Emit event
            self.emit(Event::SocialMetadataSet(
                SocialMetadataSet {
                    social_metadata_address: social_metadata_address,
                }
            ));
        }
        
        // Mint a new NFT as a reward for completing a challenge
        fn mint_reward(
            ref self: ContractState,
            recipient: ContractAddress,
            hunt_id: u64,
            challenge_id: u64
        ) -> u256 {
            // Only the challenge manager contract can mint rewards
            let caller = get_caller_address();
            let challenge_manager = self.challenge_manager.read();
            assert(caller == challenge_manager, 'Only challenge manager can mint');
            
            // Check if this challenge has already been rewarded to this user
            let already_rewarded = self.challenge_rewarded.read((hunt_id, challenge_id, recipient));
            assert(!already_rewarded, 'Challenge already rewarded');
            
            // Get and increment token counter
            let token_id = self.token_counter.read();
            self.token_counter.write(token_id + 1);
            
            // Store hunt and challenge IDs for the token
            self.token_hunt_ids.write(token_id, hunt_id);
            self.token_challenge_ids.write(token_id, challenge_id);
            
            // Mark this challenge as rewarded for this user
            self.challenge_rewarded.write((hunt_id, challenge_id, recipient), true);
            
            // Mint the NFT
            self.erc721._mint(recipient, token_id);
            
            // Add achievement to social metadata if set
            let social_metadata_address = self.social_metadata.read();
            if social_metadata_address != starknet::contract_address_const::&lt;0>() {
                let social_metadata = ISocialMetadataDispatcher { contract_address: social_metadata_address };
                
                // Add achievement
                social_metadata.add_user_achievement(
                    recipient,
                    hunt_id,
                    challenge_id,
                    'Earned a reward NFT for completing a challenge!'
                );
            }
            
            // Emit event
            self.emit(Event::NFTMinted(
                NFTMinted {
                    user: recipient,
                    token_id: token_id,
                    hunt_id: hunt_id,
                    challenge_id: challenge_id,
                }
            ));
            
            token_id
        }
        
        // Check if a challenge has already been rewarded to a user
        fn is_challenge_rewarded(
            self: @ContractState,
            hunt_id: u64,
            challenge_id: u64,
            user: ContractAddress
        ) -> bool {
            self.challenge_rewarded.read((hunt_id, challenge_id, user))
        }
        
        // Get token details
        fn get_token_details(self: @ContractState, token_id: u256) -> (u64, u64) {
            // Ensure token exists
            assert(self.erc721._exists(token_id), 'Token does not exist');
            
            // Return hunt ID and challenge ID
            (self.token_hunt_ids.read(token_id), self.token_challenge_ids.read(token_id))
        }
        
        // Generate social share content for a token
        fn generate_token_share(self: @ContractState, token_id: u256) -> SocialShareContent {
            // Ensure token exists
            assert(self.erc721._exists(token_id), 'Token does not exist');
            
            // Get token details
            let hunt_id = self.token_hunt_ids.read(token_id);
            let challenge_id = self.token_challenge_ids.read(token_id);
            
            // Get token owner
            let owner = self.erc721.owner_of(token_id);
            
            // Get social metadata
            let social_metadata_address = self.social_metadata.read();
            assert(social_metadata_address != starknet::contract_address_const::&lt;0>(), 'Social metadata not set');
            
            let social_metadata = ISocialMetadataDispatcher { contract_address: social_metadata_address };
            
            // Generate share content
            let share_content = social_metadata.generate_challenge_completion_share(
                owner,
                hunt_id,
                challenge_id
            );
            
            // Return share content
            SocialShareContent {
                title: share_content.title,
                description: share_content.description,
                image_url: share_content.image_url,
                share_url: share_content.share_url,
            }
        }
        
        // Get base URI
        fn base_uri(self: @ContractState) -> felt252 {
            self.base_uri.read()
        }
        
        // Set base URI (only owner)
        fn set_base_uri(ref self: ContractState, base_uri: felt252) {
            // Only owner can set the base URI
            self.ownable.assert_only_owner();
            self.base_uri.write(base_uri);
        }
    }
    
    // Social share content struct
    #[derive(Drop, Serde)]
    struct SocialShareContent {
        title: felt252,
        description: felt252,
        image_url: felt252,
        share_url: felt252,
    }
    
    // Implement ERC721 functionality
    #[external(v0)]
    impl ERC721Impl of ERC721::IERC721<ContractState> {
        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self.erc721.balance_of(account)
        }
        
        fn owner_of(self: @ContractState, token_id: u256) -> ContractAddress {
            self.erc721.owner_of(token_id)
        }
        
        fn get_approved(self: @ContractState, token_id: u256) -> ContractAddress {
            self.erc721.get_approved(token_id)
        }
        
        fn is_approved_for_all(
            self: @ContractState, owner: ContractAddress, operator: ContractAddress
        ) -> bool {
            self.erc721.is_approved_for_all(owner, operator)
        }
        
        fn approve(ref self: ContractState, to: ContractAddress, token_id: u256) {
            self.erc721.approve(to, token_id)
        }
        
        fn set_approval_for_all(
            ref self: ContractState, operator: ContractAddress, approved: bool
        ) {
            self.erc721.set_approval_for_all(operator, approved)
        }
        
        fn transfer_from(
            ref self: ContractState, from: ContractAddress, to: ContractAddress, token_id: u256
        ) {
            self.erc721.transfer_from(from, to, token_id)
        }
        
        fn safe_transfer_from(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            token_id: u256,
            data: Span<felt252>
        ) {
            self.erc721.safe_transfer_from(from, to, token_id, data)
        }
    }
    
    // Implement ERC721 metadata functionality
    #[external(v0)]
    impl ERC721MetadataImpl of ERC721::IERC721Metadata<ContractState> {
        fn name(self: @ContractState) -> felt252 {
            self.erc721.name()
        }
        
        fn symbol(self: @ContractState) -> felt252 {
            self.erc721.symbol()
        }
        
        fn token_uri(self: @ContractState, token_id: u256) -> felt252 {
            // Ensure token exists
            assert(self.erc721._exists(token_id), 'Token does not exist');
            
            // Get token details
            let hunt_id = self.token_hunt_ids.read(token_id);
            let challenge_id = self.token_challenge_ids.read(token_id);
            
            // For simplicity, we'll just return the base URI
            // In a production environment, you might want to concatenate the token ID
            // or generate a dynamic URI based on the hunt and challenge IDs
            self.base_uri.read()
        }
    }
    
    // Implement SRC5 functionality
    #[external(v0)]
    impl SRC5Impl of SRC5::ISRC5<ContractState> {
        fn supports_interface(self: @ContractState, interface_id: felt252) -> bool {
            self.erc721.supports_interface(interface_id)
        }
    }
    
    // Implement Ownable functionality
    #[external(v0)]
    impl OwnableImpl of Ownable::IOwnable<ContractState> {
        fn owner(self: @ContractState) -> ContractAddress {
            self.ownable.owner()
        }
        
        fn transfer_ownership(ref self: ContractState, new_owner: ContractAddress) {
            self.ownable.transfer_ownership(new_owner)
        }
        
        fn renounce_ownership(ref self: ContractState) {
            self.ownable.renounce_ownership()
        }
    }
}

// Interface for the RewardNFT contract
#[starknet::interface]
trait IRewardNFT<TContractState> {
    fn set_challenge_manager(ref self: TContractState, challenge_manager: ContractAddress);
    fn set_social_metadata(ref self: TContractState, social_metadata_address: ContractAddress);
    fn mint_reward(
        ref self: TContractState,
        recipient: ContractAddress,
        hunt_id: u64,
        challenge_id: u64
    ) -> u256;
    fn is_challenge_rewarded(
        self: @TContractState,
        hunt_id: u64,
        challenge_id: u64,
        user: ContractAddress
    ) -> bool;
    fn get_token_details(self: @TContractState, token_id: u256) -> (u64, u64);
    fn generate_token_share(self: @TContractState, token_id: u256) -> RewardNFT::SocialShareContent;
    fn base_uri(self: @TContractState) -> felt252;
    fn set_base_uri(ref self: TContractState, base_uri: felt252);
}
