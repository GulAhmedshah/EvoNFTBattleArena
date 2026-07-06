// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title CharacterManager
 * @author Your Name
 * @notice Manages character stats, training, and leveling for an NFT collection.
 * This contract is part of a larger NFT staking platform.
 */
contract CharacterManager {
    // --- State Variables ---

    /**
     * @dev Stats associated with each character NFT.
     * @param level The current level of the character.
     * @param experience The current experience points within the current level.
     * @param strength Affects physical damage or other metrics.
     * @param defense Reduces incoming damage.
     * @param speed Determines turn order or action frequency.
     * @param intelligence Affects magical abilities or other metrics.
     */
    struct CharacterStats {
        uint256 level;
        uint256 experience;
        uint256 strength;
        uint256 defense;
        uint256 speed;
        uint256 intelligence;
    }

    IERC721 public immutable nftContract;

    // --- Constants ---
    uint256 public constant EXPERIENCE_PER_LEVEL = 1000;
    uint256 public constant MAX_LEVEL = 100;
    uint256 public constant STAT_POINTS_PER_LEVEL = 4;
    uint256 public constant BASE_XP_PER_TRAIN = 50;
    uint256 public constant XP_PER_LEVEL_MULTIPLIER = 5;
    uint256 public constant RANDOM_XP_RANGE = 51; // for a random bonus of 0-50 XP

    uint256[] private evolutionMilestones = [10, 25, 50, 75];

    // --- Mappings ---
    mapping(uint256 => CharacterStats) public stats;
    mapping(uint256 => bool) private _isLocked;

    // --- For pseudo-randomness generation ---
    uint256 private _nonce;

    // --- Events ---

    /**
     * @dev Emitted when a character successfully trains.
     * @param tokenId The ID of the trained token.
     * @param experienceGained The amount of experience gained in this session.
     * @param newTotalExperience The new total experience of the character.
     */
    event Trained(uint256 indexed tokenId, uint256 experienceGained, uint256 newTotalExperience);

    /**
     * @dev Emitted when a character levels up.
     * @param tokenId The ID of the token that leveled up.
     * @param newLevel The new level of the character.
     * @param newStrength The new strength stat.
     * @param newDefense The new defense stat.
     * @param newSpeed The new speed stat.
     * @param newIntelligence The new intelligence stat.
     */
    event LevelUp(
        uint256 indexed tokenId,
        uint256 newLevel,
        uint256 newStrength,
        uint256 newDefense,
        uint256 newSpeed,
        uint256 newIntelligence
    );

    // --- Errors ---
    error NotNftOwner();
    error TokenIsLocked();
    error MaxLevelReached();

    // --- Constructor ---

    /**
     * @dev Sets the address of the target NFT contract.
     * @param _nftContractAddress The address of the ERC721 contract.
     */
    constructor(address _nftContractAddress) {
        nftContract = IERC721(_nftContractAddress);
    }

    // --- Public Functions ---

    /**
     * @notice Train a character NFT to gain experience points.
     * @dev The caller must be the owner of the NFT. The NFT cannot be locked (e.g., staked).
     * Gains a base amount of XP plus a level-based bonus and a random component.
     * Automatically triggers a level-up if experience threshold is met.
     * @param tokenId The ID of the token to train.
     */
    function train(uint256 tokenId) external {
        if (nftContract.ownerOf(tokenId) != msg.sender) revert NotNftOwner();
        if (_isLocked[tokenId]) revert TokenIsLocked();

        CharacterStats storage charStats = stats[tokenId];

        // Initialize stats if it's the first time this NFT is interacting
        if (charStats.level == 0) {
            charStats.level = 1;
            charStats.strength = 1;
            charStats.defense = 1;
            charStats.speed = 1;
            charStats.intelligence = 1;
        }

        if (charStats.level >= MAX_LEVEL) revert MaxLevelReached();

        uint256 baseGain = BASE_XP_PER_TRAIN + (charStats.level * XP_PER_LEVEL_MULTIPLIER);
        uint256 randomGain = _pseudoRandom(tokenId) % RANDOM_XP_RANGE; // Random 0-50
        uint256 experienceGained = baseGain + randomGain;

        charStats.experience += experienceGained;

        emit Trained(tokenId, experienceGained, charStats.experience);

        if (charStats.experience >= EXPERIENCE_PER_LEVEL) {
            _levelUp(tokenId);
        }
    }

    // --- View Functions ---

    /**
     * @notice Gets the potential experience gain range for a training session.
     * @param tokenId The ID of the token to check.
     * @return minXp The minimum XP that can be gained.
     * @return maxXp The maximum XP that can be gained.
     */
    function getTrainingReward(uint256 tokenId) external view returns (uint256 minXp, uint256 maxXp) {
        uint256 level = stats[tokenId].level;
        if (level == 0) {
            level = 1; // If not initialized, calculate for level 1
        }

        if (level >= MAX_LEVEL) {
            return (0, 0);
        }

        uint256 baseGain = BASE_XP_PER_TRAIN + (level * XP_PER_LEVEL_MULTIPLIER);
        return (baseGain, baseGain + RANDOM_XP_RANGE - 1);
    }

    /**
     * @notice Checks if a token is currently locked.
     * @param tokenId The ID of the token to check.
     * @return bool True if the token is locked, false otherwise.
     */
    function isLocked(uint256 tokenId) external view returns (bool) {
        return _isLocked[tokenId];
    }

    // --- Internal Functions ---

    /**
     * @dev Handles the logic for leveling up a character.
     * Can handle multiple level-ups in one go.
     * @param tokenId The ID of the token to level up.
     */
    function _levelUp(uint256 tokenId) internal {
        CharacterStats storage charStats = stats[tokenId];

        while (charStats.experience >= EXPERIENCE_PER_LEVEL && charStats.level < MAX_LEVEL) {
            charStats.experience -= EXPERIENCE_PER_LEVEL;
            charStats.level++;

            uint256 newLevel = charStats.level;

            // Check for evolution milestones to reset stats for a re-roll
            for (uint i = 0; i < evolutionMilestones.length; i++) {
                if (newLevel == evolutionMilestones[i]) {
                    charStats.strength = 1;
                    charStats.defense = 1;
                    charStats.speed = 1;
                    charStats.intelligence = 1;
                    break; // Exit loop once milestone is found and stats are reset
                }
            }

            // Distribute stat points
            for (uint256 i = 0; i < STAT_POINTS_PER_LEVEL; ++i) {
                uint256 randomStat = _pseudoRandom(tokenId + i) % 4;
                if (randomStat == 0) {
                    charStats.strength++;
                } else if (randomStat == 1) {
                    charStats.defense++;
                } else if (randomStat == 2) {
                    charStats.speed++;
                } else { // randomStat == 3
                    charStats.intelligence++;
                }
            }

            emit LevelUp(
                tokenId,
                newLevel,
                charStats.strength,
                charStats.defense,
                charStats.speed,
                charStats.intelligence
            );
        }
    }

    /**
     * @dev Generates a pseudo-random number. Not for high-stakes randomness.
     * @param salt A value to add entropy to the random number generation.
     * @return A pseudo-random number.
     */
    function _pseudoRandom(uint256 salt) internal returns (uint256) {
        _nonce++;
        // WARNING: Not a secure source of randomness. Suitable for low-stakes applications.
        // For high-stakes outcomes, use a secure source like Chainlink VRF.
        return uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, salt, _nonce)));
    }

    // --- Lock/Unlock Mechanism (for use by staking functions) ---

    /**
     * @dev Locks a token. Called by other platform functions (e.g., stake).
     */
    function _lock(uint256 tokenId) internal {
        _isLocked[tokenId] = true;
    }

    /**
     * @dev Unlocks a token. Called by other platform functions (e.g., unstake).
     */
    function _unlock(uint256 tokenId) internal {
        _isLocked[tokenId] = false;
    }
}
