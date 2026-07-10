// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title IBattleCalculator
 * @dev Interface for a contract that calculates battle outcomes.
 */
interface IBattleCalculator {
    /**
     * @dev Calculates battle scores for two NFTs based on their stats.
     * @param challengerStats Stats of the challenging NFT.
     * @param opponentStats Stats of the opposing NFT.
     * @return challengerScore The calculated score for the challenger.
     * @return opponentScore The calculated score for the opponent.
     */
    function calculateScores(
        EvoNFT.NFTStats calldata challengerStats,
        EvoNFT.NFTStats calldata opponentStats
    ) external view returns (uint256 challengerScore, uint256 opponentScore);
}

/**
 * @title EvoNFT
 * @author Your Name
 * @dev An ERC721 token with evolvable stats and battle mechanics.
 */
contract EvoNFT is ERC721, ERC721Enumerable, Ownable {
    using Counters for Counters.Counter;

    // =============================================================
    //                           Structs
    // =============================================================

    /**
     * @dev Holds the statistics for a single NFT.
     */
    struct NFTStats {
        uint256 level;
        uint256 experience;
        uint256 wins;
        uint256 losses;
        uint256 battleCount;
        // Other stats like strength, defense, agility could be added here
    }

    /**
     * @dev Records the details of a past battle for a single NFT's perspective.
     */
    struct BattleRecord {
        uint256 battleTimestamp;
        uint256 opponentId;
        address opponentOwner;
        bool isWinner;
        uint256 score;
        uint256 opponentScore;
        uint256 experienceGained;
    }

    // =============================================================
    //                           Constants
    // =============================================================

    uint256 public constant BATTLE_COOLDOWN = 1 days;
    uint256 public constant BASE_EXP_REWARD = 50;
    uint256 public constant LEVEL_DIFF_EXP_BONUS = 25;
    uint256 public constant WINNER_EXP_MULTIPLIER = 3; // 1.5x, using 3/2 to avoid floats
    uint256 public constant WINNER_EXP_DIVISOR = 2;
    uint256 public constant EXP_TO_LEVEL_UP = 1000;

    // =============================================================
    //                             State
    // =============================================================

    Counters.Counter private _nextTokenId;
    address public battleCalculatorAddress;

    mapping(uint256 => NFTStats) private _nftStats;
    mapping(uint256 => bool) private _isLocked;
    mapping(uint256 => uint256) private _lastBattleTimestamp;
    mapping(uint256 => BattleRecord[]) public battleHistory;

    // =============================================================
    //                            Events
    // =============================================================

    event BattleOccurred(
        uint256 indexed challengerId,
        uint256 indexed opponentId,
        uint256 indexed winnerId,
        uint256 loserId,
        uint256 challengerScore,
        uint256 opponentScore,
        uint256 winnerExpGained,
        uint256 loserExpGained
    );

    event LevelUp(uint256 indexed tokenId, uint256 newLevel);

    // =============================================================
    //                             Errors
    // =============================================================

    error InvalidBattleTarget();
    error TokenOnCooldown(uint256 tokenId, uint256 timeLeft);
    error TokenLocked(uint256 tokenId);
    error NotTokenOwner();
    error TokenDoesNotExist(uint256 tokenId);
    error BattleCalculatorNotSet();

    // =============================================================
    //                          Constructor
    // =============================================================

    constructor() ERC721("EvoNFT", "EVO") {}

    // =============================================================
    //                        Battle Functions
    // =============================================================

    /**
     * @notice Initiates a battle between two NFTs.
     * @dev Validates ownership, cooldowns, and lock status before proceeding.
     *      Calculates scores, determines a winner, updates stats, and records the battle.
     * @param challengerTokenId The token ID of the NFT initiating the challenge (owned by msg.sender).
     * @param opponentTokenId The token ID of the NFT being challenged.
     * @param opponentAddress The address of the owner of the opponent's NFT.
     */
    function challengeBattle(
        uint256 challengerTokenId,
        uint256 opponentTokenId,
        address opponentAddress
    ) external {
        // --- Validation ---
        if (challengerTokenId == opponentTokenId || msg.sender == opponentAddress) revert InvalidBattleTarget();
        if (battleCalculatorAddress == address(0)) revert BattleCalculatorNotSet();

        if (ownerOf(challengerTokenId) != msg.sender) revert NotTokenOwner();
        if (ownerOf(opponentTokenId) != opponentAddress) revert NotTokenOwner();

        if (_isLocked[challengerTokenId]) revert TokenLocked(challengerTokenId);
        if (_isLocked[opponentTokenId]) revert TokenLocked(opponentTokenId);

        uint256 challengerCooldownEnd = _lastBattleTimestamp[challengerTokenId] + BATTLE_COOLDOWN;
        if (block.timestamp < challengerCooldownEnd) {
            revert TokenOnCooldown(challengerTokenId, challengerCooldownEnd - block.timestamp);
        }
        uint256 opponentCooldownEnd = _lastBattleTimestamp[opponentTokenId] + BATTLE_COOLDOWN;
        if (block.timestamp < opponentCooldownEnd) {
            revert TokenOnCooldown(opponentTokenId, opponentCooldownEnd - block.timestamp);
        }

        // --- Battle Logic ---
        NFTStats storage challengerStats = _nftStats[challengerTokenId];
        NFTStats storage opponentStats = _nftStats[opponentTokenId];

        (uint256 challengerScore, uint256 opponentScore) = IBattleCalculator(battleCalculatorAddress).calculateScores(
            challengerStats,
            opponentStats
        );

        // --- Determine Winner & Loser ---
        uint256 winnerId;
        uint256 loserId;
        NFTStats storage winnerStats;
        NFTStats storage loserStats;
        uint256 winnerScore; 
        uint256 loserScore;

        if (challengerScore >= opponentScore) {
            winnerId = challengerTokenId;
            loserId = opponentTokenId;
            winnerStats = challengerStats;
            loserStats = opponentStats;
            winnerScore = challengerScore;
            loserScore = opponentScore;
        } else {
            winnerId = opponentTokenId;
            loserId = challengerTokenId;
            winnerStats = opponentStats;
            loserStats = challengerStats;
            winnerScore = opponentScore;
            loserScore = challengerScore;
        }

        // --- Calculate Experience ---
        uint256 levelDifference =
            winnerStats.level > loserStats.level ? winnerStats.level - loserStats.level : loserStats.level - winnerStats.level;
        uint256 baseExp = BASE_EXP_REWARD + (levelDifference * LEVEL_DIFF_EXP_BONUS);
        uint256 winnerExpGained = (baseExp * WINNER_EXP_MULTIPLIER) / WINNER_EXP_DIVISOR;
        uint256 loserExpGained = baseExp;

        // --- Update Stats & Apply Experience ---
        winnerStats.wins++;
        loserStats.losses++;
        winnerStats.battleCount++;
        loserStats.battleCount++;

        _applyExperience(winnerId, winnerExpGained);
        _applyExperience(loserId, loserExpGained);

        // --- Reset Cooldowns ---
        uint256 battleTimestamp = block.timestamp;
        _lastBattleTimestamp[challengerTokenId] = battleTimestamp;
        _lastBattleTimestamp[opponentTokenId] = battleTimestamp;

        // --- Store Battle History ---
        battleHistory[challengerTokenId].push(
            BattleRecord(
                battleTimestamp,
                opponentTokenId,
                opponentAddress,
                challengerId == winnerId,
                challengerScore,
                opponentScore,
                challengerId == winnerId ? winnerExpGained : loserExpGained
            )
        );
        battleHistory[opponentTokenId].push(
            BattleRecord(
                battleTimestamp,
                challengerTokenId,
                msg.sender,
                opponentId == winnerId,
                opponentScore,
                challengerScore,
                opponentId == winnerId ? winnerExpGained : loserExpGained
            )
        );

        // --- Emit Event ---
        emit BattleOccurred(
            challengerTokenId,
            opponentTokenId,
            winnerId,
            loserId,
            challengerScore,
            opponentScore,
            winnerExpGained,
            loserExpGained
        );
    }

    // =============================================================
    //                      Internal Functions
    // =============================================================

    /**
     * @dev Applies experience to an NFT and handles level-ups.
     * @param tokenId The ID of the token gaining experience.
     * @param expGained The amount of experience gained.
     */
    function _applyExperience(uint256 tokenId, uint256 expGained) internal {
        NFTStats storage stats = _nftStats[tokenId];
        stats.experience += expGained;

        uint256 newLevel = 1 + (stats.experience / EXP_TO_LEVEL_UP);
        if (newLevel > stats.level) {
            stats.level = newLevel;
            emit LevelUp(tokenId, newLevel);
        }
    }

    /**
     * @dev See {ERC721-_beforeTokenTransfer}.
     */
    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    // =============================================================
    //                        Admin Functions
    // =============================================================

    /**
     * @notice Mints a new EvoNFT and assigns it to an owner.
     * @dev Initializes the NFT with base stats. Can only be called by the contract owner.
     * @param to The address that will own the newly minted NFT.
     */
    function mint(address to) external onlyOwner {
        uint256 tokenId = _nextTokenId.current();
        _nextTokenId.increment();
        _safeMint(to, tokenId);
        _nftStats[tokenId] = NFTStats({
            level: 1,
            experience: 0,
            wins: 0,
            losses: 0,
            battleCount: 0
        });
    }

    /**
     * @notice Sets the address of the Battle Calculator contract.
     * @dev Can only be called by the contract owner.
     * @param _calculatorAddress The new address for the battle calculator.
     */
    function setBattleCalculator(address _calculatorAddress) external onlyOwner {
        battleCalculatorAddress = _calculatorAddress;
    }

    /**
     * @notice Marks a token as locked (e.g., for staking).
     * @dev Locked tokens cannot participate in battles. Can only be called by the contract owner.
     * @param tokenId The ID of the token to lock.
     */
    function lockToken(uint256 tokenId) external onlyOwner {
        if (!_exists(tokenId)) revert TokenDoesNotExist(tokenId);
        _isLocked[tokenId] = true;
    }

    /**
     * @notice Marks a token as unlocked.
     * @dev Can only be called by the contract owner.
     * @param tokenId The ID of the token to unlock.
     */
    function unlockToken(uint256 tokenId) external onlyOwner {
        if (!_exists(tokenId)) revert TokenDoesNotExist(tokenId);
        _isLocked[tokenId] = false;
    }

    // =============================================================
    //                         View Functions
    // =============================================================

    /**
     * @notice Retrieves the stats for a given NFT.
     * @param tokenId The ID of the token to query.
     * @return The NFTStats struct for the token.
     */
    function getNFTStats(uint256 tokenId) external view returns (NFTStats memory) {
        if (!_exists(tokenId)) revert TokenDoesNotExist(tokenId);
        return _nftStats[tokenId];
    }

    /**
     * @notice Retrieves the full battle history for a given NFT.
     * @param tokenId The ID of the token to query.
     * @return An array of BattleRecord structs.
     */
    function getBattleHistory(uint256 tokenId) external view returns (BattleRecord[] memory) {
        if (!_exists(tokenId)) revert TokenDoesNotExist(tokenId);
        return battleHistory[tokenId];
    }

    /**
     * @notice Checks if a token is currently locked.
     * @param tokenId The ID of the token to check.
     * @return True if the token is locked, false otherwise.
     */
    function isLocked(uint256 tokenId) external view returns (bool) {
        return _isLocked[tokenId];
    }

    /**
     * @notice See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}