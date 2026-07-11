// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title NFTStaking
 * @author Your Name
 * @notice A comprehensive NFT staking platform with gamified elements like levels, battles, and evolutions.
 * This contract manages NFT stats, battle history, levels, experience, and more.
 */
contract NFTStaking is ERC721Enumerable, Ownable, ReentrancyGuard {
    using Strings for uint256;

    // --- CUSTOM ERRORS ---
    error NFTNotOwned(address owner, uint256 tokenId);
    error TokenIsLocked(uint256 tokenId);
    error TokenOnCooldown(uint256 tokenId, uint256 cooldownRemaining);
    error InvalidElement();
    error BatchSizeTooLarge(uint256 size, uint256 max);

    // --- ENUMS & STRUCTS ---

    /**
     * @dev Elemental types for NFTs, used in battle advantage calculations.
     */
    enum Element { NONE, FIRE, WATER, GRASS, LIGHT, DARK }

    /**
     * @dev Core statistics for each NFT.
     */
    struct NFTStats {
        uint16 level;
        uint256 experience;
        uint32 wins;
        uint32 losses;
        Element element;
        uint256 lastBattleTimestamp;
        uint8 evolutionStage;
    }

    /**
     * @dev Information regarding the rental status of an NFT.
     */
    struct RentalInfo {
        bool isRented;
        address renter;
        uint256 rentalEnds;
    }

    /**
     * @dev A record of a single battle for an NFT.
     */
    struct BattleRecord {
        uint256 opponentTokenId;
        bool won;
        uint256 timestamp;
    }

    /**
     * @dev Represents an NFT in the top leaderboard.
     */
    struct TopNFT {
        uint256 tokenId;
        uint256 battlePower;
    }

    // --- STATE VARIABLES ---
    uint256 private _nextTokenId;
    
    // Mappings
    mapping(uint256 => NFTStats) private _nftStats;
    mapping(uint256 => RentalInfo) private _rentalInfo;
    mapping(uint256 => BattleRecord[]) private _battleHistories;
    mapping(uint256 => bool) private _isLocked; // General purpose lock for staking, battling etc.

    // Constants
    uint256 public constant BATTLE_COOLDOWN = 1 hours;
    uint256 public constant MAX_BATCH_SIZE = 50;

    // Leaderboard
    TopNFT[10] private _topNFTs;

    // --- EVENTS ---
    event LevelUp(uint256 indexed tokenId, uint16 newLevel);
    event BattleFinished(uint256 indexed winnerId, uint256 indexed loserId);
    event ExperienceGained(uint256 indexed tokenId, uint256 xpGained);

    // --- CONSTRUCTOR ---
    constructor() ERC721("GameFi NFT", "GFN") {}

    // --- MINTING (EXAMPLE) ---

    /**
     * @notice Mints a new NFT with specified element and assigns it to an owner.
     * @dev Initializes stats for the new NFT. Only callable by the contract owner.
     * @param to The address to receive the new NFT.
     * @param element The element for the new NFT.
     */
    function mint(address to, Element element) public onlyOwner {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        _nftStats[tokenId] = NFTStats({
            level: 1,
            experience: 0,
            wins: 0,
            losses: 0,
            element: element,
            lastBattleTimestamp: 0,
            evolutionStage: 1
        });
    }

    // --- VIEW FUNCTIONS ---

    /**
     * @notice Gets all core statistics for a given NFT.
     * @param tokenId The ID of the NFT.
     * @return A struct containing all stats of the NFT.
     */
    function getNFTStats(uint256 tokenId) external view returns (NFTStats memory) {
        require(_exists(tokenId), "ERC721: invalid token ID");
        return _nftStats[tokenId];
    }

    /**
     * @notice Retrieves the battle history for a specific NFT.
     * @param tokenId The ID of the NFT.
     * @return An array of BattleRecord structs.
     */
    function getBattleHistory(uint256 tokenId) external view returns (BattleRecord[] memory) {
        require(_exists(tokenId), "ERC721: invalid token ID");
        return _battleHistories[tokenId];
    }

    /**
     * @notice Gets the current level of an NFT.
     * @param tokenId The ID of the NFT.
     * @return The current level.
     */
    function getNFTLevel(uint256 tokenId) external view returns (uint16) {
        require(_exists(tokenId), "ERC721: invalid token ID");
        return _nftStats[tokenId].level;
    }

    /**
     * @notice Gets the NFT's current experience and the amount needed for the next level.
     * @param tokenId The ID of the NFT.
     * @return currentXp The experience the NFT currently has.
     * @return xpForNextLevel The total experience required to reach the next level.
     */
    function getExperienceProgress(uint256 tokenId) external view returns (uint256 currentXp, uint256 xpForNextLevel) {
        require(_exists(tokenId), "ERC721: invalid token ID");
        NFTStats storage stats = _nftStats[tokenId];
        return (stats.experience, _xpToNextLevel(stats.level));
    }

    /**
     * @notice Calculates the battle power of an NFT based on its stats.
     * @param tokenId The ID of the NFT.
     * @return The calculated battle power.
     */
    function getBattlePower(uint256 tokenId) public view returns (uint256) {
        require(_exists(tokenId), "ERC721: invalid token ID");
        NFTStats storage stats = _nftStats[tokenId];
        // Example formula: Each level adds 10 power, each win adds 1.
        return (stats.level * 10) + stats.wins;
    }

    /**
     * @notice Shows the NFT's progress towards its next evolution.
     * @dev Example: Evolution occurs at level 15 and 30.
     * @param tokenId The ID of the NFT.
     * @return currentLevel The current level of the NFT.
     * @return evolutionLevel The level required for the next evolution.
     */
    function getEvolutionProgress(uint256 tokenId) external view returns (uint16 currentLevel, uint16 evolutionLevel) {
        require(_exists(tokenId), "ERC721: invalid token ID");
        NFTStats storage stats = _nftStats[tokenId];
        uint16 nextEvolutionLevel = 0;
        if (stats.level < 15) {
            nextEvolutionLevel = 15;
        } else if (stats.level < 30) {
            nextEvolutionLevel = 30;
        }
        // If max evolution, returns 0 for evolutionLevel
        return (stats.level, nextEvolutionLevel);
    }

    /**
     * @notice Retrieves the rental status of an NFT.
     * @param tokenId The ID of the NFT.
     * @return A struct containing the rental information.
     */
    function getRentalStatus(uint256 tokenId) external view returns (RentalInfo memory) {
        require(_exists(tokenId), "ERC721: invalid token ID");
        return _rentalInfo[tokenId];
    }

    /**
     * @notice Calculates the elemental advantage multiplier.
     * @param attacker The element of the attacking NFT.
     * @param defender The element of the defending NFT.
     * @return Multiplier (e.g., 200 for 2x, 100 for 1x, 50 for 0.5x).
     */
    function getElementAdvantage(Element attacker, Element defender) external pure returns (uint256) {
        if (attacker == Element.NONE || defender == Element.NONE) return 100;
        if (attacker == defender) return 100;

        if ((attacker == Element.FIRE && defender == Element.GRASS) ||
            (attacker == Element.GRASS && defender == Element.WATER) ||
            (attacker == Element.WATER && defender == Element.FIRE)) {
            return 200; // Advantage
        }

        if ((attacker == Element.GRASS && defender == Element.FIRE) ||
            (attacker == Element.WATER && defender == Element.GRASS) ||
            (attacker == Element.FIRE && defender == Element.WATER)) {
            return 50; // Disadvantage
        }

        if ((attacker == Element.LIGHT && defender == Element.DARK) ||
            (attacker == Element.DARK && defender == Element.LIGHT)) {
            return 200; // Mutual advantage
        }

        return 100; // Neutral
    }

    // --- BATCH VIEW FUNCTIONS ---

    /**
     * @notice Gets statistics for multiple NFTs in a single call.
     * @param tokenIds An array of NFT IDs.
     * @return An array of NFTStats structs.
     */
    function getMultipleNFTStats(uint256[] calldata tokenIds) external view returns (NFTStats[] memory) {
        if (tokenIds.length > MAX_BATCH_SIZE) revert BatchSizeTooLarge(tokenIds.length, MAX_BATCH_SIZE);
        NFTStats[] memory allStats = new NFTStats[](tokenIds.length);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(_exists(tokenIds[i]), "ERC721: invalid token ID");
            allStats[i] = _nftStats[tokenIds[i]];
        }
        return allStats;
    }

    /**
     * @notice Gets the top 10 NFTs ranked by battle power.
     * @return An array of TopNFT structs, sorted highest to lowest power.
     */
    function getTopNFTs() external view returns (TopNFT[10] memory) {
        return _topNFTs;
    }

    // --- UTILITY & INTERNAL FUNCTIONS ---

    /**
     * @notice Internal function to transfer an NFT, with an additional check for a lock status.
     * @dev This should be used internally instead of _safeTransfer when a lock is relevant.
     *      Note: A more robust pattern is overriding _beforeTokenTransfer to enforce this on all transfers.
     * @param from The current owner of the NFT.
     * @param to The new owner.
     * @param tokenId The ID of the NFT to transfer.
     */
    function _safeTransferWithLockCheck(address from, address to, uint256 tokenId) internal {
        if (_isLocked[tokenId]) revert TokenIsLocked(tokenId);
        _safeTransfer(from, to, tokenId, "");
    }

    /**
     * @notice Updates the win/loss record for a token and records the battle.
     * @param tokenId The ID of the token being updated.
     * @param opponentTokenId The ID of the opponent token.
     * @param won A boolean indicating if the battle was won.
     */
    function _updateBattleStats(uint256 tokenId, uint256 opponentTokenId, bool won) internal {
        NFTStats storage stats = _nftStats[tokenId];
        stats.lastBattleTimestamp = block.timestamp;
        if (won) {
            stats.wins++;
        } else {
            stats.losses++;
        }
        _battleHistories[tokenId].push(BattleRecord({
            opponentTokenId: opponentTokenId,
            won: won,
            timestamp: block.timestamp
        }));
        // Does not emit event here, assumed to be part of a larger battle function
    }

    /**
     * @notice Applies experience to an NFT and handles level-ups.
     * @param tokenId The ID of the NFT receiving experience.
     * @param xpGained The amount of experience gained.
     */
    function _applyExperience(uint256 tokenId, uint256 xpGained) internal {
        NFTStats storage stats = _nftStats[tokenId];
        stats.experience += xpGained;
        emit ExperienceGained(tokenId, xpGained);

        uint256 requiredXp = _xpToNextLevel(stats.level);
        while (stats.experience >= requiredXp) {
            stats.level++;
            stats.experience -= requiredXp;
            emit LevelUp(tokenId, stats.level);
            requiredXp = _xpToNextLevel(stats.level);
        }
        // After stats change, update its position in the leaderboard
        _updateTopNFTs(tokenId);
    }

    /**
     * @notice Checks if an NFT is on battle cooldown.
     * @dev Reverts if the NFT is still on cooldown.
     * @param tokenId The ID of the NFT to check.
     */
    function _checkCooldown(uint256 tokenId) internal view {
        uint256 lastBattle = _nftStats[tokenId].lastBattleTimestamp;
        if (lastBattle > 0) {
            uint256 cooldownEnd = lastBattle + BATTLE_COOLDOWN;
            if (block.timestamp < cooldownEnd) {
                revert TokenOnCooldown(tokenId, cooldownEnd - block.timestamp);
            }
        }
    }

    // --- PRIVATE HELPER FUNCTIONS ---

    /**
     * @dev Calculates the experience needed to advance from a given level.
     * @param level The current level.
     * @return The total experience points required for the next level.
     */
    function _xpToNextLevel(uint16 level) private pure returns (uint256) {
        // A simple curve: (level + 1) * 100
        return (uint256(level) + 1) * 100;
    }

    /**
     * @dev Updates the top 10 leaderboard if the given token qualifies.
     * @param tokenId The ID of the token whose power may have changed.
     */
    function _updateTopNFTs(uint256 tokenId) private {
        uint256 newPower = getBattlePower(tokenId);
        uint256 lowestTopPower = _topNFTs[9].battlePower;
        
        // Exit early if power is not high enough, unless the token is already in the list
        int256 listIndex = -1;
        for (uint8 i = 0; i < 10; i++) {
            if (_topNFTs[i].tokenId == tokenId) {
                listIndex = int256(i);
                break;
            }
        }

        if (newPower <= lowestTopPower && listIndex == -1) {
            return; // Not powerful enough to make the list
        }

        // Remove the old entry if it exists
        if (listIndex != -1) {
            for (uint256 i = uint256(listIndex); i < 9; i++) {
                _topNFTs[i] = _topNFTs[i+1];
            }
            _topNFTs[9] = TopNFT(0, 0);
        }
        
        // Insert new entry at the bottom
        _topNFTs[9] = TopNFT(tokenId, newPower);

        // Bubble it up to the correct sorted position
        for (uint256 i = 9; i > 0; i--) {
            if (_topNFTs[i].battlePower > _topNFTs[i-1].battlePower) {
                TopNFT memory temp = _topNFTs[i-1];
                _topNFTs[i-1] = _topNFTs[i];
                _topNFTs[i] = temp;
            } else {
                // In correct position
                break;
            }
        }
    }

    /**
     * @dev Overridden to ensure lock status is checked before any transfer.
     */
    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize)
        internal
        virtual
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
        if (from != address(0)) { // Not a mint transfer
            if (_isLocked[tokenId]) revert TokenIsLocked(tokenId);
        }
    }
}