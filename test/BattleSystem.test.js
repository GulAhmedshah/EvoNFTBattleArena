const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time, loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

// In a real project, these mock contracts would be in `contracts/mocks/`
// For this task, we assume they are available to Hardhat's compiler.
// This test file will function correctly if you have:
// - contracts/mocks/ERC20Mock.sol (standard OpenZeppelin mock)
// - contracts/mocks/CharacterNFTMock.sol (a mock ERC721 with stats and required functions)
// - contracts/BattleSystem.sol (the contract being tested)

describe("BattleSystem", function () {
    // We define a fixture to reuse the same setup in every test.
    async function deployContractsFixture() {
        const [owner, addr1, addr2, addr3, ...addrs] = await ethers.getSigners();

        // Deploy Mock ERC20 Rewards Token
        const RewardsTokenFactory = await ethers.getContractFactory("ERC20Mock");
        const rewardsToken = await RewardsTokenFactory.deploy("Rewards Token", "RWD");

        // Deploy Mock Character NFT
        const CharacterNFTFactory = await ethers.getContractFactory("CharacterNFTMock");
        const characterNFT = await CharacterNFTFactory.deploy();

        // Deploy Battle System
        const BattleSystemFactory = await ethers.getContractFactory("BattleSystem");
        const battleSystem = await BattleSystemFactory.deploy(characterNFT.address, rewardsToken.address);

        // Grant the BattleSystem contract a role to update character stats
        const UPDATER_ROLE = await characterNFT.UPDATER_ROLE();
        await characterNFT.grantRole(UPDATER_ROLE, battleSystem.address);

        // Mint characters for test accounts
        // mint(to, level, exp, attack, defense, speed, element)
        // Element Enum: 0:None, 1:Fire, 2:Water, 3:Grass, 4:Light, 5:Dark
        await characterNFT.mint(owner.address, 5, 0, 20, 10, 15, 1);   // Token ID 0, Fire
        await characterNFT.mint(addr1.address, 5, 0, 18, 12, 12, 2);   // Token ID 1, Water
        await characterNFT.mint(addr2.address, 5, 0, 19, 11, 14, 3);   // Token ID 2, Grass
        await characterNFT.mint(owner.address, 100, 0, 500, 500, 500, 4); // Token ID 3, Light (for edge case)

        // Approve the BattleSystem to manage NFTs
        for (const acc of [owner, addr1, addr2, addr3]) {
            await characterNFT.connect(acc).setApprovalForAll(battleSystem.address, true);
        }

        return { battleSystem, characterNFT, rewardsToken, owner, addr1, addr2, addr3, addrs };
    }

    describe("Deployment and Configuration", function () {
        it("Should set the right owner and contract addresses", async function () {
            const { battleSystem, characterNFT, rewardsToken, owner } = await loadFixture(deployContractsFixture);
            expect(await battleSystem.owner()).to.equal(owner.address);
            expect(await battleSystem.characterNFT()).to.equal(characterNFT.address);
            expect(await battleSystem.rewardsToken()).to.equal(rewardsToken.address);
        });
    });

    describe("Battle Logic Calculations", function () {
        it("Should calculate power correctly based on stats and level", async function () {
            const { battleSystem } = await loadFixture(deployContractsFixture);
            // Assuming power formula is: (attack + defense + speed) * level
            // Token 0: (20 + 10 + 15) * 5 = 45 * 5 = 225
            expect(await battleSystem.getPower(0)).to.equal(225);
            // Token 3: (500 + 500 + 500) * 100 = 1500 * 100 = 150000
            expect(await battleSystem.getPower(3)).to.equal(150000);
        });

        it("Should apply correct damage multipliers for elemental advantage", async function () {
            const { battleSystem } = await loadFixture(deployContractsFixture);
            // Assuming a public test function `calculateDamage` exists for this verification
            const attackerPower = 100;
            const defenderPower = 80;

            const advantageDamage = await battleSystem.calculateDamage(attackerPower, defenderPower, 1, 3); // Fire > Grass
            const neutralDamage = await battleSystem.calculateDamage(attackerPower, defenderPower, 1, 4);   // Fire vs Light
            const disadvantageDamage = await battleSystem.calculateDamage(attackerPower, defenderPower, 1, 2); // Fire < Water

            expect(advantageDamage).to.be.gt(neutralDamage);
            expect(neutralDamage).to.be.gt(disadvantageDamage);
        });

        it("Should calculate score based on documented weights", async function () {
            const { battleSystem } = await loadFixture(deployContractsFixture);
            // Assuming score = (damageDealt * 2) + remainingHp
            const score = await battleSystem.calculateScore(50, 80, 100);
            expect(score).to.equal(50 * 2 + 80);
        });
    });

    describe("1v1 Battle Execution", function () {
        it("Should execute a battle, distribute EXP, and track wins/losses", async function () {
            const { battleSystem, characterNFT, owner, addr1 } = await loadFixture(deployContractsFixture);
            const challengerId = 0; // owner's Fire NFT
            const opponentId = 2;   // addr2's Grass NFT

            // Fire (advantage) vs Grass
            await expect(battleSystem.connect(owner).challenge(challengerId, opponentId))
                .to.emit(battleSystem, "BattleConcluded");

            const challenger = await characterNFT.getCharacter(challengerId);
            const opponent = await characterNFT.getCharacter(opponentId);

            expect(challenger.wins).to.equal(1);
            expect(challenger.losses).to.equal(0);
            expect(challenger.experience).to.be.gt(0);

            expect(opponent.wins).to.equal(0);
            expect(opponent.losses).to.equal(1);
            // Assuming loser might get a small amount of EXP
            expect(opponent.experience).to.be.gte(0);
        });

        it("Should reject challenges from non-owners", async function () {
            const { battleSystem, addr1 } = await loadFixture(deployContractsFixture);
            await expect(battleSystem.connect(addr1).challenge(0, 1))
                .to.be.revertedWith("BattleSystem: Caller is not the owner of the challenger NFT.");
        });

        it("Should enforce battle cooldowns", async function () {
            const { battleSystem, owner } = await loadFixture(deployContractsFixture);
            await battleSystem.connect(owner).challenge(0, 2);
            await expect(battleSystem.connect(owner).challenge(0, 2))
                .to.be.revertedWith("BattleSystem: Character is on cooldown.");

            const cooldown = await battleSystem.BATTLE_COOLDOWN();
            await time.increase(cooldown.add(1));

            await expect(battleSystem.connect(owner).challenge(0, 2))
                .to.emit(battleSystem, "BattleConcluded");
        });
    });

    describe("Rental System", function () {
        it("Should list an NFT for rent and allow another user to rent it", async function () {
            const { battleSystem, owner, addr1 } = await loadFixture(deployContractsFixture);
            const tokenId = 0;
            const pricePerDay = ethers.utils.parseEther("0.1");
            const rentDays = 2;
            const totalCost = pricePerDay.mul(rentDays);

            await battleSystem.connect(owner).listForRent(tokenId, pricePerDay, 7);
            await expect(battleSystem.connect(addr1).rent(tokenId, rentDays, { value: totalCost }))
                .to.emit(battleSystem, "NFTRented");

            const listing = await battleSystem.rentals(tokenId);
            const blockTimestamp = (await ethers.provider.getBlock("latest")).timestamp;

            expect(listing.renter).to.equal(addr1.address);
            expect(listing.rentDuration).to.equal(rentDays * 86400);
        });

        it("Should allow renter to use NFT in battle and revert after expiry", async function () {
            const { battleSystem, owner, addr1, addr2 } = await loadFixture(deployContractsFixture);
            const rentedTokenId = 0;
            const opponentTokenId = 2;
            const pricePerDay = ethers.utils.parseEther("0.1");

            await battleSystem.connect(owner).listForRent(rentedTokenId, pricePerDay, 7);
            await battleSystem.connect(addr1).rent(rentedTokenId, 1, { value: pricePerDay });

            // Renter can battle
            await expect(battleSystem.connect(addr1).challengeAsRenter(rentedTokenId, opponentTokenId))
                .to.emit(battleSystem, "BattleConcluded");

            // Fast-forward time past the rental period
            await time.increase(86400 + 60); // 1 day + 1 minute

            // Renter can no longer battle
            await expect(battleSystem.connect(addr1).challengeAsRenter(rentedTokenId, opponentTokenId))
                .to.be.revertedWith("BattleSystem: Rental has expired or you are not the renter.");

            // Owner should regain control and be able to battle
            await expect(battleSystem.connect(owner).challenge(rentedTokenId, opponentTokenId))
                .to.emit(battleSystem, "BattleConcluded");
        });
    });

    describe("Tournament System", function () {
        it("Should handle tournament creation, joining, and starting", async function () {
            const { battleSystem, characterNFT, owner, addr1, addr2, addr3 } = await loadFixture(deployContractsFixture);
            
            await characterNFT.mint(addr3.address, 5, 0, 15, 15, 15, 4); // Token ID 4

            const prizeAmount = ethers.utils.parseEther("10");
            await battleSystem.createTournament(4, prizeAmount);

            await battleSystem.connect(owner).joinTournament(0, 0);
            await battleSystem.connect(addr1).joinTournament(0, 1);
            await battleSystem.connect(addr2).joinTournament(0, 2);
            await battleSystem.connect(addr3).joinTournament(0, 4);

            await expect(battleSystem.connect(owner).startTournament(0))
                .to.emit(battleSystem, "TournamentStarted");
            
            const tournament = await battleSystem.tournaments(0);
            expect(tournament.isActive).to.be.true;
            expect(tournament.participantsCount).to.equal(4);
        });

        it("Should correctly process tournament rounds and distribute prize", async function () {
            const { battleSystem, characterNFT, rewardsToken, owner, addr1, addr2, addr3 } = await loadFixture(deployContractsFixture);
            await characterNFT.mint(addr3.address, 5, 0, 1, 1, 1, 4); // Mint a weak token, ID 4
            
            const prizeAmount = ethers.utils.parseEther("50");
            await rewardsToken.mint(battleSystem.address, prizeAmount); // Fund the contract

            await battleSystem.createTournament(4, prizeAmount);

            // Strongest token (0) vs Weak (4), Mid (2) vs Mid (1)
            await battleSystem.connect(owner).joinTournament(0, 0);
            await battleSystem.connect(addr3).joinTournament(0, 4);
            await battleSystem.connect(addr2).joinTournament(0, 2);
            await battleSystem.connect(addr1).joinTournament(0, 1);

            await battleSystem.startTournament(0);
            
            // Round 1
            await battleSystem.executeTournamentRound(0);
            // Round 2 (Final)
            await battleSystem.executeTournamentRound(0);

            const tournament = await battleSystem.tournaments(0);
            const winnerId = tournament.winnerTokenId;

            // Token 0 is the strongest and should win
            expect(winnerId).to.equal(0);
            expect(await rewardsToken.balanceOf(owner.address)).to.equal(prizeAmount);
        });
    });

    describe("Edge Cases", function () {
        it("Should handle battle with a zero-stat character", async function () {
            const { battleSystem, characterNFT, owner, addr1 } = await loadFixture(deployContractsFixture);
            await characterNFT.mint(addr1.address, 1, 0, 0, 0, 0, 0); // Token ID 4 (zero stats)
            
            await expect(battleSystem.connect(owner).challenge(0, 4))
                .to.emit(battleSystem, "BattleConcluded");
            
            const winner = await characterNFT.getCharacter(0);
            const loser = await characterNFT.getCharacter(4);

            expect(winner.wins).to.equal(1);
            expect(loser.losses).to.equal(1);
        });

        it("Should correctly resolve battle between vastly different levels (Lvl 5 vs Lvl 100)", async function () {
            const { battleSystem, characterNFT, owner, addr1 } = await loadFixture(deployContractsFixture);
            // Token 1 (addr1): Level 5
            // Token 3 (owner): Level 100
            
            await expect(battleSystem.connect(addr1).challenge(1, 3))
                .to.emit(battleSystem, "BattleConcluded");

            const challenger = await characterNFT.getCharacter(1); // Lvl 5
            const opponent = await characterNFT.getCharacter(3);   // Lvl 100

            expect(challenger.wins).to.equal(0);
            expect(challenger.losses).to.equal(1);
            expect(opponent.wins).to.equal(1);
            expect(opponent.losses).to.equal(0);
        });
    });
});
