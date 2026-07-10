// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title NFTStaking
 * @author Your Name
 * @notice A contract for staking NFTs and earning rewards. This version introduces NFT evolution.
 * This contract assumes it is the central point of logic for NFT stats and staking.
 */
contract NFTStaking is Ownable, Pausable, ReentrancyGuard, ERC721Holder {
    // =============================================================
    //                           Enums
    // =============================================================

    /**
     * @dev Represents the elemental type of an NFT.
     */
    enum ElementType { Fire, Water, Earth, Wind, Light, Dark, Neutral }

    /**
     * @dev Represents the visual and stat-cap tier of an NFT.
     */
    enum EvolutionTier { Basic, Evolved, Ultimate, Legendary }

    /**
     * @dev Represents the chosen path for an NFT's evolution, affecting stat growth.
     */
    enum EvolutionPath { Strength, Defense, Balanced }

    // =============================================================
    //                           Structs
    // =============================================================

    /**
     * @dev Holds all gameplay-related stats for a specific NFT.
     * @param level The current level of the NFT.
     * @param strength Affects physical attack power.
     * @param defense Reduces damage from physical attacks.
     * @param speed Determines turn order and dodge chance.
     * @param intelligence Affects magical attack power and defense.
     * @param experience Current XP, used for leveling up.
     * @param battleCount Total number of battles fought.
     * @param wins Total number of battles won.
     * @param isEvolved Flag indicating if the NFT has undergone evolution.
     * @param evolutionTimestamp The timestamp of the last evolution.
     * @param evolutionTier The current evolution tier of the NFT.
     * @param elementType The elemental affinity of the NFT.
     */
    struct NFTStats {
        uint32 level;
        uint32 strength;
        uint32 defense;
        uint32 speed;
        uint32 intelligence;
        uint32 experience;
        uint32 battleCount;
        uint32 wins;
        bool isEvolved;
        uint256 evolutionTimestamp;
        EvolutionTier evolutionTier;
        ElementType elementType;
    }
    
    /**
     * @dev Stores information about a staked NFT.
     * @param owner The address of the staker.
     * @param stakedTimestamp The time the NFT was staked.
     */
    struct StakedNFT {
        address owner;
        uint256 stakedTimestamp;
    }

    /**
     * @dev A struct to preview the outcome of an evolution path.
     * @param path The evolution path.
     * @param newStrength The resulting strength stat.
     * @param newDefense The resulting defense stat.
     * @param newSpeed The resulting speed stat.
     * @param newIntelligence The resulting intelligence stat.
     */
    struct EvolutionPreview {
        EvolutionPath path;
        uint32 newStrength;
        uint32 newDefense;
        uint32 newSpeed;
        uint32 newIntelligence;
    }

    // =============================================================
    //                      State Variables
    // =============================================================

    IERC721 public immutable nftCollection;
    uint256 public evolutionFee;

    uint32 private constant MAX_STAT_VALUE_BASIC = 500;
    uint32 private constant MAX_STAT_VALUE_EVOLVED = 750;

    mapping(uint256 => StakedNFT) private _stakedNFTs;
    mapping(uint256 => NFTStats) private _nftStats;
    
    // =============================================================
    //                           Events
    // =============================================================

    event Staked(address indexed owner, uint256 indexed tokenId, uint256 timestamp);
    event Unstaked(address indexed owner, uint256 indexed tokenId, uint256 timestamp);
    event EvolutionFeeUpdated(uint256 oldFee, uint256 newFee);
    event NFTEvolved(
        uint256 indexed tokenId,
        address indexed owner,
        EvolutionPath path,
        uint32 newStrength,
        uint32 newDefense,
        uint32 newSpeed,
        uint32 newIntelligence
    );

    // =============================================================
    //                         Constructor
    // =============================================================

    /**
     * @dev Sets up the contract with the NFT collection address and initial evolution fee.
     * @param _nftCollectionAddress The address of the ERC721 token contract.
     * @param _initialEvolutionFee The initial fee required for an NFT to evolve.
     */
    constructor(address _nftCollectionAddress, uint256 _initialEvolutionFee) {
        require(_nftCollectionAddress != address(0), "NFT address cannot be zero");
        nftCollection = IERC721(_nftCollectionAddress);
        evolutionFee = _initialEvolutionFee;
    }

    // =============================================================
    //                   Staking/Unstaking Logic
    // =============================================================

    /**
     * @notice Stakes an NFT in the contract.
     * @dev The user must approve the contract to manage their NFT first.
     * @param tokenId The ID of the NFT to stake.
     */
    function stake(uint256 tokenId) external whenNotPaused nonReentrant {
        require(nftCollection.ownerOf(tokenId) == msg.sender, "Not owner of token");
        require(!_isStaked(tokenId), "Token already staked");

        // Initialize stats if this is the first interaction
        if (_nftStats[tokenId].level == 0) {
            _initializeNFTStats(tokenId);
        }

        _stakedNFTs[tokenId] = StakedNFT({
            owner: msg.sender,
            stakedTimestamp: block.timestamp
        });
        
        nftCollection.safeTransferFrom(msg.sender, address(this), tokenId);
        
        emit Staked(msg.sender, tokenId, block.timestamp);
    }

    /**
     * @notice Unstakes an NFT from the contract.
     * @param tokenId The ID of the NFT to unstake.
     */
    function unstake(uint256 tokenId) external whenNotPaused nonReentrant {
        require(_stakedNFTs[tokenId].owner == msg.sender, "Not staker of token");
        
        delete _stakedNFTs[tokenId];
        
        nftCollection.safeTransferFrom(address(this), msg.sender, tokenId);

        emit Unstaked(msg.sender, tokenId, block.timestamp);
    }

    // =============================================================
    //                      Evolution Logic
    // =============================================================

    /**
     * @notice Evolves an NFT, increasing its stats and capabilities.
     * @dev The NFT must meet specific criteria (level, battles, wins) and not be staked.
     * The caller must pay the `evolutionFee`.
     * @param tokenId The ID of the NFT to evolve.
     * @param path The desired evolution path (Strength, Defense, or Balanced).
     */
    function evolveNFT(uint256 tokenId, EvolutionPath path) external payable whenNotPaused nonReentrant {
        // 1. Requirement Checks
        require(nftCollection.ownerOf(tokenId) == msg.sender, "Not token owner");
        require(!_isStaked(tokenId), "Token is staked and locked");

        NFTStats storage stats = _nftStats[tokenId];
        
        require(stats.level >= 30, "Evolution requires level 30+");
        require(stats.battleCount >= 50, "Evolution requires 50+ battles");
        require(stats.wins >= 25, "Evolution requires 25+ wins");
        require(!stats.isEvolved, "NFT has already evolved");
        require(msg.value >= evolutionFee, "Insufficient evolution fee");
        
        // 2. Fee Handling
        if (msg.value > evolutionFee) {
            payable(msg.sender).transfer(msg.value - evolutionFee);
        }

        // 3. Evolution Process
        stats.isEvolved = true;
        stats.evolutionTimestamp = block.timestamp;

        _updateEvolutionTier(stats);

        (uint32 newStrength, uint32 newDefense, uint32 newSpeed, uint32 newIntelligence) = _calculateEvolvedStats(stats, path);

        uint32 maxStat = _getMaxStatCap(stats.evolutionTier);
        stats.strength = _min(newStrength, maxStat);
        stats.defense = _min(newDefense, maxStat);
        stats.speed = _min(newSpeed, maxStat);
        stats.intelligence = _min(newIntelligence, maxStat);
        
        // 4. Emit Event
        emit NFTEvolved(
            tokenId,
            msg.sender,
            path,
            stats.strength,
            stats.defense,
            stats.speed,
            stats.intelligence
        );
    }

    /**
     * @notice Sets a new fee for NFT evolution.
     * @dev Only the contract owner can call this function.
     * @param _newFee The new evolution fee in wei.
     */
    function setEvolutionFee(uint256 _newFee) external onlyOwner {
        emit EvolutionFeeUpdated(evolutionFee, _newFee);
        evolutionFee = _newFee;
    }
    
    /**
     * @notice Allows the owner to withdraw collected fees.
     */
    function withdrawFees() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");
        (bool success, ) = owner().call{value: balance}("");
        require(success, "Withdrawal failed");
    }

    // =============================================================
    //                       View Functions
    // =============================================================

    /**
     * @notice Retrieves the stats of a specific NFT.
     * @param tokenId The ID of the NFT.
     * @return A struct containing the NFT's stats.
     */
    function getNFTStats(uint256 tokenId) external view returns (NFTStats memory) {
        return _nftStats[tokenId];
    }
    
    /**
     * @notice Retrieves staking information for a specific NFT.
     * @param tokenId The ID of the NFT.
     * @return A struct containing the NFT's staking info.
     */
    function getStakedInfo(uint256 tokenId) external view returns (StakedNFT memory) {
        return _stakedNFTs[tokenId];
    }

    /**
     * @notice Checks if an NFT is currently staked.
     * @param tokenId The ID of the NFT.
     * @return True if the NFT is staked, false otherwise.
     */
    function _isStaked(uint256 tokenId) internal view returns (bool) {
        return _stakedNFTs[tokenId].owner != address(0);
    }
    
    /**
     * @notice Previews the potential stat outcomes for all available evolution paths for an NFT.
     * @dev Returns an array of empty structs if the NFT is not eligible for evolution.
     * @param tokenId The ID of the NFT to preview.
     * @return An array of three EvolutionPreview structs, one for each path.
     */
    function getEvolutionPaths(uint256 tokenId) external view returns (EvolutionPreview[3] memory) {
        NFTStats memory stats = _nftStats[tokenId];
        EvolutionPreview[3] memory previews;

        if (stats.level < 30 || stats.battleCount < 50 || stats.wins < 25 || stats.isEvolved) {
            return previews; // Return empty array if not eligible
        }

        uint32 maxStat = _getMaxStatCap(EvolutionTier.Evolved);

        // Strength Path
        (uint32 sS, uint32 dS, uint32 spS, uint32 iS) = _calculateEvolvedStats(stats, EvolutionPath.Strength);
        previews[0] = EvolutionPreview(EvolutionPath.Strength, _min(sS, maxStat), _min(dS, maxStat), _min(spS, maxStat), _min(iS, maxStat));

        // Defense Path
        (uint32 sD, uint32 dD, uint32 spD, uint32 iD) = _calculateEvolvedStats(stats, EvolutionPath.Defense);
        previews[1] = EvolutionPreview(EvolutionPath.Defense, _min(sD, maxStat), _min(dD, maxStat), _min(spD, maxStat), _min(iD, maxStat));

        // Balanced Path
        (uint32 sB, uint32 dB, uint32 spB, uint32 iB) = _calculateEvolvedStats(stats, EvolutionPath.Balanced);
        previews[2] = EvolutionPreview(EvolutionPath.Balanced, _min(sB, maxStat), _min(dB, maxStat), _min(spB, maxStat), _min(iB, maxStat));

        return previews;
    }


    // =============================================================
    //                     Internal Helpers
    // =============================================================

    /**
     * @dev Initializes the stats for a newly interacted NFT.
     * @param tokenId The ID of the NFT.
     */
    function _initializeNFTStats(uint256 tokenId) internal {
        _nftStats[tokenId] = NFTStats({
            level: 1,
            strength: 10,
            defense: 10,
            speed: 10,
            intelligence: 10,
            experience: 0,
            battleCount: 0,
            wins: 0,
            isEvolved: false,
            evolutionTimestamp: 0,
            evolutionTier: EvolutionTier.Basic,
            elementType: ElementType.Neutral
        });
    }

    /**
     * @dev Updates an NFT's evolution tier based on its level.
     * @param stats The storage pointer to the NFT's stats.
     */
    function _updateEvolutionTier(NFTStats storage stats) internal {
        uint32 level = stats.level;
        if (level >= 90) {
            stats.evolutionTier = EvolutionTier.Legendary;
        } else if (level >= 60) {
            stats.evolutionTier = EvolutionTier.Ultimate;
        } else if (level >= 30) {
            stats.evolutionTier = EvolutionTier.Evolved;
        } else {
            stats.evolutionTier = EvolutionTier.Basic;
        }
    }

    /**
     * @dev Calculates the new stats for an NFT based on a chosen evolution path.
     * @param stats The current stats of the NFT.
     * @param path The chosen evolution path.
     * @return A tuple containing the new (strength, defense, speed, intelligence).
     */
    function _calculateEvolvedStats(
        NFTStats memory stats, 
        EvolutionPath path
    ) internal pure returns (uint32, uint32, uint32, uint32) {
        // Base 20% increase for all stats
        uint32 strengthBoost = (stats.strength * 20) / 100;
        uint32 defenseBoost = (stats.defense * 20) / 100;
        uint32 speedBoost = (stats.speed * 20) / 100;
        uint32 intelligenceBoost = (stats.intelligence * 20) / 100;

        // Path-specific bonus
        if (path == EvolutionPath.Strength) {
            strengthBoost += (stats.strength * 10) / 100;
            speedBoost += (stats.speed * 10) / 100;
        } else if (path == EvolutionPath.Defense) {
            defenseBoost += (stats.defense * 10) / 100;
            intelligenceBoost += (stats.intelligence * 10) / 100;
        } else { // Balanced path
            strengthBoost += (stats.strength * 5) / 100;
            defenseBoost += (stats.defense * 5) / 100;
            speedBoost += (stats.speed * 5) / 100;
            intelligenceBoost += (stats.intelligence * 5) / 100;
        }
        
        return (
            stats.strength + strengthBoost,
            stats.defense + defenseBoost,
            stats.speed + speedBoost,
            stats.intelligence + intelligenceBoost
        );
    }
    
    /**
     * @dev Returns the maximum stat value based on the evolution tier.
     * The logic for Ultimate and Legendary can be expanded.
     */
    function _getMaxStatCap(EvolutionTier tier) internal pure returns (uint32) {
        if (tier == EvolutionTier.Evolved) {
            return MAX_STAT_VALUE_EVOLVED;
        }
        // Add more tiers later
        // if (tier == EvolutionTier.Ultimate) return 1000;
        // if (tier == EvolutionTier.Legendary) return 1500;
        return MAX_STAT_VALUE_BASIC;
    }

    /**
     * @dev Returns the smaller of two uint32 values.
     */
    function _min(uint32 a, uint32 b) internal pure returns (uint32) {
        return a < b ? a : b;
    }
}
