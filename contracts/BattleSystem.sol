// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// The IEvoNFT interface is expected to be in `contracts/interfaces/IEvoNFT.sol`
// and should define the `Stats` struct and `Element` enum, for example:
//
// interface IEvoNFT {
//     enum Element { None, Fire, Water, Earth, Air, Light, Dark }
//     struct Stats {
//         uint32 strength;
//         uint32 defense;
//         uint32 speed;
//         uint32 intelligence;
//     }
//     function getNFTStats(uint256 tokenId) external view returns (Stats memory);
//     function getNFTElement(uint256 tokenId) external view returns (Element);
// }
import "../interfaces/IEvoNFT.sol";

/**
 * @title BattleCalculator
 * @notice A library for performing battle-related calculations for EvoNFTs.
 * @dev Provides functions for calculating power, damage, critical hits, and overall battle scores.
 * All multipliers are based on a 100-point scale (e.g., 150 represents a 1.5x multiplier).
 */
library BattleCalculator {
    // Multiplier constants (base 100)
    uint256 private constant SUPER_EFFECTIVE_MULTIPLIER = 150; // 1.5x
    uint256 private constant EFFECTIVE_MULTIPLIER = 120; // 1.2x
    uint256 private constant NEUTRAL_MULTIPLIER = 100; // 1.0x
    uint256 private constant NOT_VERY_EFFECTIVE_MULTIPLIER = 80; // 0.8x
    uint256 private constant INEFFECTIVE_MULTIPLIER = 50; // 0.5x

    /**
     * @notice Calculates the total power score of an NFT by summing its stats.
     * @param stats The stat block of the NFT.
     * @return The combined stat score.
     */
    function calculatePower(IEvoNFT.Stats memory stats) internal pure returns (uint256) {
        return stats.strength + stats.defense + stats.speed + stats.intelligence;
    }

    /**
     * @notice Determines the damage multiplier based on elemental advantages.
     * @dev Multipliers: Super (1.5x), Effective (1.2x), Neutral (1.0x), Not Very (0.8x), Ineffective (0.5x).
     * - Fire > Earth, Water > Fire, Earth > Water (1.5x / 0.5x)
     * - Air > Earth (1.2x / 0.8x)
     * - Light <> Dark (1.5x)
     * @param attackerElement The element of the attacking NFT.
     * @param defenderElement The element of the defending NFT.
     * @return A multiplier value (where 100 = 1.0x).
     */
    function getElementAdvantage(
        IEvoNFT.Element attackerElement,
        IEvoNFT.Element defenderElement
    ) internal pure returns (uint256) {
        if (attackerElement == defenderElement || attackerElement == IEvoNFT.Element.None || defenderElement == IEvoNFT.Element.None) {
            return NEUTRAL_MULTIPLIER;
        }

        // Cyclic advantages (Fire > Earth > Water > Fire)
        if (attackerElement == IEvoNFT.Element.Fire && defenderElement == IEvoNFT.Element.Earth) return SUPER_EFFECTIVE_MULTIPLIER;
        if (attackerElement == IEvoNFT.Element.Earth && defenderElement == IEvoNFT.Element.Fire) return INEFFECTIVE_MULTIPLIER;

        if (attackerElement == IEvoNFT.Element.Earth && defenderElement == IEvoNFT.Element.Water) return SUPER_EFFECTIVE_MULTIPLIER;
        if (attackerElement == IEvoNFT.Element.Water && defenderElement == IEvoNFT.Element.Earth) return INEFFECTIVE_MULTIPLIER;

        if (attackerElement == IEvoNFT.Element.Water && defenderElement == IEvoNFT.Element.Fire) return SUPER_EFFECTIVE_MULTIPLIER;
        if (attackerElement == IEvoNFT.Element.Fire && defenderElement == IEvoNFT.Element.Water) return INEFFECTIVE_MULTIPLIER;

        // Specific advantages (Air > Earth)
        if (attackerElement == IEvoNFT.Element.Air && defenderElement == IEvoNFT.Element.Earth) return EFFECTIVE_MULTIPLIER;
        if (attackerElement == IEvoNFT.Element.Earth && defenderElement == IEvoNFT.Element.Air) return NOT_VERY_EFFECTIVE_MULTIPLIER;

        // Binary advantages (Light <> Dark)
        if ((attackerElement == IEvoNFT.Element.Light && defenderElement == IEvoNFT.Element.Dark) ||
            (attackerElement == IEvoNFT.Element.Dark && defenderElement == IEvoNFT.Element.Light)) {
            return SUPER_EFFECTIVE_MULTIPLIER;
        }

        return NEUTRAL_MULTIPLIER;
    }

    /**
     * @notice Calculates the base damage dealt by an attacker to a defender.
     * @param attackerPower The attacker's total power.
     * @param attackerElement The attacker's element.
     * @param defenderElement The defender's element.
     * @return The base damage value, adjusted for elemental advantage.
     */
    function calculateDamage(
        uint256 attackerPower,
        IEvoNFT.Element attackerElement,
        IEvoNFT.Element defenderElement
    ) internal pure returns (uint256) {
        uint256 advantageMultiplier = getElementAdvantage(attackerElement, defenderElement);
        return (attackerPower * advantageMultiplier) / 100;
    }

    /**
     * @notice Determines if a critical hit occurs and calculates the resulting damage.
     * @dev Uses a pseudo-random number from the provided seed. NOT suitable for high-value scenarios.
     * @param baseDamage The damage before critical hit calculation.
     * @param critChance The chance of a critical hit (e.g., 10 for 10%).
     * @param randomSeed A pseudo-random seed (e.g., from blockhash).
     * @return The final damage, potentially doubled on a critical hit.
     */
    function calculateCriticalHit(
        uint256 baseDamage,
        uint256 critChance,
        bytes32 randomSeed
    ) internal pure returns (uint256) {
        uint256 randomValue = uint256(randomSeed) % 100;
        if (randomValue < critChance) {
            // Critical hit! Damage is doubled.
            return baseDamage * 2;
        }
        return baseDamage;
    }

    /**
     * @notice Calculates a weighted battle score for an NFT, with a random variation.
     * @dev Weights: 30% Strength, 25% Defense, 25% Speed, 20% Intelligence.
     *      Variation: Randomly adjusts the final score by +-15%.
     * @param stats The stat block of the NFT.
     * @param randomSeed A pseudo-random seed for variation. NOT for secure randomness.
     * @return The final, varied battle score.
     */
    function calculateBattleScore(
        IEvoNFT.Stats memory stats,
        bytes32 randomSeed
    ) internal pure returns (uint256) {
        // Calculate weighted base score
        uint256 baseScore = ((stats.strength * 30) +
            (stats.defense * 25) +
            (stats.speed * 25) +
            (stats.intelligence * 20)) / 100;

        // Apply a random variation of +-15% (i.e., a multiplier from 85% to 115%)
        // We derive the random number from the second half of the seed to avoid collisions
        uint256 variation = (uint256(randomSeed) >> 128) % 31; // A number between 0 and 30
        uint256 multiplier = 85 + variation; // A multiplier between 85 and 115

        return (baseScore * multiplier) / 100;
    }
}

/**
 * @title BattleSystem
 * @notice A contract for managing and simulating battles between EvoNFTs.
 * @dev This contract uses the BattleCalculator library to determine battle outcomes.
 * It is a simplified example of how the library can be used.
 */
contract BattleSystem {
    /// @notice The EvoNFT contract this battle system is tied to.
    IEvoNFT public immutable evoNFT;

    /**
     * @dev Emitted when battle scores are calculated for a pair of NFTs.
     */
    event BattleScoresCalculated(
        uint256 indexed tokenIdA,
        uint256 indexed tokenIdB,
        uint256 scoreA,
        uint256 scoreB
    );

    /**
     * @param _evoNFTAddress The address of the deployed EvoNFT contract.
     */
    constructor(address _evoNFTAddress) {
        evoNFT = IEvoNFT(_evoNFTAddress);
    }

    /**
     * @notice Resolves a battle and calculates scores for two NFTs.
     * @dev WARNING: Uses block-dependent variables for pseudo-randomness (block.timestamp, msg.sender).
     * This is NOT secure for production systems where outcomes have financial value.
     * A secure source of randomness like Chainlink VRF is recommended for such cases.
     * @param tokenIdA The ID of the first NFT.
     * @param tokenIdB The ID of the second NFT.
     * @return scoreA The final battle score for NFT A.
     * @return scoreB The final battle score for NFT B.
     */
    function resolveBattle(uint256 tokenIdA, uint256 tokenIdB)
        external
        returns (uint256 scoreA, uint256 scoreB)
    {
        // Generate a pseudo-random seed.
        bytes32 randomSeed = keccak256(abi.encodePacked(block.timestamp, msg.sender, tokenIdA, tokenIdB));

        // Fetch stats directly from the NFT contract using the interface.
        IEvoNFT.Stats memory statsA = evoNFT.getNFTStats(tokenIdA);
        IEvoNFT.Stats memory statsB = evoNFT.getNFTStats(tokenIdB);

        // Use the library to calculate the final battle scores.
        scoreA = BattleCalculator.calculateBattleScore(statsA, randomSeed);
        scoreB = BattleCalculator.calculateBattleScore(statsB, randomSeed);

        emit BattleScoresCalculated(tokenIdA, tokenIdB, scoreA, scoreB);

        return (scoreA, scoreB);
    }
}