// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title GameMechanics
 * @author Your Name
 * @notice This contract manages the game-related logic for NFTs, including stats, levels, training, and battles.
 * It serves as the on-chain backend for game features, emitting events that a frontend can use for notifications.
 */
contract GameMechanics is Ownable, ReentrancyGuard {
    // --- Errors ---
    error NotNFTOwner();
    error NFTNotRegistered(uint256 tokenId);
    error NFTAlreadyRegistered(uint256 tokenId);
    error InvalidElement();
    error CooldownActive(uint256 timeLeft);
    error InsufficientPayment();
    error CannotBattleSelf();
    error MaxLevelReached();

    // --- Enums & Structs ---

    /**
     * @dev Elemental types for NFTs, influencing battles and abilities.
     */
    enum Element { Fire, Water, Earth, Air, Light, Dark }

    /**
     * @dev Rarity tiers for NFTs, affecting their base power and potential.
     */
    enum Tier { Common, Uncommon, Rare, Epic, Legendary, Mythic }

    /**
     * @dev Core statistics for an NFT that determine its combat prowess.
     */
    struct NFTStats {
        uint32 attack;
        uint32 defense;
        uint32 speed;
    }

    /**
     * @dev The complete game-related profile of an NFT.
     */
    struct NFTGameProfile {
        uint256 xp;
        uint256 level;
        Element element;
        Tier tier;
        NFTStats stats;
        uint256 lastActionTimestamp; // Used for training/battle cooldowns
    }

    // --- State Variables ---

    IERC721 public immutable nftContract;

    /// @notice Mapping from NFT token ID to its game profile.
    mapping(uint256 => NFTGameProfile) public nftProfiles;

    /// @notice Time in seconds an NFT must wait between training sessions.
    uint256 public trainingCooldown = 1 days;
    /// @notice Cost in wei to train an NFT.
    uint256 public trainingCost = 0.01 ether;
    /// @notice XP gained from a single training session.
    uint256 public trainingXpGain = 50;

    /// @notice The maximum level an NFT can achieve.
    uint256 public constant MAX_LEVEL = 100;

    // --- Events ---

    event NFTRegistered(uint256 indexed tokenId, Element element, Tier tier);
    event Trained(uint256 indexed tokenId, uint256 xpGained, uint256 newXp, uint256 newTotalXp);
    event LeveledUp(uint256 indexed tokenId, uint256 newLevel);
    event Evolved(uint256 indexed tokenId, Tier newTier, Element newElement);
    event BattleResultSet(
        uint256 indexed battleId, // A future identifier for battles
        uint256 indexed winnerId,
        uint256 indexed loserId,
        uint256 xpGained
    );

    // --- Constructor ---

    /**
     * @notice Sets the address of the main NFT contract.
     * @param _nftContractAddress The address of the ERC721 NFT contract.
     */
    constructor(address _nftContractAddress) {
        nftContract = IERC721(_nftContractAddress);
    }

    // --- Owner Functions ---

    /**
     * @notice Updates the cost for a training session.
     * @param _newCost The new cost in wei.
     */
    function setTrainingCost(uint256 _newCost) external onlyOwner {
        trainingCost = _newCost;
    }

    /**
     * @notice Updates the cooldown period for training.
     * @param _newCooldown The new cooldown in seconds.
     */
    function setTrainingCooldown(uint256 _newCooldown) external onlyOwner {
        trainingCooldown = _newCooldown;
    }

    /**
     * @notice Updates the XP gained from training.
     * @param _newXpGain The new XP amount.
     */
    function setTrainingXpGain(uint256 _newXpGain) external onlyOwner {
        trainingXpGain = _newXpGain;
    }

    /**
     * @notice Registers a new NFT, initializing its game profile.
     * @dev Can only be called by the owner, intended for use on mint or by a trusted contract.
     * @param tokenId The ID of the NFT to register.
     * @param element The initial element of the NFT.
     * @param tier The initial tier of the NFT.
     * @param stats The initial stats of the NFT.
     */
    function registerNFT(uint256 tokenId, Element element, Tier tier, NFTStats calldata stats) external onlyOwner {
        if (nftProfiles[tokenId].level > 0) {
            revert NFTAlreadyRegistered(tokenId);
        }

        nftProfiles[tokenId] = NFTGameProfile({
            xp: 0,
            level: 1,
            element: element,
            tier: tier,
            stats: stats,
            lastActionTimestamp: 0
        });

        emit NFTRegistered(tokenId, element, tier);
    }

    // --- Public & External Functions ---

    /**
     * @notice Allows a user to train their NFT, gaining XP.
     * @dev Requires a fee and enforces a cooldown period.
     * @param tokenId The ID of the NFT to train.
     */
    function train(uint256 tokenId) external payable nonReentrant {
        if (msg.sender != nftContract.ownerOf(tokenId)) {
            revert NotNFTOwner();
        }
        if (trainingCost > 0 && msg.value < trainingCost) {
            revert InsufficientPayment();
        }

        NFTGameProfile storage profile = nftProfiles[tokenId];
        if (profile.level == 0) {
            revert NFTNotRegistered(tokenId);
        }
        if (profile.level >= MAX_LEVEL) {
            revert MaxLevelReached();
        }

        uint256 cooldownEnds = profile.lastActionTimestamp + trainingCooldown;
        if (block.timestamp < cooldownEnds) {
            revert CooldownActive(cooldownEnds - block.timestamp);
        }

        profile.lastActionTimestamp = block.timestamp;
        _grantXP(tokenId, profile, trainingXpGain);

        emit Trained(tokenId, trainingXpGain, profile.xp, _calculateTotalXp(profile.level, profile.xp));
    }

    /**
     * @notice Simulates a battle between two NFTs.
     * @dev The winner is determined by battle power and gains XP.
     * @param attackerId The token ID of the attacking NFT, owned by msg.sender.
     * @param defenderId The token ID of the defending NFT.
     */
    function battle(uint256 attackerId, uint256 defenderId) external nonReentrant {
        if (attackerId == defenderId) revert CannotBattleSelf();
        if (msg.sender != nftContract.ownerOf(attackerId)) revert NotNFTOwner();

        NFTGameProfile storage attackerProfile = nftProfiles[attackerId];
        NFTGameProfile storage defenderProfile = nftProfiles[defenderId];

        if (attackerProfile.level == 0) revert NFTNotRegistered(attackerId);
        if (defenderProfile.level == 0) revert NFTNotRegistered(defenderId);

        uint256 attackerPower = calculateBattlePower(attackerId);
        uint256 defenderPower = calculateBattlePower(defenderId);

        uint256 winnerId;
        uint256 loserId;

        // Deterministic battle outcome based on power
        if (attackerPower >= defenderPower) {
            winnerId = attackerId;
            loserId = defenderId;
        } else {
            winnerId = defenderId;
            loserId = attackerId;
        }
        
        // Grant XP to the winner
        NFTGameProfile storage winnerProfile = nftProfiles[winnerId];
        if (winnerProfile.level < MAX_LEVEL) {
             uint256 xpGained = 100; // Example XP gain
            _grantXP(winnerId, winnerProfile, xpGained);
            emit BattleResultSet(0, winnerId, loserId, xpGained); // BattleID 0 for now
        }
    }

    // --- View & Pure Functions ---

    /**
     * @notice Calculates the experience needed to reach the next level.
     * @param level The current level.
     * @return The amount of XP required for the next level up.
     */
    function xpToNextLevel(uint256 level) public pure returns (uint256) {
        if (level == 0) return 100; // Base case for level 1
        if (level >= MAX_LEVEL) return type(uint256).max; // Effectively infinite
        return 100 * (level ** 2);
    }

    /**
     * @notice Calculates the battle power of a given NFT.
     * @dev The formula combines stats, level, and tier.
     * @param tokenId The ID of the NFT.
     * @return The calculated battle power.
     */
    function calculateBattlePower(uint256 tokenId) public view returns (uint256) {
        NFTGameProfile memory profile = nftProfiles[tokenId];
        if (profile.level == 0) {
            return 0;
        }

        uint256 statsSum = profile.stats.attack + profile.stats.defense + profile.stats.speed;
        uint256 tierBonus = _getTierBonus(profile.tier);

        // Formula: (TotalStats) * Level * TierBonus / 100
        return (statsSum * profile.level * tierBonus) / 100;
    }

    /**
     * @notice Retrieves all game-related data for a specific NFT.
     * @dev Useful for frontend to fetch all data in one call.
     * @param tokenId The ID of the NFT.
     * @return A struct containing the NFT's game profile.
     */
    function getNFTGameData(uint256 tokenId) public view returns (NFTGameProfile memory) {
        return nftProfiles[tokenId];
    }

    // --- Internal & Private Functions ---

    /**
     * @dev Grants experience to an NFT and handles level-ups.
     * @param tokenId The ID of the NFT receiving XP.
     * @param profile The storage pointer to the NFT's profile.
     * @param xpAmount The amount of XP to grant.
     */
    function _grantXP(uint256 tokenId, NFTGameProfile storage profile, uint256 xpAmount) internal {
        profile.xp += xpAmount;
        uint256 requiredXp = xpToNextLevel(profile.level);

        while (profile.xp >= requiredXp && profile.level < MAX_LEVEL) {
            profile.xp -= requiredXp;
            profile.level++;
            _applyLevelUpStatGains(profile);

            emit LeveledUp(tokenId, profile.level);

            requiredXp = xpToNextLevel(profile.level);
        }
    }

    /**
     * @dev Applies stat increases when an NFT levels up.
     * @param profile The storage pointer to the NFT's profile.
     */
    function _applyLevelUpStatGains(NFTGameProfile storage profile) internal {
        // Example: Increase stats by a small amount each level
        profile.stats.attack += 1;
        profile.stats.defense += 1;
        profile.stats.speed += 1;
    }

    /**
     * @dev Calculates a bonus multiplier based on the NFT's tier.
     * @param tier The tier of the NFT.
     * @return The bonus multiplier (e.g., 100 for 1.00x, 120 for 1.20x).
     */
    function _getTierBonus(Tier tier) internal pure returns (uint256) {
        if (tier == Tier.Common) return 100;
        if (tier == Tier.Uncommon) return 110;
        if (tier == Tier.Rare) return 125;
        if (tier == Tier.Epic) return 150;
        if (tier == Tier.Legendary) return 180;
        if (tier == Tier.Mythic) return 220;
        return 100;
    }

    /**
     * @dev Helper to calculate an NFT's total accumulated XP from level 1.
     * @param level The current level.
     * @param currentLevelXp The XP accumulated within the current level.
     * @return The total accumulated XP.
     */
    function _calculateTotalXp(uint256 level, uint256 currentLevelXp) internal pure returns (uint256) {
        uint256 totalXp = currentLevelXp;
        for (uint256 i = 1; i < level; i++) {
            totalXp += xpToNextLevel(i);
        }
        return totalXp;
    }
    
    /**
     * @notice Allow owner to withdraw funds from the contract.
     */
    function withdraw() external onlyOwner {
        (bool success, ) = payable(owner()).call{value: address(this).balance}("");
        require(success, "Withdrawal failed");
    }
}
