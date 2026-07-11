/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title ElementSystem
 * @author Your Name
 * @notice Manages elemental properties, special abilities, synergies, and counters for NFTs in a battle context.
 * @dev This contract is designed to be a component of a larger NFT gaming/staking platform.
 * It tracks elemental alignments and in-battle status effects for tokens.
 */
contract ElementSystem is Ownable, ReentrancyGuard {
    using Math for uint256;

    // =============================================================
    //                           Enums
    // =============================================================

    /// @dev Elemental alignments for characters.
    enum Element { None, Fire, Water, Earth, Air, Light, Dark }

    /// @dev Types of status effects that can be applied during battle.
    enum EffectType { None, Burn, Shield, SpeedBoost, Curse }

    // =============================================================
    //                           Structs
    // =============================================================

    /**
     * @dev Represents an active status effect on a character in battle.
     * @param effectType The type of effect (e.g., Burn, Shield).
     * @param duration The number of rounds the effect will last.
     * @param potency The strength of the effect, in basis points (1% = 100).
     */
    struct ActiveEffect {
        EffectType effectType;
        uint8 duration;
        uint16 potency;
    }

    /**
     * @dev Holds all data for a character, both persistent and transient (for battle).
     * @notice In a larger system, persistent and battle data might be split for gas efficiency.
     * @param element The character's elemental alignment.
     * @param changesUsed The number of times the character has changed its element.
     * @param hp Current health points in battle.
     * @param maxHp Maximum health points.
     * @param specialEnergy Energy for using special abilities (gained once per battle).
     * @param activeEffects Array of status effects currently affecting the character.
     */
    struct CharacterData {
        Element element;
        uint8 changesUsed;
        uint256 hp;
        uint256 maxHp;
        uint8 specialEnergy;
        ActiveEffect[5] activeEffects; // Fixed size for gas efficiency
    }

    // =============================================================
    //                           Errors
    // =============================================================

    error InvalidElement();
    error InvalidFee();
    error NotEnoughEnergy();
    error NotAnEligibleLevel();
    error MaxElementChangesReached();
    error NotInBattle();
    error NoNegativeEffects();

    // =============================================================
    //                         State Variables
    // =============================================================

    /// @dev Fee in wei to change an NFT's element.
    uint256 public elementChangeFee;

    /// @dev Mapping from a token ID to its character data.
    mapping(uint256 => CharacterData) private _characterData;

    /// @dev An external contract that can provide character levels.
    address public characterRegistry;

    // =============================================================
    //                             Events
    // =============================================================

    /// @dev Emitted when a token's element is successfully changed.
    event ElementChanged(uint256 indexed tokenId, Element oldElement, Element newElement);

    /// @dev Emitted when a special ability is used.
    event SpecialAbilityUsed(uint256 indexed casterId, uint256 indexed targetId, Element element);

    /// @dev Emitted when the fee for changing elements is updated.
    event ElementChangeFeeUpdated(uint256 newFee);

    // =============================================================
    //                          Constructor
    // =============================================================

    /**
     * @dev Sets the initial owner, fee, and registry address.
     * @param _initialFee The initial fee for changing an element.
     * @param _registryAddress The address of the contract providing character levels.
     */
    constructor(uint256 _initialFee, address _registryAddress) {
        elementChangeFee = _initialFee;
        characterRegistry = _registryAddress;
    }

    // =============================================================
    //                     Admin Functions
    // =============================================================

    /**
     * @notice Updates the fee required to change an element.
     * @param _newFee The new fee in wei.
     */
    function setElementChangeFee(uint256 _newFee) external onlyOwner {
        elementChangeFee = _newFee;
        emit ElementChangeFeeUpdated(_newFee);
    }

    /**
     * @notice Updates the address of the character registry contract.
     * @param _newRegistry The new address of the ICharacterRegistry compatible contract.
     */
    function setCharacterRegistry(address _newRegistry) external onlyOwner {
        characterRegistry = _newRegistry;
    }

    /**
     * @notice Withdraws the contract's Ether balance to the owner's address.
     */
    function withdraw() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        (bool success, ) = owner().call{value: balance}("");
        require(success, "Transfer failed.");
    }

    // =============================================================
    //                      Core Logic Functions
    // =============================================================

    /**
     * @notice Changes the element of a given token ID, subject to level and fee requirements.
     * @dev A character can change its element upon reaching levels 10, 25, 50, and 75.
     * @param tokenId The ID of the token to change.
     * @param newElement The desired new element.
     */
    function changeElement(uint256 tokenId, Element newElement) external payable nonReentrant {
        if (msg.value != elementChangeFee) revert InvalidFee();
        if (uint8(newElement) == 0 || uint8(newElement) > 6) revert InvalidElement();

        uint256 level = _getLevel(tokenId);
        CharacterData storage character = _characterData[tokenId];

        uint8 allowedChanges;
        if (level >= 75) allowedChanges = 4;
        else if (level >= 50) allowedChanges = 3;
        else if (level >= 25) allowedChanges = 2;
        else if (level >= 10) allowedChanges = 1;
        else revert NotAnEligibleLevel();

        if (character.changesUsed >= allowedChanges) revert MaxElementChangesReached();

        Element oldElement = character.element;
        character.element = newElement;
        character.changesUsed++;

        emit ElementChanged(tokenId, oldElement, newElement);
    }

    /**
     * @notice Activates the special ability of a character's element during battle.
     * @dev Consumes one unit of special energy. Abilities have various effects.
     * @param casterId The token ID of the character using the ability.
     * @param targetId The token ID of the target (can be the same as casterId for self-buffs).
     */
    function useSpecialAbility(uint256 casterId, uint256 targetId) external {
        CharacterData storage caster = _characterData[casterId];
        CharacterData storage target = _characterData[targetId];

        if (caster.hp == 0) revert NotInBattle(); // Use hp as a proxy for being in battle
        if (caster.specialEnergy < 1) revert NotEnoughEnergy();

        caster.specialEnergy--;

        Element element = caster.element;

        if (element == Element.Fire) { // Burn: 15% damage over 3 rounds
            _applyEffect(target, EffectType.Burn, 3, 500); // 5% per round
        } else if (element == Element.Water) { // Heal: recovers 20% of max HP
            caster.hp = caster.hp.add((caster.maxHp * 2000) / 10000).min(caster.maxHp);
        } else if (element == Element.Earth) { // Shield: reduces damage by 30% for 2 rounds
            _applyEffect(caster, EffectType.Shield, 2, 3000);
        } else if (element == Element.Air) { // Speed Boost: double attack speed for 1 round
            _applyEffect(caster, EffectType.SpeedBoost, 1, 10000); // 100% boost
        } else if (element == Element.Light) { // Purify: removes negative effects and heals 10%
            _removeAllNegativeEffects(caster);
            caster.hp = caster.hp.add((caster.maxHp * 1000) / 10000).min(caster.maxHp);
        } else if (element == Element.Dark) { // Curse: reduces opponent stats by 15% for 2 rounds
            _applyEffect(target, EffectType.Curse, 2, 1500);
        } else {
            revert InvalidElement();
        }

        emit SpecialAbilityUsed(casterId, targetId, element);
    }

    // =============================================================
    //                  View & Pure Functions
    // =============================================================

    /**
     * @notice Gets the elemental data for a given token.
     * @param tokenId The ID of the token.
     * @return The character's data struct.
     */
    function getCharacterData(uint256 tokenId) external view returns (CharacterData memory) {
        return _characterData[tokenId];
    }

    /**
     * @notice Calculates the damage multiplier based on elemental advantage.
     * @dev Advantage: +25%, Disadvantage: -25%.
     * Fire > Earth > Air > Water > Fire. Light >< Dark.
     * @param attacker The attacker's element.
     * @param defender The defender's element.
     * @return Multiplier in basis points (10000 = 100%). 12500 for advantage, 7500 for disadvantage.
     */
    function getElementAdvantage(Element attacker, Element defender) public pure returns (uint256) {
        if (attacker == defender || attacker == Element.None || defender == Element.None) {
            return 10000; // Neutral
        }

        if ((attacker == Element.Light && defender == Element.Dark) || (attacker == Element.Dark && defender == Element.Light)) {
            return 12500; // Advantage
        }

        if ( (attacker == Element.Fire && defender == Element.Earth) ||
             (attacker == Element.Earth && defender == Element.Air) ||
             (attacker == Element.Air && defender == Element.Water) ||
             (attacker == Element.Water && defender == Element.Fire) ) {
            return 12500; // Advantage
        }

        if ( (defender == Element.Fire && attacker == Element.Earth) ||
             (defender == Element.Earth && attacker == Element.Air) ||
             (defender == Element.Air && attacker == Element.Water) ||
             (defender == Element.Water && attacker == Element.Fire) ) {
            return 7500; // Disadvantage
        }

        return 10000; // Neutral for all other combinations
    }

    /**
     * @notice Checks for team synergy bonus.
     * @dev A team where all members share the same element (not None) gets a 10% bonus.
     * @param tokenIds An array of token IDs on the same team.
     * @return The bonus multiplier in basis points (11000 for bonus, 10000 for none).
     */
    function getTeamSynergyBonus(uint256[] calldata tokenIds) external view returns (uint256) {
        if (tokenIds.length <= 1) return 10000; // No bonus for single-member teams

        Element firstElement = _characterData[tokenIds[0]].element;
        if (firstElement == Element.None) return 10000; // No synergy for None element

        for (uint256 i = 1; i < tokenIds.length; i++) {
            if (_characterData[tokenIds[i]].element != firstElement) {
                return 10000; // Elements do not match
            }
        }

        return 11000; // 10% bonus
    }

    // =============================================================
    //                    Internal & Private Helpers
    // =============================================================

    /**
     * @dev Internal function to get a character's level from the registry.
     * @param tokenId The ID of the token.
     * @return The character's level.
     */
    function _getLevel(uint256 tokenId) internal view returns (uint256) {
        if (characterRegistry == address(0)) return 0;
        // This is a simplified interface. A real implementation might require more specific function signatures.
        (bool success, bytes memory data) = characterRegistry.staticcall(
            abi.encodeWithSignature("getLevel(uint256)", tokenId)
        );
        return success && data.length == 32 ? abi.decode(data, (uint256)) : 0;
    }

    /**
     * @dev Applies a new status effect to a character, overwriting the first available slot.
     * @notice If all slots are full, it overwrites the first one. A more complex system could manage priorities.
     */
    function _applyEffect(CharacterData storage character, EffectType effectType, uint8 duration, uint16 potency) private {
        for (uint i = 0; i < character.activeEffects.length; i++) {
            if (character.activeEffects[i].effectType == EffectType.None || character.activeEffects[i].duration == 0) {
                character.activeEffects[i] = ActiveEffect(effectType, duration, potency);
                return;
            }
        }
        // If no empty slot, overwrite the first one.
        character.activeEffects[0] = ActiveEffect(effectType, duration, potency);
    }

    /**
     * @dev Removes all negative effects (Burn, Curse) from a character.
     */
    function _removeAllNegativeEffects(CharacterData storage character) private {
        bool hadNegativeEffects = false;
        for (uint i = 0; i < character.activeEffects.length; i++) {
            EffectType et = character.activeEffects[i].effectType;
            if (et == EffectType.Burn || et == EffectType.Curse) {
                character.activeEffects[i] = ActiveEffect(EffectType.None, 0, 0);
                hadNegativeEffects = true;
            }
        }
        if (!hadNegativeEffects) revert NoNegativeEffects();
    }

    // =============================================================
    //         Battle Setup/Teardown (to be called externally)
    // =============================================================

    /**
     * @notice Initializes characters for battle.
     * @dev To be called by a battle contract before a fight begins.
     * This is a simplified setup for demonstration.
     */
    function _setupBattleParticipant(uint256 tokenId, uint256 maxHp) internal {
        CharacterData storage character = _characterData[tokenId];
        character.maxHp = maxHp;
        character.hp = maxHp;
        character.specialEnergy = 1; // Each participant gets 1 energy per battle
        // Clear effects from previous battles
        for (uint i = 0; i < character.activeEffects.length; i++) {
            character.activeEffects[i] = ActiveEffect(EffectType.None, 0, 0);
        }
    }
}
