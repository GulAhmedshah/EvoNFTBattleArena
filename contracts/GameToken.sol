// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title GameToken
 * @author EvoPlatform Team
 * @notice An ERC20 token for an NFT staking platform's game ecosystem.
 * @dev Implements the EVO token with features like staking, fee systems, a test faucet, and transfer restrictions.
 */
contract GameToken is ERC20, Ownable {
    // --- Custom Errors ---
    error GameToken__ExceedsMaxSupply();
    error GameToken__TransferWhileInBattle();
    error GameToken__FaucetCooldownNotMet();
    error GameToken__InsufficientStake();
    error GameToken__ZeroAddress();
    error GameToken__InvalidWinnerArrayLength();

    // --- Constants ---
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10**18;
    uint256 public constant BATTLE_ENTRY_FEE = 100 * 10**18;
    uint256 public constant TOURNAMENT_ENTRY_FEE = 500 * 10**18;
    uint256 public constant FAUCET_AMOUNT = 100 * 10**18;
    uint256 public constant FAUCET_COOLDOWN = 1 days;
    uint256 public constant PRIZE_POOL_PERCENTAGE = 10; // 10%

    // --- State Variables ---
    mapping(address => uint256) private _stakes;
    uint256 private _totalStaked;

    mapping(address => bool) public inActiveBattle;

    uint256 public prizePool;

    mapping(address => uint256) private _lastFaucetClaim;

    // --- Events ---
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event BattleFeePaid(address indexed player, uint256 amount);
    event TournamentFeePaid(address indexed player, uint256 amount);
    event FaucetDispensed(address indexed user, uint256 amount);
    event PrizePoolDistributed(address indexed distributor, uint256 totalAmount, uint256 winnerCount);
    event BattleStatusUpdated(address indexed player, bool status);
    event FeesWithdrawn(address indexed recipient, uint256 amount);

    /**
     * @notice Initializes the contract, sets token properties, and mints initial supply to the deployer.
     */
    constructor() ERC20("EvoToken", "EVO") Ownable(msg.sender) {
        uint256 initialSupply = 100_000_000 * 10**18;
        if (initialSupply > MAX_SUPPLY) {
            revert GameToken__ExceedsMaxSupply();
        }
        _mint(msg.sender, initialSupply);
    }

    // --- ERC20 Hooks ---

    /**
     * @dev Hook that is called before any transfer of tokens. It is used here to enforce transfer restrictions.
     * @notice Prevents users from transferring tokens while they are in an active battle.
     * This restriction is bypassed for minting (from address(0)), burning (to address(0)),
     * and transfers to this contract for staking or paying fees.
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);
        
        if (from != address(0) && to != address(this) && inActiveBattle[from]) {
            revert GameToken__TransferWhileInBattle();
        }
    }

    // --- Core Token Functions ---

    /**
     * @notice Mints new tokens for game rewards, up to the MAX_SUPPLY.
     * @dev Can only be called by the owner.
     * @param to The address to mint tokens to.
     * @param amount The amount of tokens to mint.
     */
    function mint(address to, uint256 amount) public onlyOwner {
        if (to == address(0)) {
            revert GameToken__ZeroAddress();
        }
        if (totalSupply() + amount > MAX_SUPPLY) {
            revert GameToken__ExceedsMaxSupply();
        }
        _mint(to, amount);
    }

    /**
     * @notice Allows a user to burn their own tokens, reducing the total supply.
     * @param amount The amount of tokens to burn from the caller's balance.
     */
    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }
    
    // --- Staking Mechanism ---

    /**
     * @notice Stakes a specified amount of tokens to earn rewards like battle passes.
     * @dev Tokens are transferred from the user to this contract. User must first approve the contract.
     * @param amount The amount of tokens to stake.
     */
    function stake(uint256 amount) public {
        _stakes[msg.sender] += amount;
        _totalStaked += amount;
        transferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    /**
     * @notice Unstakes a specified amount of tokens.
     * @dev Tokens are transferred from this contract back to the user.
     * @param amount The amount of tokens to unstake.
     */
    function unstake(uint256 amount) public {
        uint256 userStake = _stakes[msg.sender];
        if (userStake < amount) {
            revert GameToken__InsufficientStake();
        }
        _stakes[msg.sender] = userStake - amount;
        _totalStaked -= amount;
        _transfer(address(this), msg.sender, amount);
        emit Unstaked(msg.sender, amount);
    }
    
    // --- Game Fee System ---

    /**
     * @notice Pays the entry fee for a standard battle. User must first approve this contract.
     * @dev Transfers 100 EVO from the player. 10% goes to the prize pool.
     */
    function payBattleFee() public {
        _handleFee(BATTLE_ENTRY_FEE, msg.sender);
        emit BattleFeePaid(msg.sender, BATTLE_ENTRY_FEE);
    }

    /**
     * @notice Pays the entry fee for a tournament. User must first approve this contract.
     * @dev Transfers 500 EVO from the player. 10% goes to the prize pool.
     */
    function payTournamentFee() public {
        _handleFee(TOURNAMENT_ENTRY_FEE, msg.sender);
        emit TournamentFeePaid(msg.sender, TOURNAMENT_ENTRY_FEE);
    }

    /**
     * @dev Internal function to process a fee payment by transferring tokens and allocating to prize pool.
     */
    function _handleFee(uint256 fee, address payer) private {
        transferFrom(payer, address(this), fee);
        uint256 prizePoolCut = (fee * PRIZE_POOL_PERCENTAGE) / 100;
        prizePool += prizePoolCut;
    }

    // --- Prize Pool & Fee Management ---

    /**
     * @notice Distributes the entire prize pool to winners based on their performance shares.
     * @dev Can only be called by the owner. Resets the prize pool to zero after distribution.
     * Intended to be called periodically (e.g., monthly).
     * @param winners An array of winner addresses.
     * @param shares An array of corresponding prize shares for each winner.
     */
    function distributePrizePool(address[] calldata winners, uint256[] calldata shares) public onlyOwner {
        if (winners.length != shares.length) {
            revert GameToken__InvalidWinnerArrayLength();
        }

        uint256 totalShares;
        for (uint256 i = 0; i < shares.length; i++) {
            totalShares += shares[i];
        }

        uint256 pool = prizePool;
        if (pool == 0 || totalShares == 0) return;

        prizePool = 0; // Prevent re-entrancy by setting to zero before transfers
        
        uint256 distributedAmount;
        for (uint256 i = 0; i < winners.length; i++) {
            uint256 prize = (pool * shares[i]) / totalShares;
            if (prize > 0) {
                _transfer(address(this), winners[i], prize);
                distributedAmount += prize;
            }
        }
        
        // Return any dust from rounding to the prize pool
        if(pool > distributedAmount) {
            prizePool += pool - distributedAmount;
        }

        emit PrizePoolDistributed(msg.sender, distributedAmount, winners.length);
    }

    /**
     * @notice Withdraws the accumulated fees that were not allocated to the prize pool.
     * @dev Can only be called by the owner.
     */
    function withdrawFees() public onlyOwner {
        uint256 withdrawableAmount = balanceOf(address(this)) - _totalStaked - prizePool;
        if (withdrawableAmount > 0) {
            _transfer(address(this), owner(), withdrawableAmount);
            emit FeesWithdrawn(owner(), withdrawableAmount);
        }
    }

    // --- Test Faucet ---
    
    /**
     * @notice Provides a test user with 100 EVO tokens once per day.
     * @dev Mints new tokens, respecting the MAX_SUPPLY. For testing purposes only.
     */
    function faucet() public {
        if (block.timestamp < _lastFaucetClaim[msg.sender] + FAUCET_COOLDOWN) {
            revert GameToken__FaucetCooldownNotMet();
        }
        if (totalSupply() + FAUCET_AMOUNT > MAX_SUPPLY) {
            revert GameToken__ExceedsMaxSupply();
        }
        
        _lastFaucetClaim[msg.sender] = block.timestamp;
        _mint(msg.sender, FAUCET_AMOUNT);
        emit FaucetDispensed(msg.sender, FAUCET_AMOUNT);
    }

    // --- Admin Functions ---

    /**
     * @notice Sets the active battle status for a player to enable/disable transfer restrictions.
     * @dev Can only be called by the owner (or a designated game contract).
     * @param player The address of the player.
     * @param status The new battle status (true for in battle, false for not).
     */
    function setBattleStatus(address player, bool status) public onlyOwner {
        inActiveBattle[player] = status;
        emit BattleStatusUpdated(player, status);
    }
    
    // --- Public View Functions ---

    /**
     * @notice Gets the staked balance of a user.
     * @param user The address of the user.
     * @return The amount of tokens staked by the user.
     */
    function stakedBalance(address user) public view returns (uint256) {
        return _stakes[user];
    }
}