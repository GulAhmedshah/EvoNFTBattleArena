// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title Tournament
 * @author Your Name
 * @notice Day 7: Implements an advanced tournament system for a parent NFT staking platform.
 * @dev This contract manages 4-participant tournaments, battle replays, spectator rewards, battle streaks, and a leaderboard.
 *      It is designed to be part of a larger system and assumes StakedNFT data is available and managed externally.
 */
contract Tournament is Ownable {
    using SafeERC20 for IERC20;
    using Counters for Counters.Counter;

    // --- STRUCTS ---

    /// @notice Represents a staked NFT with its core attributes for battling. Assumed to be populated by a parent contract.
    struct StakedNFT {
        address owner;
        uint256 stakeTime;
        uint256 level;
        uint256 xp;
        uint256 attack;
        uint256 defense;
    }

    /// @notice Stores battle statistics for each NFT.
    struct NFTBattleStats {
        uint256 wins;
        uint256 losses;
        uint256 winStreak;
    }

    /// @notice Represents a single head-to-head battle.
    struct Battle {
        uint256 nft1;
        uint256 nft2;
        uint256 winner;
        uint256 loser;
        bytes[] replay; // Stores sequence of moves/actions for replay
    }

    /// @notice Defines the status of a tournament.
    enum TournamentStatus { Created, InProgress, Finished }

    /// @notice Represents a 4-participant tournament.
    struct TournamentData {
        address creator;
        uint256[4] participants;
        uint256 entryFeePool;
        TournamentStatus status;
        uint256 winner;
        uint256 runnerUp;
        uint256 battleIdRound1_1;
        uint256 battleIdRound1_2;
        uint256 battleIdFinal;
    }

    /// @notice Represents an entry on the leaderboard.
    struct LeaderboardEntry {
        uint256 tokenId;
        uint256 score;
    }

    // --- STATE VARIABLES ---

    IERC721 public immutable nftContract;
    IERC20 public immutable feeToken;

    Counters.Counter private _tournamentIds;
    Counters.Counter private _battleIds;

    mapping(uint256 => StakedNFT) public stakedNfts;
    mapping(uint256 => bool) public isStaked;
    mapping(uint256 => NFTBattleStats) public nftStats;
    mapping(uint256 => TournamentData) public tournaments;
    mapping(uint256 => Battle) public battles;
    mapping(address => uint256) public userXP;
    mapping(address => mapping(uint256 => bool)) private _hasWatchedBattle;

    uint256 public constant LEADERBOARD_SIZE = 100;
    LeaderboardEntry[LEADERBOARD_SIZE] public leaderboard;
    uint256 private _minLeaderboardScore;
    uint8 private _minLeaderboardScoreIndex;

    uint256 public constant SPECTATOR_XP = 10;
    uint256 public constant WINNER_REWARD_PERCENT = 80;

    // --- EVENTS ---

    event TournamentCreated(uint256 indexed tournamentId, address indexed creator, uint256[4] participants, uint256 totalEntryFee);
    event TournamentBattleStarted(uint256 indexed tournamentId);
    event TournamentFinished(uint256 indexed tournamentId, uint256 winner, uint256 runnerUp);
    event BattleExecuted(uint256 indexed battleId, uint256 indexed tournamentId, uint256 winner, uint256 loser);
    event BattleWatched(address indexed spectator, uint256 indexed battleId, uint256 xpGained);
    event WinStreakBonus(uint256 indexed tokenId, uint256 newStreak, uint256 xpBonus);
    event LeaderboardUpdated(uint256 indexed tokenId, uint256 newScore);

    // --- CONSTRUCTOR ---

    constructor(address _nftAddress, address _feeTokenAddress) {
        nftContract = IERC721(_nftAddress);
        feeToken = IERC20(_feeTokenAddress);
    }

    // --- PUBLIC & EXTERNAL FUNCTIONS ---

    /**
     * @notice Creates a new 4-participant tournament.
     * @dev The caller must own and have staked all four participating NFTs.
     *      They must also approve this contract to spend the required entry fee tokens.
     * @param _tokenIds An array of 4 unique token IDs to participate.
     * @param _entryFeePerNft The entry fee in feeToken units for each NFT.
     */
    function createTournament(uint256[4] calldata _tokenIds, uint256 _entryFeePerNft) external {
        uint256 totalFee = _entryFeePerNft * 4;
        require(totalFee == 0 || totalFee / 4 == _entryFeePerNft, "Tournament: Fee overflow");

        for (uint i = 0; i < 4; i++) {
            require(isStaked[_tokenIds[i]], "Tournament: A token is not staked");
            require(stakedNfts[_tokenIds[i]].owner == msg.sender, "Tournament: Not owner of all tokens");
            for (uint j = i + 1; j < 4; j++) {
                require(_tokenIds[i] != _tokenIds[j], "Tournament: Duplicate token IDs");
            }
        }
        
        if (totalFee > 0) {
            feeToken.safeTransferFrom(msg.sender, address(this), totalFee);
        }
        
        _tournamentIds.increment();
        uint256 tournamentId = _tournamentIds.current();

        tournaments[tournamentId] = TournamentData({
            creator: msg.sender,
            participants: _tokenIds,
            entryFeePool: totalFee,
            status: TournamentStatus.Created,
            winner: 0,
            runnerUp: 0,
            battleIdRound1_1: 0,
            battleIdRound1_2: 0,
            battleIdFinal: 0
        });

        emit TournamentCreated(tournamentId, msg.sender, _tokenIds, totalFee);
    }

    /**
     * @notice Initiates and completes a full tournament battle for a given tournament ID.
     * @dev Executes Round 1 and the Final Round, distributes rewards, and updates stats.
     *      Only the tournament creator can start the battle.
     * @param _tournamentId The ID of the tournament to battle.
     */
    function tournamentBattle(uint256 _tournamentId) external {
        TournamentData storage t = tournaments[_tournamentId];

        require(t.creator != address(0), "Tournament: Not found");
        require(t.creator == msg.sender, "Tournament: Only creator can start");
        require(t.status == TournamentStatus.Created, "Tournament: Already started or finished");

        t.status = TournamentStatus.InProgress;
        emit TournamentBattleStarted(_tournamentId);

        (uint256 winner1, , uint256 battleId1) = _executeBattle(_tournamentId, t.participants[0], t.participants[1]);
        t.battleIdRound1_1 = battleId1;

        (uint256 winner2, , uint256 battleId2) = _executeBattle(_tournamentId, t.participants[2], t.participants[3]);
        t.battleIdRound1_2 = battleId2;

        (uint256 finalWinner, uint256 finalLoser, uint256 battleIdFinal) = _executeBattle(_tournamentId, winner1, winner2);
        t.battleIdFinal = battleIdFinal;

        t.winner = finalWinner;
        t.runnerUp = finalLoser;
        t.status = TournamentStatus.Finished;

        if (t.entryFeePool > 0) {
            uint256 winnerReward = (t.entryFeePool * WINNER_REWARD_PERCENT) / 100;
            uint256 runnerUpReward = t.entryFeePool - winnerReward;

            feeToken.safeTransfer(stakedNfts[finalWinner].owner, winnerReward);
            feeToken.safeTransfer(stakedNfts[finalLoser].owner, runnerUpReward);
        }
        
        emit TournamentFinished(_tournamentId, t.winner, t.runnerUp);
    }

    /**
     * @notice Allows a user to "watch" a completed battle to earn XP.
     * @dev Can only be done once per battle per user.
     * @param _battleId The ID of the battle to watch.
     */
    function watchBattle(uint256 _battleId) external {
        require(_battleId > 0 && _battleId <= _battleIds.current(), "Watch: Invalid battle ID");
        require(!_hasWatchedBattle[msg.sender][_battleId], "Watch: Already watched");
        require(battles[_battleId].winner != 0, "Watch: Battle not completed");

        _hasWatchedBattle[msg.sender][_battleId] = true;
        userXP[msg.sender] += SPECTATOR_XP;

        emit BattleWatched(msg.sender, _battleId, SPECTATOR_XP);
    }

    // --- VIEW FUNCTIONS ---

    /**
     * @notice Retrieves the replay data for a specific battle.
     * @param _battleId The ID of the battle.
     * @return An array of bytes, where each element is a "move" in the battle.
     */
    function getBattleReplay(uint256 _battleId) external view returns (bytes[] memory) {
        require(_battleId > 0 && _battleId <= _battleIds.current(), "Replay: Invalid battle ID");
        return battles[_battleId].replay;
    }

    /**
     * @notice Returns the top 100 leaderboard entries.
     * @dev The returned array is not guaranteed to be sorted by score.
     * @return The array of leaderboard entries.
     */
    function getLeaderboard() external view returns (LeaderboardEntry[LEADERBOARD_SIZE] memory) {
        return leaderboard;
    }

    // --- INTERNAL FUNCTIONS ---

    function _executeBattle(uint256 _tournamentId, uint256 _tokenId1, uint256 _tokenId2)
        internal
        returns (uint256 winner, uint256 loser, uint256 battleId)
    {
        _battleIds.increment();
        battleId = _battleIds.current();
        
        Battle storage b = battles[battleId];
        b.nft1 = _tokenId1;
        b.nft2 = _tokenId2;

        StakedNFT memory nft1 = stakedNfts[_tokenId1];
        StakedNFT memory nft2 = stakedNfts[_tokenId2];

        uint8 score1 = 0;
        bytes[] memory replay = new bytes[](5);

        for (uint8 i = 0; i < 5; i++) {
            uint256 rand = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, _tokenId1, _tokenId2, i)));
            
            uint256 power1 = nft1.attack + (rand % 50);
            uint256 power2 = nft2.defense + ((rand >> 8) % 50);
            
            if (power1 >= power2) {
                score1++;
                replay[i] = abi.encodePacked(uint8(1), power1, power2);
            } else {
                replay[i] = abi.encodePacked(uint8(2), power1, power2);
            }
        }
        b.replay = replay;

        if (score1 >= 3) {
            winner = _tokenId1;
            loser = _tokenId2;
        } else {
            winner = _tokenId2;
            loser = _tokenId1;
        }

        b.winner = winner;
        b.loser = loser;

        _updateStatsAndStreaks(winner, loser);
        _updateLeaderboard(winner);
        _updateLeaderboard(loser);
        
        emit BattleExecuted(battleId, _tournamentId, winner, loser);
    }
    
    function _updateStatsAndStreaks(uint256 _winnerId, uint256 _loserId) internal {
        nftStats[_winnerId].wins++;
        nftStats[_winnerId].winStreak++;
        stakedNfts[_winnerId].xp += 100;

        uint256 streak = nftStats[_winnerId].winStreak;
        if (streak == 5 || streak == 10 || streak == 25) {
            uint256 bonusXp = streak * 100;
            stakedNfts[_winnerId].xp += bonusXp;
            emit WinStreakBonus(_winnerId, streak, bonusXp);
        }

        nftStats[_loserId].losses++;
        nftStats[_loserId].winStreak = 0;
        stakedNfts[_loserId].xp += 25;
    }

    function _calculateScore(uint256 _tokenId) internal view returns (uint256) {
        NFTBattleStats storage stats = nftStats[_tokenId];
        uint256 totalBattles = stats.wins + stats.losses;
        if (totalBattles == 0) return 0;
        return (stats.wins * 10000) / totalBattles + totalBattles;
    }
    
    function _updateLeaderboard(uint256 _tokenId) internal {
        uint256 newScore = _calculateScore(_tokenId);

        for (uint8 i = 0; i < LEADERBOARD_SIZE; i++) {
            if (leaderboard[i].tokenId == _tokenId) {
                leaderboard[i].score = newScore;
                if (i == _minLeaderboardScoreIndex) {
                     _refindMinLeaderboardScore();
                } else if (newScore < _minLeaderboardScore) {
                    _minLeaderboardScore = newScore;
                    _minLeaderboardScoreIndex = i;
                }
                emit LeaderboardUpdated(_tokenId, newScore);
                return;
            }
        }
        
        if (newScore > _minLeaderboardScore || leaderboard[_minLeaderboardScoreIndex].tokenId == 0) {
            leaderboard[_minLeaderboardScoreIndex] = LeaderboardEntry(_tokenId, newScore);
            _refindMinLeaderboardScore();
            emit LeaderboardUpdated(_tokenId, newScore);
        }
    }
    
    function _refindMinLeaderboardScore() internal {
        uint256 minScore = type(uint256).max;
        uint8 minIndex = 0;
        for (uint8 i = 0; i < LEADERBOARD_SIZE; i++) {
            uint256 currentScore = leaderboard[i].tokenId == 0 ? 0 : leaderboard[i].score;
            if (currentScore <= minScore) {
                minScore = currentScore;
                minIndex = i;
            }
        }
        _minLeaderboardScore = minScore;
        _minLeaderboardScoreIndex = minIndex;
    }
}