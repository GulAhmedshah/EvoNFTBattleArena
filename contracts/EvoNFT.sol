// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Import required OpenZeppelin contracts
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title EvoNFT
 * @author Your Name
 * @notice An evolvable NFT contract for a staking and battling platform.
 * @dev This contract manages the creation, stats, battles, and evolution of NFTs.
 */
contract EvoNFT is ERC721Enumerable, Ownable {
    using Counters for Counters.Counter;
    using Strings for uint256;

    /**
     * @notice Defines the elemental types for NFTs.
     * 0: Fire, 1: Water, 2: Earth, 3: Air, 4: Light, 5: Dark
     */
    enum ElementType { Fire, Water, Earth, Air, Light, Dark }

    /**
     * @notice Represents the detailed statistics and attributes of a single NFT.
     * @param strength The attack power of the NFT.
     * @param defense The defensive capability of the NFT.
     * @param speed Determines turn order and dodge chance in battles.
     * @param intelligence Affects special abilities and magic resistance.
     * @param level The current level of the NFT.
     * @param experience The current experience points of the NFT.
     * @param wins The total number of battles won.
     * @param losses The total number of battles lost.
     * @param battleCount The total number of battles participated in.
     * @param lastBattleTime The timestamp of the last battle.
     * @param name The custom name of the NFT.
     * @param battleCry A unique catchphrase for the NFT.
     * @param elementType The elemental type of the NFT, corresponds to ElementType enum.
     * @param isEvolved A flag indicating if the NFT has evolved.
     * @param evolutionTimestamp The timestamp of when the NFT evolved.
     */
    struct NFTStats {
        uint256 strength;
        uint256 defense;
        uint256 speed;
        uint256 intelligence;
        uint256 level;
        uint256 experience;
        uint256 wins;
        uint256 losses;
        uint256 battleCount;
        uint256 lastBattleTime;
        string name;
        string battleCry;
        uint8 elementType;
        bool isEvolved;
        uint256 evolutionTimestamp;
    }

    /**
     * @notice Records the details of a completed battle.
     * @param challenger The address of the challenging player.
     * @param opponent The address of the opposing player.
     * @param tokenIds An array containing the token IDs of the battling NFTs.
     * @param winner The address of the winning player.
     * @param timestamp The time the battle occurred.
     * @param scores An array of the final scores for each participant.
     */
    struct BattleRecord {
        address challenger;
        address opponent;
        uint256[] tokenIds;
        address winner;
        uint256 timestamp;
        uint256[] scores;
    }

    // --- Mappings ---

    /// @notice Maps a token ID to its detailed statistics.
    mapping(uint256 => NFTStats) public nftStats;

    /// @notice Maps a token ID to an array of its battle records.
    mapping(uint256 => BattleRecord[]) public battleHistory;

    /// @notice Maps a token ID to its locked status. Locked tokens cannot be transferred or battled.
    mapping(uint256 => bool) public isTokenLocked;

    /**
     * @notice Maps an owner's address to an array of their token IDs.
     * @dev Redundant with ERC721Enumerable, but can be used for app-specific logic. Requires manual sync.
     */
    mapping(address => uint256[]) public ownerTokens;

    /// @notice Maps a token ID to the timestamp when its battle cooldown period ends.
    mapping(uint256 => uint256) public battleCooldown;

    // --- Constants ---

    /// @notice The maximum level an NFT can achieve.
    uint256 public constant MAX_LEVEL = 100;
    /// @notice The amount of experience required to advance to the next level.
    uint256 public constant EXPERIENCE_PER_LEVEL = 1000;
    /// @notice The cooldown period between battles for a single NFT.
    uint256 public constant BATTLE_COOLDOWN = 1 days;

    // --- State Variables ---

    /// @notice The fee required to evolve an NFT.
    uint256 public evolutionFee;
    /// @notice The price to mint a new NFT.
    uint256 public mintPrice;
    /// @notice The maximum total supply of NFTs.
    uint256 public maxSupply;
    /// @notice A counter for the total number of battles that have occurred.
    uint256 public totalBattles;

    // --- Events ---

    event NFTCreated(uint256 indexed tokenId, address indexed owner, uint8 elementType, string name);
    event LevelUp(uint256 indexed tokenId, uint256 newLevel);
    event BattleOccurred(uint256 indexed battleId, uint256 indexed challengerTokenId, uint256 indexed opponentTokenId, address winner);
    event NFTEvolved(uint256 indexed tokenId);
    event NFTLocked(uint256 indexed tokenId, bool locked);
    event ElementChanged(uint256 indexed tokenId, uint8 oldElement, uint8 newElement);

    // --- Constructor ---

    /**
     * @notice Initializes the contract, setting up the NFT collection and contract parameters.
     * @param _name The name of the NFT collection (e.g., "EvoNFT").
     * @param _symbol The symbol of the NFT collection (e.g., "EVO").
     * @param _mintPrice The initial price for minting a new NFT.
     * @param _maxSupply The maximum number of NFTs that can be minted.
     * @param _evolutionFee The initial fee for evolving an NFT.
     */
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _mintPrice,
        uint256 _maxSupply,
        uint256 _evolutionFee
    ) ERC721(_name, _symbol) {
        mintPrice = _mintPrice;
        maxSupply = _maxSupply;
        evolutionFee = _evolutionFee;
    }
}
