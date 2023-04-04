import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers } from "hardhat";

describe("Staking", function () {
  async function deployStakingFixture() {
    const [owner, alice, bob] = await ethers.getSigners();

    const Authority = await ethers.getContractFactory("Authority");
    const Manager = await ethers.getContractFactory("Manager");
    const TestToken = await ethers.getContractFactory("TestToken");
    const Vault = await ethers.getContractFactory("ArbitrumStaking");
    const GovernanceIncentiveCalculator = await ethers.getContractFactory("MockGovernanceIncentiveCalculator");

    const authority = await Authority.deploy(owner.address);
    const manager = await Manager.deploy(authority.address);
    const arbitrum = await TestToken.deploy(18);
    const firm = await TestToken.deploy(18);
    const usdc = await TestToken.deploy(6);
    const vault = await Vault.deploy()
    const calc = await GovernanceIncentiveCalculator.deploy(
      ethers.constants.AddressZero,
      usdc.address,
      arbitrum.address,
      firm.address,
    );
    await vault.initialize(
      firm.address,
      arbitrum.address,
      manager.address,
    )

    const now = await time.latest();
    await authority.setFirmament(firm.address);
    await manager.initialize(
      vault.address,
      calc.address,
      now + 3600,
    );

    await arbitrum.transfer(alice.address, ethers.utils.parseEther("1000"));
    await arbitrum.transfer(bob.address, ethers.utils.parseEther("1000"));

    await arbitrum.approve(vault.address, ethers.constants.MaxUint256);
    await arbitrum.connect(alice).approve(vault.address, ethers.constants.MaxUint256);
    await arbitrum.connect(bob).approve(vault.address, ethers.constants.MaxUint256);

    return { authority, manager, vault, owner, alice, bob, arbitrum, firm };
  }

  describe("Deployment", function () {
    it("Should calculate yield properly", async function () {
      const { authority, manager, vault, owner, arbitrum, firm } = await loadFixture(deployStakingFixture);

      await vault.stake(ethers.utils.parseEther("10"));
      expect(await vault.balanceOf(owner.address)).to.equal(ethers.utils.parseEther("10"));
      expect(await vault.earned(owner.address)).to.equal(0);
      await time.increase(3600);
      await manager.allocateGovernanceIncentive();

      expect(await vault.earned(owner.address)).to.equal(0);

      for (let i = 0; i < 3; i++) {
        await time.increase(3600 * 12);
        await manager.allocateGovernanceIncentive();
      }
      console.log('earned', await vault.earned(owner.address));

      expect(await vault.getMultiplierPoints(owner.address)).to.equal(ethers.utils.parseEther("30"));
      let earned = await vault.earned(owner.address);

      await vault.stake(ethers.utils.parseEther("10"));
      expect(await vault.getMultiplierPoints(owner.address)).to.equal(ethers.utils.parseEther("30"));
      await time.increase(3600 * 12);

      // first epoch after deposit doesn't earn rewards
      await manager.allocateGovernanceIncentive();
      expect(await vault.earned(owner.address)).to.equal(earned);
      expect(await vault.getMultiplierPoints(owner.address)).to.equal(ethers.utils.parseEther("30"));

      for (let i = 0; i < 2; i++) {
        await time.increase(3600 * 12);
        await manager.allocateGovernanceIncentive();
      }
      expect(await vault.getMultiplierPoints(owner.address)).to.equal(ethers.utils.parseEther("70"));

      for (let i = 0; i < 200; i++) {
        await time.increase(3600 * 12);
        await manager.allocateGovernanceIncentive();
      }
      earned = await vault.earned(owner.address);
      const before = await firm.balanceOf(owner.address);
      console.log('multiplier', await vault.getMultiplier(owner.address));
      console.log('after', await vault.earned(owner.address));
      await vault.claimReward();
      const after = await firm.balanceOf(owner.address);
      console.log(after.sub(before));
      // expect(await firm.balanceOf(owner.address)).to.equal(before.add(earned.mul("1094999061737661850").div(ethers.utils.parseEther("1"))));
    });
  });
});
