// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title ICharacterNFT
 * @dev Interface for the main NFT contract.
 * Assumes the NFT contract has an `ownerOf` function and a way to update
 * the token URI, restricted to an authorized address (this contract).
 */
interface ICharacterNFT {
    function ownerOf(uint256 tokenId) external view returns (address);
    function setTokenURI(uint256 tokenId, string memory tokenURI) external;
}

/**
 * @title CharacterMechanics
 * @author [Your Name]
 * @dev Manages the game mechanics for NFT characters, including training, leveling up, and evolution.
 * This contract is designed to be the central logic hub for character progression, interacting with
 * an NFT contract and a reward token contract.
 */
contract CharacterMechanics is Ownable, ReentrancyGuard {
    // --- STRUCTS ---

    /**
     * @dev Holds all gameplay-related stats for a character NFT.
     */
    struct CharacterStats {
        uint256 level;
        uint256 experience;
        uint32 evolutionTier;
        // Base stats can be expanded (e.g., attack, defense, speed)
        uint256 power;
        uint256 wins;
        uint256 battles;
    }

    /**
     * @dev Defines a possible evolution path for a character.
     */
    struct EvolutionPath {
        uint256 requiredLevel;
        uint256 cost; // Cost in reward tokens
        uint32 nextEvolutionTier;
        string newUri; // The new metadata URI for the evolved form
        uint256 powerBonus;
    }

    // --- ERRORS ---

    error NotNFTOwner();
    error AlreadyRegistered();
    error NotRegistered();
    error CooldownActive(uint256 timeLeft);
    error InsufficientLevel(uint256 current, uint256 required);
    error InsufficientFunds(uint256 current, uint256 required);
    error InvalidEvolutionPath();
    error ZeroAddress();

    // --- STATE VARIABLES ---

    ICharacterNFT public nftContract;
    IERC20 public rewardToken;

    mapping(uint256 => CharacterStats) public characterStats;
    mapping(uint256 => uint256) public nextTrainTime;
    mapping(uint32 => EvolutionPath[]) public evolutionPaths;

    uint256 public trainingCooldown = 30 minutes;
    uint256 public baseTrainingExp = 10;

    // Experience required to reach the next level. Index `i` is exp for level `i+1`.
    uint256[] public expToLevelUp;

    // --- EVENTS ---

    event CharacterRegistered(uint256 indexed tokenId);
    event CharacterTrained(uint256 indexed tokenId, uint256 expGained, uint256 newTotalExp);
    event CharacterLeveledUp(uint256 indexed tokenId, uint256 newLevel, uint256 newPower);
    event CharacterEvolved(
        uint256 indexed tokenId,
        uint32 fromTier,
        uint32 toTier,
        uint256 newPower
    );

    // --- CONSTRUCTOR ---

    /**
     * @dev Sets up the contract with dependent contract addresses.
     * @param _nftAddress The address of the main character NFT contract.
     * @param _rewardTokenAddress The address of the ERC20 reward token.
     */
    constructor(address _nftAddress, address _rewardTokenAddress) {
        if (_nftAddress == address(0) || _rewardTokenAddress == address(0)) {
            revert ZeroAddress();
        }
        nftContract = ICharacterNFT(_nftAddress);
        rewardToken = IERC20(_rewardTokenAddress);

        // Initialize an example experience curve for levels 2-10
        expToLevelUp = [100, 250, 450, 700, 1000, 1350, 1750, 2200, 2700];
    }

    // --- PUBLIC & EXTERNAL FUNCTIONS ---

    /**
     * @notice Registers a new NFT in the system, initializing its stats.
     * @dev Can only be called once per NFT, by the NFT's owner.
     * @param tokenId The ID of the NFT to register.
     */
    function registerCharacter(uint256 tokenId) external {
        if (msg.sender != nftContract.ownerOf(tokenId)) revert NotNFTOwner();
        if (characterStats[tokenId].level > 0) revert AlreadyRegistered();

        characterStats[tokenId] = CharacterStats({
            level: 1,
            experience: 0,
            evolutionTier: 1,
            power: 10, // Initial base power
            wins: 0,
            battles: 0
        });

        emit CharacterRegistered(tokenId);
    }

    /**
     * @notice Train a character to gain experience.
     * @dev Subject to a cooldown. Can only be called by the NFT's owner.
     * @param tokenId The ID of the NFT to train.
     */
    function train(uint256 tokenId) external nonReentrant {
        if (msg.sender != nftContract.ownerOf(tokenId)) revert NotNFTOwner();
        if (characterStats[tokenId].level == 0) revert NotRegistered();
        if (block.timestamp < nextTrainTime[tokenId]) {
            revert CooldownActive(nextTrainTime[tokenId] - block.timestamp);
        }

        nextTrainTime[tokenId] = block.timestamp + trainingCooldown;

        CharacterStats storage stats = characterStats[tokenId];
        stats.experience += baseTrainingExp;

        emit CharacterTrained(tokenId, baseTrainingExp, stats.experience);

        _checkForLevelUp(tokenId);
    }

    /**
     * @notice Evolve a character to its next tier.
     * @dev Requires the character to meet level and cost requirements.
     * @param tokenId The ID of the NFT to evolve.
     * @param evolutionChoiceIndex The index of the chosen evolution path.
     */
    function evolve(uint256 tokenId, uint256 evolutionChoiceIndex) external nonReentrant {
        if (msg.sender != nftContract.ownerOf(tokenId)) revert NotNFTOwner();

        CharacterStats storage stats = characterStats[tokenId];
        if (stats.level == 0) revert NotRegistered();

        EvolutionPath[] storage paths = evolutionPaths[stats.evolutionTier];
        if (evolutionChoiceIndex >= paths.length) revert InvalidEvolutionPath();

        EvolutionPath storage path = paths[evolutionChoiceIndex];

        if (stats.level < path.requiredLevel) {
            revert InsufficientLevel(stats.level, path.requiredLevel);
        }

        if (path.cost > 0) {
            uint256 allowance = rewardToken.allowance(msg.sender, address(this));
            if (allowance < path.cost) revert InsufficientFunds(allowance, path.cost);
            rewardToken.transferFrom(msg.sender, address(this), path.cost);
        }

        uint32 fromTier = stats.evolutionTier;
        stats.evolutionTier = path.nextEvolutionTier;
        stats.power += path.powerBonus;
        
        // This contract must be authorized to call setTokenURI on the NFT contract
        nftContract.setTokenURI(tokenId, path.newUri);

        emit CharacterEvolved(tokenId, fromTier, stats.evolutionTier, stats.power);
    }

    // --- INTERNAL FUNCTIONS ---

    /**
     * @dev Checks if a character has enough experience to level up and processes it.
     * @param tokenId The ID of the character to check.
     */
    function _checkForLevelUp(uint256 tokenId) internal {
        CharacterStats storage stats = characterStats[tokenId];
        uint256 currentLevel = stats.level;
        uint256 expForNext = getExpForLevel(currentLevel);

        if (expForNext > 0 && stats.experience >= expForNext) {
            stats.level++;
            stats.experience -= expForNext;
            // Example: Increase power by 5 on level up
            stats.power += 5;

            emit CharacterLeveledUp(tokenId, stats.level, stats.power);

            // Recursive check in case of multiple level-ups from one training
            _checkForLevelUp(tokenId);
        }
    }

    // --- VIEW FUNCTIONS ---

    /**
     * @notice Gets the experience required to advance from a given level.
     * @param level The current level.
     * @return The experience required for the next level. Returns 0 if max level reached.
     */
    function getExpForLevel(uint256 level) public view returns (uint256) {
        if (level == 0 || level > expToLevelUp.length) {
            return 0;
        }
        return expToLevelUp[level - 1];
    }

    /**
     * @notice Returns all available evolution options for a character's current tier.
     * @param tokenId The ID of the character.
     * @return An array of `EvolutionPath` structs.
     */
    function getEvolutionOptions(uint256 tokenId) external view returns (EvolutionPath[] memory) {
        return evolutionPaths[characterStats[tokenId].evolutionTier];
    }

    // --- ADMIN FUNCTIONS ---

    /**
     * @notice Adds a new evolution path.
     * @param fromTier The evolution tier this path starts from.
     * @param path The `EvolutionPath` struct to add.
     */
    function addEvolutionPath(uint32 fromTier, EvolutionPath calldata path) external onlyOwner {
        evolutionPaths[fromTier].push(path);
    }

    /**
     * @notice Updates an existing evolution path.
     * @param fromTier The evolution tier this path starts from.
     * @param index The index of the path to update.
     * @param path The new `EvolutionPath` struct.
     */
    function updateEvolutionPath(uint32 fromTier, uint256 index, EvolutionPath calldata path) external onlyOwner {
        if (index >= evolutionPaths[fromTier].length) revert InvalidEvolutionPath();
        evolutionPaths[fromTier][index] = path;
    }

    /**
     * @notice Sets the experience curve for leveling up.
     * @param _expRequirements Array where index `i` is exp for level `i+1`.
     */
    function setExpCurve(uint256[] calldata _expRequirements) external onlyOwner {
        expToLevelUp = _expRequirements;
    }

    function setTrainingCooldown(uint256 _cooldown) external onlyOwner {
        trainingCooldown = _cooldown;
    }

    function setBaseTrainingExp(uint256 _exp) external onlyOwner {
        baseTrainingExp = _exp;
    }

    function setNftContract(address _address) external onlyOwner {
        if (_address == address(0)) revert ZeroAddress();
        nftContract = ICharacterNFT(_address);
    }

    function setRewardToken(address _address) external onlyOwner {
        if (_address == address(0)) revert ZeroAddress();
        rewardToken = IERC20(_address);
    }

    /**
     * @notice Allows owner to withdraw any ERC20 tokens sent to this contract.
     */
    function withdrawTokens(address tokenAddress, address to, uint256 amount) external onlyOwner {
        IERC20 token = IERC20(tokenAddress);
        token.transfer(to, amount);
    }
}