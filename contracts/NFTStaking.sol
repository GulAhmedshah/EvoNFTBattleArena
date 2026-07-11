// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
// ERC4907 is the standard for rentable NFTs. It extends ERC721.
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC721/extensions/ERC4907.sol";


/**
 * @title NFTStaking
 * @author Your Name
 * @notice An NFT contract with staking, battling, and renting capabilities.
 * This contract implements ERC4907 for NFT rentals, allowing owners to list their
 * NFTs for rent and renters to use them for a specified duration. It also includes
 * a locking mechanism to prevent transfers during sensitive operations like battles.
 */
contract NFTStaking is ERC4907, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdCounter;

    // --- Enums ---

    /**
     * @dev Describes the current activity status of an NFT.
     * An NFT's status determines if it can be transferred.
     */
    enum ActivityStatus {
        None,
        Training,
        InBattle
    }

    // --- Mappings ---

    /**
     * @dev Maps a tokenId to its current activity status.
     * If status is not None, the NFT is considered locked.
     */
    mapping(uint256 => ActivityStatus) public activityStatus;

    /**
     * @dev Maps a tokenId to its rental listing details.
     */
    mapping(uint256 => RentalListing) public rentalListings;

    /**
     * @dev Maps a tokenId to its active rental information.
     * This supplements ERC4907 by storing rental-specific financial and activity data.
     */
    mapping(uint256 => ActiveRental) public activeRentals;

    /**
     * @dev Maps an NFT owner's address to their total accumulated rental revenue.
     */
    mapping(address => uint256) public rentRevenue;

    // --- Structs ---

    /**
     * @dev Stores information for an NFT listed for rent.
     * @param dailyPrice The price in wei to rent the NFT for one day.
     * @param minRentalDays The minimum number of days the NFT can be rented for.
     * @param maxRentalDays The maximum number of days the NFT can be rented for.
     * @param isListed Flag indicating if the NFT is currently listed for rent.
     */
    struct RentalListing {
        uint256 dailyPrice;
        uint16 minRentalDays;
        uint16 maxRentalDays;
        bool isListed;
    }

    /**
     * @dev Stores information about an active rental.
     * @param renter The address of the user renting the NFT.
     * @param securityDeposit The amount held in escrow as a security deposit.
     * @param expires The timestamp when the rental period ends.
     * @param lastBattleTimestamp The timestamp of the renter's last battle with the NFT.
     */
    struct ActiveRental {
        address renter;
        uint256 securityDeposit;
        uint256 expires;
        uint256 lastBattleTimestamp;
    }

    // --- Constants ---

    /// @notice The cooldown period a renter must adhere to for battles.
    uint256 public constant BATTLE_COOLDOWN_PERIOD = 24 hours;

    // --- Events ---

    event NFTLocked(uint256 indexed tokenId, ActivityStatus status);
    event NFTUnlocked(uint256 indexed tokenId);
    event EmergencyUnlock(uint256 indexed tokenId, address indexed owner);
    event NFTListedForRent(uint256 indexed tokenId, address indexed owner, uint256 dailyPrice, uint16 minRentalDays, uint16 maxRentalDays);
    event NFTDelisted(uint256 indexed tokenId);
    event NFTRented(uint256 indexed tokenId, address indexed owner, address indexed renter, uint256 totalFee, uint256 expires);
    event RentalSettled(uint256 indexed tokenId, address indexed renter, uint256 depositReturned, uint256 penaltyPaid);
    event BattleActivityRecorded(uint256 indexed tokenId, address indexed renter);


    // --- Constructor ---

    /**
     * @dev Initializes the contract, setting the name and symbol for the NFT collection.
     */
    constructor() ERC721("NFTStakingHero", "NSH") ERC4907() {}

    // --- Minting Function (for demonstration) ---
    function safeMint(address to, string memory uri) public onlyOwner {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
    }
    
    // --- Core Hooks & Overrides ---

    /**
     * @dev Hook that is called before any token transfer.
     * Reverts if the token is locked (i.e., its activity status is not 'None').
     */
    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize) internal virtual override(ERC721, ERC4907) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);

        if (from != address(0) && activityStatus[tokenId] != ActivityStatus.None) {
            revert("NFTStaking: Token is locked and cannot be transferred.");
        }
    }

    // --- Locking Mechanism ---

    /**
     * @notice Locks an NFT by setting its activity status, preventing transfers.
     * @dev Can only be called by the NFT owner or current user (renter).
     * @param tokenId The ID of the token to lock.
     * @param status The activity status to set.
     */
    function lockNFT(uint256 tokenId, ActivityStatus status) public {
        _requireIsOwnerOrUser(tokenId, _msgSender());
        require(status != ActivityStatus.None, "NFTStaking: Cannot lock with 'None' status.");
        require(activityStatus[tokenId] == ActivityStatus.None, "NFTStaking: Token is already locked.");

        activityStatus[tokenId] = status;
        emit NFTLocked(tokenId, status);
    }

    /**
     * @notice Unlocks an NFT by resetting its activity status, allowing transfers.
     * @dev Can only be called by the NFT owner or current user (renter).
     * @param tokenId The ID of the token to unlock.
     */
    function unlockNFT(uint256 tokenId) public {
        _requireIsOwnerOrUser(tokenId, _msgSender());
        require(activityStatus[tokenId] != ActivityStatus.None, "NFTStaking: Token is not locked.");

        activityStatus[tokenId] = ActivityStatus.None;
        emit NFTUnlocked(tokenId);
    }

    /**
     * @notice Allows an owner to forcibly unlock their NFT.
     * @dev This is an emergency function. It cannot be used if the NFT is in an active battle.
     * @param tokenId The ID of the token to unlock.
     */
    function emergencyUnlock(uint256 tokenId) external {
        require(ownerOf(tokenId) == _msgSender(), "NFTStaking: Not the owner.");
        require(activityStatus[tokenId] != ActivityStatus.None, "NFTStaking: Token is not locked.");
        require(activityStatus[tokenId] != ActivityStatus.InBattle, "NFTStaking: Cannot unlock during a battle.");

        activityStatus[tokenId] = ActivityStatus.None;
        emit EmergencyUnlock(tokenId, _msgSender());
    }

    // --- Rental System ---

    /**
     * @notice Lists an NFT for rent.
     * @dev Only the owner of the NFT can call this function.
     * @param tokenId The ID of the token to list.
     * @param dailyPrice The rental price per day in wei.
     * @param minRentalDays The minimum rental duration in days.
     * @param maxRentalDays The maximum rental duration in days.
     */
    function listNFTForRent(uint256 tokenId, uint256 dailyPrice, uint16 minRentalDays, uint16 maxRentalDays) external {
        require(ownerOf(tokenId) == _msgSender(), "NFTStaking: Not the owner.");
        require(dailyPrice > 0, "NFTStaking: Daily price must be positive.");
        require(minRentalDays > 0, "NFTStaking: Min rental days must be positive.");
        require(maxRentalDays >= minRentalDays, "NFTStaking: Max days must be >= min days.");
        require(activityStatus[tokenId] == ActivityStatus.None, "NFTStaking: Cannot list a locked NFT.");

        rentalListings[tokenId] = RentalListing({
            dailyPrice: dailyPrice,
            minRentalDays: minRentalDays,
            maxRentalDays: maxRentalDays,
            isListed: true
        });

        emit NFTListedForRent(tokenId, _msgSender(), dailyPrice, minRentalDays, maxRentalDays);
    }

    /**
     * @notice Removes an NFT from the rental market.
     * @dev Only the owner can delist.
     * @param tokenId The ID of the token to delist.
     */
    function delistNFTFromRent(uint256 tokenId) external {
        require(ownerOf(tokenId) == _msgSender(), "NFTStaking: Not the owner.");
        require(rentalListings[tokenId].isListed, "NFTStaking: NFT is not listed for rent.");

        delete rentalListings[tokenId];
        emit NFTDelisted(tokenId);
    }

    /**
     * @notice Rents an NFT for a specified number of days.
     * @dev The renter must send ETH equal to the total rental fee plus a security deposit (2x rental fee).
     * @param tokenId The ID of the token to rent.
     * @param rentalDays The number of days to rent the NFT.
     */
    function rentNFT(uint256 tokenId, uint256 rentalDays) external payable {
        RentalListing storage listing = rentalListings[tokenId];
        require(listing.isListed, "NFTStaking: NFT is not listed for rent.");
        require(rentalDays >= listing.minRentalDays && rentalDays <= listing.maxRentalDays, "NFTStaking: Invalid rental duration.");

        address owner = ownerOf(tokenId);
        require(owner != _msgSender(), "NFTStaking: Owner cannot rent their own NFT.");

        uint256 totalRentFee = listing.dailyPrice * rentalDays;
        uint256 securityDeposit = totalRentFee * 2;
        uint256 requiredPayment = totalRentFee + securityDeposit;

        require(msg.value == requiredPayment, "NFTStaking: Incorrect payment amount sent.");

        listing.isListed = false;

        uint64 expires = uint64(block.timestamp + (rentalDays * 1 days));
        _setUser(tokenId, _msgSender(), expires);

        activeRentals[tokenId] = ActiveRental({
            renter: _msgSender(),
            securityDeposit: securityDeposit,
            expires: expires,
            lastBattleTimestamp: block.timestamp
        });

        rentRevenue[owner] += totalRentFee;

        (bool success, ) = owner.call{value: totalRentFee}("");
        require(success, "NFTStaking: Failed to send rent fee to owner.");

        emit NFTRented(tokenId, owner, _msgSender(), totalRentFee, expires);
    }
    
    /**
     * @notice Settles a rental after it has expired to distribute the security deposit.
     * @dev Can be called by anyone. Returns the deposit to the renter or gives it to the owner as penalty.
     * @param tokenId The ID of the token whose rental is to be settled.
     */
    function settleRental(uint256 tokenId) external {
        ActiveRental storage rental = activeRentals[tokenId];
        address renter = rental.renter;
        
        require(renter != address(0), "NFTStaking: No active rental for this token.");
        require(block.timestamp > rental.expires, "NFTStaking: Rental period has not expired yet.");

        uint256 deposit = rental.securityDeposit;
        uint256 penalty = 0;
        address owner = ownerOf(tokenId);

        if (block.timestamp > rental.lastBattleTimestamp + BATTLE_COOLDOWN_PERIOD) {
            penalty = deposit;
            rentRevenue[owner] += penalty;
            (bool success, ) = owner.call{value: deposit}("");
            require(success, "NFTStaking: Failed to send penalty to owner.");
        } else {
            (bool success, ) = renter.call{value: deposit}("");
            require(success, "NFTStaking: Failed to return deposit to renter.");
        }

        delete activeRentals[tokenId];
        delete rentalListings[tokenId];

        emit RentalSettled(tokenId, renter, deposit - penalty, penalty);
    }

    // --- Renter Actions & Penalties ---

    /**
     * @notice A function for the renter to record battle activity and reset the penalty cooldown.
     * @dev This function would typically be called within a `battle()` function.
     * @param tokenId The ID of the token used in battle.
     */
    function recordBattleActivity(uint256 tokenId) external {
        require(userOf(tokenId) == _msgSender(), "NFTStaking: You are not the current renter.");
        require(activityStatus[tokenId] == ActivityStatus.InBattle, "NFTStaking: Must be in battle to record activity.");
        
        activeRentals[tokenId].lastBattleTimestamp = block.timestamp;

        emit BattleActivityRecorded(tokenId, _msgSender());
    }

    // --- Helper & View Functions ---

    /**
     * @dev Checks if an address is the owner or the current user (renter) of a token.
     */
    function _requireIsOwnerOrUser(uint256 tokenId, address spender) internal view {
        require(ownerOf(tokenId) == spender || userOf(tokenId) == spender, "NFTStaking: Caller is not owner or user.");
    }
    
    /**
     * @notice A placeholder function to demonstrate how evolving would be restricted to the owner.
     * @param tokenId The ID of the token to evolve.
     */
    function evolve(uint256 tokenId) external {
        require(ownerOf(tokenId) == _msgSender(), "NFTStaking: Only the owner can evolve the NFT.");
        // ... evolution logic here ...
    }
}
