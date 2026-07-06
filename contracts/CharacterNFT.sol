// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title CharacterNFT
 * @author Your Name
 * @notice An NFT contract for minting characters with unique, randomly generated stats.
 * This contract is part of an NFT staking platform. It handles the creation
 * of NFTs, management of their stats, and fee collection.
 */
contract CharacterNFT is ERC721, Ownable {
    using Counters for Counters.Counter;

    // --- Events ---
    event NFTCreated(
        uint256 indexed tokenId,
        address indexed owner,
        string name,
        uint8 elementType
    );

    // --- Errors ---
    error PaymentIncorrect();
    error MaxSupplyReached();
    error InvalidElementType();
    error InvalidNameLength();
    error InvalidBattleCryLength();
    error WithdrawalFailed();

    // --- Constants ---
    uint256 public constant MAX_SUPPLY = 10000;
    uint8 private constant MIN_STAT_VALUE = 10;
    uint8 private constant MAX_STAT_VALUE = 30;

    // --- State Variables ---
    Counters.Counter private _tokenIdCounter;
    uint256 public mintPrice = 0.01 ether;

    struct NFTStats {
        string name;
        string battleCry;
        uint8 elementType;
        uint8 attack;
        uint8 defense;
        uint8 speed;
        uint8 level;
        uint256 experience;
        bool isEvolved;
    }

    mapping(uint256 => NFTStats) public nftStats;

    // For random stat generation
    enum StatType { Attack, Defense, Speed }

    // --- Constructor ---
    constructor() ERC721("CharacterNFT", "CNFT") {}

    // --- Public Functions ---

    /**
     * @notice Mints a new Character NFT with specified attributes and random stats.
     * @dev Caller must send ETH equal to or greater than `mintPrice`.
     * Validates input parameters and ensures the max supply is not exceeded.
     * @param name The name of the character (1-32 chars).
     * @param battleCry The character's battle cry (1-100 chars).
     * @param elementType The elemental type of the character (0-5).
     */
    function createNFT(
        string calldata name,
        string calldata battleCry,
        uint8 elementType
    ) public payable {
        if (msg.value < mintPrice) {
            revert PaymentIncorrect();
        }

        uint256 currentSupply = _tokenIdCounter.current();
        if (currentSupply >= MAX_SUPPLY) {
            revert MaxSupplyReached();
        }

        if (elementType > 5) {
            revert InvalidElementType();
        }

        uint256 nameLen = bytes(name).length;
        if (nameLen == 0 || nameLen > 32) {
            revert InvalidNameLength();
        }

        uint256 battleCryLen = bytes(battleCry).length;
        if (battleCryLen == 0 || battleCryLen > 100) {
            revert InvalidBattleCryLength();
        }

        _tokenIdCounter.increment();
        uint256 newItemId = _tokenIdCounter.current();
        
        _safeMint(msg.sender, newItemId);

        nftStats[newItemId] = NFTStats({
            name: name,
            battleCry: battleCry,
            elementType: elementType,
            attack: randomStat(newItemId, StatType.Attack, msg.sender),
            defense: randomStat(newItemId, StatType.Defense, msg.sender),
            speed: randomStat(newItemId, StatType.Speed, msg.sender),
            level: 1,
            experience: 0,
            isEvolved: false
        });

        emit NFTCreated(newItemId, msg.sender, name, elementType);
    }

    // --- Owner Functions ---

    /**
     * @notice Allows the owner to set a new mint price.
     * @param newMintPrice The new price for minting an NFT.
     */
    function setMintPrice(uint256 newMintPrice) public onlyOwner {
        mintPrice = newMintPrice;
    }

    /**
     * @notice Allows the owner to withdraw the contract's entire balance.
     * @dev Uses a low-level call to send Ether, which is safer against re-entrancy.
     */
    function withdraw() public onlyOwner {
        (bool success, ) = owner().call{value: address(this).balance}("");
        if (!success) {
            revert WithdrawalFailed();
        }
    }

    // --- Internal Functions ---

    /**
     * @notice Generates a pseudo-random stat value within a defined range.
     * @dev This is NOT a secure source of randomness for high-value applications.
     * It's suitable for non-critical game mechanics. It uses on-chain data which
     * can be predicted or manipulated by miners.
     * @param tokenId The ID of the token for which the stat is being generated.
     * @param statType An enum to differentiate stat calculations.
     * @param sender The address of the minter.
     * @return A random stat value between MIN_STAT_VALUE and MAX_STAT_VALUE.
     */
    function randomStat(
        uint256 tokenId,
        StatType statType,
        address sender
    ) internal view returns (uint8) {
        // `block.prevrandao` (also known as `block.difficulty`) is used for pseudo-randomness.
        // It is not secure and can be influenced by miners. For production systems
        // requiring true randomness, consider a VRF service like Chainlink VRF.
        bytes32 randomHash = keccak256(
            abi.encodePacked(
                block.timestamp,
                block.prevrandao,
                sender,
                tokenId,
                statType
            )
        );

        uint8 range = MAX_STAT_VALUE - MIN_STAT_VALUE + 1;
        return uint8(uint256(randomHash) % range) + MIN_STAT_VALUE;
    }

    // --- View Functions ---

    /**
     * @notice Returns the current total supply of NFTs.
     * @return The number of NFTs minted so far.
     */
    function totalSupply() public view returns (uint256) {
        return _tokenIdCounter.current();
    }
}
