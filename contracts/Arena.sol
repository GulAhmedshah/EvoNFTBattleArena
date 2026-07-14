// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title INftWithStats
 * @dev Interface for an NFT contract that includes retrievable stats and XP management.
 */
interface INftWithStats {
    struct NftStats {
        uint32 power;
        uint32 level;
        uint32 xp;
        uint8 element; // 0: None, 1: Fire, 2: Water, 3: Grass, 4: Light, 5: Dark
    }

    function getStats(uint256 tokenId) external view returns (NftStats memory);
    function gainXp(uint256 tokenId, uint32 xp) external;
}

/**
 * @title Arena
 * @author Your Name
 * @dev A contract for managing NFT battles, tournaments, and rewards.
 * This contract facilitates Player-vs-AI and Player-vs-Player battles with wagers,
 * as well as structured tournaments.
 */
contract Arena is Ownable, ReentrancyGuard {
    // --- Custom Errors ---
    error NotYourNFT();
    error InvalidWager();
    error BattleNotFound();
    error NotInvolvedInBattle();
    error BattleAlreadyResolved();
    error BattleNotReady();
    error TournamentNotFound();
    error TournamentNotActive();
    error AlreadyInTournament();
    error TournamentFull();
    error MatchNotFound();
    error NotInMatch();
    error MatchAlreadyResolved();

    // --- Structs ---
    struct Fighter {
        address owner;
        uint256 tokenId;
        uint32 power;
        uint32 level;
        uint8 element;
    }

    struct Battle {
        address challenger;
        address opponent; // Address(0) for AI
        uint256 challengerTokenId;
        uint256 opponentTokenId; // 0 for AI
        uint256 wagerAmount; // In reward tokens
        bool isResolved;
        address winner;
    }

    struct TournamentMatch {
        address player1;
        address player2;
        address winner;
    }

    struct Tournament {
        uint256 prizePool;
        uint16 capacity; // e.g., 8, 16, 32
        uint16 participantCount;
        bool isActive;
        bool isFinished;
        address[] participants;
        mapping(uint256 => TournamentMatch) matches; // round => match
    }

    // --- Enums ---
    enum Difficulty { Easy, Medium, Hard }

    // --- State Variables ---
    INftWithStats public nftWithStats;
    IERC721 public nftContract;
    IERC20 public rewardToken;

    uint256 public battleNonce;
    mapping(uint256 => Battle) public battles;

    uint256 public tournamentNonce;
    mapping(uint256 => Tournament) public tournaments;
    mapping(address => uint256) public playerActiveTournament;

    uint256 public constant ELEMENTAL_ADVANTAGE_BONUS = 20; // 20% bonus
    uint256 public constant XP_PER_WIN = 50;

    // --- Events ---
    event BattleCreated(uint256 indexed battleId, address indexed challenger, uint256 indexed challengerTokenId, Difficulty difficulty, uint256 wager);
    event BattleResolved(uint256 indexed battleId, address indexed winner, uint256 winnerTokenId, uint256 loserTokenId, uint256 reward, uint256 xpGained);
    event TournamentCreated(uint256 indexed tournamentId, uint16 capacity, uint256 entryFee);
    event PlayerEnteredTournament(uint256 indexed tournamentId, address indexed player, uint256 tokenId);
    event TournamentStarted(uint256 indexed tournamentId, uint256 prizePool);
    event MatchResolved(uint256 indexed tournamentId, uint256 round, uint256 matchIndex, address indexed winner);
    event TournamentFinished(uint256 indexed tournamentId, address indexed winner);

    // --- Constructor ---
    constructor(address _nftContract, address _nftWithStats, address _rewardToken) {
        nftContract = IERC721(_nftContract);
        nftWithStats = INftWithStats(_nftWithStats);
        rewardToken = IERC20(_rewardToken);
    }

    // --- AI Battle Functions ---

    /**
     * @notice Initiates a battle against an AI opponent.
     * @param challengerTokenId The ID of the user's NFT.
     * @param difficulty The desired difficulty of the AI opponent.
     * @param wagerAmount The amount of reward tokens to wager.
     */
    function battleAI(uint256 challengerTokenId, Difficulty difficulty, uint256 wagerAmount) external nonReentrant {
        if (nftContract.ownerOf(challengerTokenId) != msg.sender) revert NotYourNFT();
        if (wagerAmount > 0 && rewardToken.allowance(msg.sender, address(this)) < wagerAmount) revert InvalidWager();

        if (wagerAmount > 0) {
            rewardToken.transferFrom(msg.sender, address(this), wagerAmount);
        }

        battleNonce++;
        uint256 currentBattleId = battleNonce;

        battles[currentBattleId] = Battle({
            challenger: msg.sender,
            opponent: address(0), // AI battle
            challengerTokenId: challengerTokenId,
            opponentTokenId: 0,
            wagerAmount: wagerAmount,
            isResolved: false,
            winner: address(0)
        });

        emit BattleCreated(currentBattleId, msg.sender, challengerTokenId, difficulty, wagerAmount);

        _resolveAIBattle(currentBattleId, difficulty);
    }

    /**
     * @dev Internal function to resolve an AI battle immediately.
     * @param battleId The ID of the battle to resolve.
     * @param difficulty The AI difficulty.
     */
    function _resolveAIBattle(uint256 battleId, Difficulty difficulty) internal {
        Battle storage currentBattle = battles[battleId];
        
        INftWithStats.NftStats memory challengerStats = nftWithStats.getStats(currentBattle.challengerTokenId);
        Fighter memory challenger = Fighter(currentBattle.challenger, currentBattle.challengerTokenId, challengerStats.power, challengerStats.level, challengerStats.element);
        Fighter memory aiOpponent = _generateAIOpponent(difficulty, challenger.level);

        (address winner, address loser, uint256 winnerTokenId, uint256 loserTokenId) = _calculateBattleOutcome(challenger, aiOpponent);

        currentBattle.isResolved = true;
        currentBattle.winner = winner;

        uint256 reward = 0;
        uint256 xpGained = 0;

        if (winner == challenger.owner) {
            reward = currentBattle.wagerAmount * 2;
            xpGained = XP_PER_WIN + (uint256(difficulty) * 10);
            nftWithStats.gainXp(winnerTokenId, uint32(xpGained));
            if (reward > 0) {
                rewardToken.transfer(winner, reward);
            }
        } // If loser, the wager is kept by the contract (or a treasury).

        emit BattleResolved(battleId, winner, winnerTokenId, loserTokenId, reward, xpGained);
    }

    // --- Battle Logic ---

    /**
     * @dev Calculates the winner of a battle based on stats and pseudo-randomness.
     * On-chain randomness is susceptible to manipulation by miners. Use with caution.
     * @param fighter1 The first fighter.
     * @param fighter2 The second fighter.
     * @return winner The address of the winning owner.
     * @return loser The address of the losing owner.
     * @return winnerTokenId The ID of the winning token.
     * @return loserTokenId The ID of the losing token.
     */
    function _calculateBattleOutcome(Fighter memory fighter1, Fighter memory fighter2) 
        internal view 
        returns (address winner, address loser, uint256 winnerTokenId, uint256 loserTokenId)
    {
        uint256 score1 = (fighter1.power * fighter1.level) + _getElementalBonus(fighter1.element, fighter2.element);
        uint256 score2 = (fighter2.power * fighter2.level) + _getElementalBonus(fighter2.element, fighter1.element);
        
        // Pseudo-random factor
        uint256 randomFactor = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, fighter1.owner, fighter2.owner, battleNonce))) % 100;

        if (score1 * (100 + randomFactor / 5) >= score2 * (120 - randomFactor / 5)) {
            return (fighter1.owner, fighter2.owner, fighter1.tokenId, fighter2.tokenId);
        } else {
            return (fighter2.owner, fighter1.owner, fighter2.tokenId, fighter1.tokenId);
        }
    }

    /**
     * @dev Generates stats for an AI opponent based on difficulty and challenger level.
     * @param difficulty The difficulty setting.
     * @param challengerLevel The level of the player's NFT.
     * @return Fighter struct for the AI.
     */
    function _generateAIOpponent(Difficulty difficulty, uint32 challengerLevel) internal view returns (Fighter memory) {
        uint32 aiLevel = challengerLevel;
        uint32 aiPower;
        
        uint256 randomElement = uint256(keccak256(abi.encodePacked(block.timestamp, battleNonce))) % 5 + 1;

        if (difficulty == Difficulty.Easy) {
            aiLevel = (aiLevel * 90) / 100;
            aiPower = 8 * aiLevel;
        } else if (difficulty == Difficulty.Medium) {
            aiPower = 10 * aiLevel;
        } else { // Hard
            aiLevel = (aiLevel * 110) / 100;
            aiPower = 12 * aiLevel;
        }
        if (aiLevel == 0) aiLevel = 1;

        return Fighter(address(0), 0, aiPower, aiLevel, uint8(randomElement));
    }

    /**
     * @dev Calculates elemental advantage bonus percentage.
     * Fire > Grass, Grass > Water, Water > Fire. Light >< Dark.
     * @param attackerElement The element of the attacker.
     * @param defenderElement The element of the defender.
     * @return Bonus points to add to the score.
     */
    function _getElementalBonus(uint8 attackerElement, uint8 defenderElement) internal pure returns (uint256) {
        // 1: Fire, 2: Water, 3: Grass, 4: Light, 5: Dark
        if (
            (attackerElement == 1 && defenderElement == 3) || // Fire > Grass
            (attackerElement == 2 && defenderElement == 1) || // Water > Fire
            (attackerElement == 3 && defenderElement == 2) || // Grass > Water
            (attackerElement == 4 && defenderElement == 5) || // Light > Dark
            (attackerElement == 5 && defenderElement == 4)    // Dark > Light
        ) {
            return ELEMENTAL_ADVANTAGE_BONUS;
        }
        return 0;
    }

    // --- View Functions ---

    /**
     * @notice Gets the details of a specific battle.
     * @param battleId The ID of the battle.
     * @return Battle struct.
     */
    function getBattleDetails(uint256 battleId) external view returns (Battle memory) {
        return battles[battleId];
    }

    // --- Admin Functions ---

    /**
     * @notice Updates the NFT contract address.
     * @param _newAddress The new contract address.
     */
    function setNftContract(address _newAddress) external onlyOwner {
        nftContract = IERC721(_newAddress);
    }

    /**
     * @notice Updates the NFT stats contract address.
     * @param _newAddress The new contract address.
     */
    function setNftWithStats(address _newAddress) external onlyOwner {
        nftWithStats = INftWithStats(_newAddress);
    }

    /**
     * @notice Updates the reward token contract address.
     * @param _newAddress The new contract address.
     */
    function setRewardToken(address _newAddress) external onlyOwner {
        rewardToken = IERC20(_newAddress);
    }

    /**
     * @notice Withdraws stuck ERC20 tokens from the contract.
     * @param tokenAddress The address of the ERC20 token to withdraw.
     */
    function withdrawStuckTokens(address tokenAddress) external onlyOwner {
        IERC20 token = IERC20(tokenAddress);
        uint256 balance = token.balanceOf(address(this));
        token.transfer(owner(), balance);
    }
}