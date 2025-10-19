const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ProjectFactory", function () {
  let projectFactory;
  let owner;
  let creator1;
  let creator2;
  let investor1;
  let investor2;

  beforeEach(async function () {
    [owner, creator1, creator2, investor1, investor2] = await ethers.getSigners();

    const ProjectFactory = await ethers.getContractFactory("ProjectFactory");
    projectFactory = await ProjectFactory.deploy();
    await projectFactory.waitForDeployment();
  });

  describe("项目创建", function () {
    it("应该成功创建一个有效项目", async function () {
      const projectParams = {
        projectName: "Test Project",
        description: "A test project for testing purposes",
        imageUrl: "https://example.com/test.jpg",
        fundingGoal: ethers.parseEther("5"),
        fundingPeriod: 7 * 24 * 60 * 60, // 7 days
        totalSupply: 1000000,
        crowdsaleAllocation: 50,
        tokenName: "Test Token",
        tokenSymbol: "TEST",
        holderPercentage: 40,
        creatorPercentage: 60,
        dividendThreshold: ethers.parseEther("1")
      };

      const tx = await projectFactory.connect(creator1).createProject(projectParams);
      const receipt = await tx.wait();

      // 获取事件中的crowdsaleContract地址
      const event = receipt.logs.find(log => log.fragment?.name === "ProjectCreated");
      const crowdsaleAddress = event?.args?.crowdsaleContract;

      expect(crowdsaleAddress).to.be.properAddress;

      const projectInfo = await projectFactory.getProject(1);
      expect(projectInfo.projectId).to.equal(1);
      expect(projectInfo.creator).to.equal(creator1.address);
      expect(projectInfo.projectName).to.equal("Test Project");
      expect(projectInfo.active).to.be.true;
    });

    it("应该拒绝无效的项目参数", async function () {
      const invalidParams = {
        projectName: "", // 空名称
        description: "Invalid project",
        imageUrl: "https://example.com/test.jpg",
        fundingGoal: ethers.parseEther("5"),
        fundingPeriod: 7 * 24 * 60 * 60,
        totalSupply: 1000000,
        crowdsaleAllocation: 50,
        tokenName: "Test Token",
        tokenSymbol: "TEST",
        holderPercentage: 40,
        creatorPercentage: 60,
        dividendThreshold: ethers.parseEther("1")
      };

      await expect(
        projectFactory.connect(creator1).createProject(invalidParams)
      ).to.be.revertedWith("Project name is required");
    });
  });

  describe("项目查询", function () {
    beforeEach(async function () {
      const projectParams = {
        projectName: "Test Project",
        description: "A test project",
        imageUrl: "https://example.com/test.jpg",
        fundingGoal: ethers.parseEther("5"),
        fundingPeriod: 7 * 24 * 60 * 60,
        totalSupply: 1000000,
        crowdsaleAllocation: 50,
        tokenName: "Test Token",
        tokenSymbol: "TEST",
        holderPercentage: 40,
        creatorPercentage: 60,
        dividendThreshold: ethers.parseEther("1")
      };

      await projectFactory.connect(creator1).createProject(projectParams);
    });

    it("应该正确返回项目信息", async function () {
      const projectInfo = await projectFactory.getProject(1);

      expect(projectInfo.projectId).to.equal(1);
      expect(projectInfo.creator).to.equal(creator1.address);
      expect(projectInfo.projectName).to.equal("Test Project");
      expect(projectInfo.description).to.equal("A test project");
      expect(projectInfo.active).to.be.true;
      expect(projectInfo.createdAt).to.be.gt(0);
    });

    it("应该返回创作者的项目列表", async function () {
      const creatorProjects = await projectFactory.getCreatorProjects(creator1.address);
      expect(creatorProjects).to.deep.equal([BigInt(1)]);
    });

    it("应该返回所有项目", async function () {
      const allProjects = await projectFactory.getAllProjects();
      expect(allProjects).to.deep.equal([BigInt(1)]);
    });

    it("应该正确统计项目数量", async function () {
      const stats = await projectFactory.getFactoryStats();
      expect(stats.totalProjects).to.equal(1);
      expect(stats.activeProjects).to.equal(1);
      expect(stats.totalCreators).to.equal(1);
    });
  });

  describe("项目更新", function () {
    beforeEach(async function () {
      const projectParams = {
        projectName: "Original Name",
        description: "Original description",
        imageUrl: "https://example.com/test.jpg",
        fundingGoal: ethers.parseEther("5"),
        fundingPeriod: 7 * 24 * 60 * 60,
        totalSupply: 1000000,
        crowdsaleAllocation: 50,
        tokenName: "Test Token",
        tokenSymbol: "TEST",
        holderPercentage: 40,
        creatorPercentage: 60,
        dividendThreshold: ethers.parseEther("1")
      };

      await projectFactory.connect(creator1).createProject(projectParams);
    });

    it("应该允许创作者更新项目信息", async function () {
      await expect(projectFactory.connect(creator1).updateProject(1, "New Name", "New description"))
        .to.emit(projectFactory, "ProjectUpdated")
        .withArgs(1, "New Name", "New description");

      const projectInfo = await projectFactory.getProject(1);
      expect(projectInfo.projectName).to.equal("New Name");
      expect(projectInfo.description).to.equal("New description");
    });

    it("应该拒绝非创作者更新项目", async function () {
      await expect(
        projectFactory.connect(creator2).updateProject(1, "New Name", "New description")
      ).to.be.revertedWith("Only creator can update project");
    });
  });

  describe("项目停用", function () {
    beforeEach(async function () {
      const projectParams = {
        projectName: "Test Project",
        description: "A test project",
        imageUrl: "https://example.com/test.jpg",
        fundingGoal: ethers.parseEther("5"),
        fundingPeriod: 7 * 24 * 60 * 60,
        totalSupply: 1000000,
        crowdsaleAllocation: 50,
        tokenName: "Test Token",
        tokenSymbol: "TEST",
        holderPercentage: 40,
        creatorPercentage: 60,
        dividendThreshold: ethers.parseEther("1")
      };

      await projectFactory.connect(creator1).createProject(projectParams);
    });

    it("应该允许创作者停用项目", async function () {
      await expect(projectFactory.connect(creator1).deactivateProject(1))
        .to.emit(projectFactory, "ProjectDeactivated")
        .withArgs(1);

      const projectInfo = await projectFactory.getProject(1);
      expect(projectInfo.active).to.be.false;
    });

    it("应该拒绝非创作者停用项目", async function () {
      await expect(
        projectFactory.connect(creator2).deactivateProject(1)
      ).to.be.revertedWith("Only creator can deactivate project");
    });
  });

  describe("项目搜索", function () {
    beforeEach(async function () {
      const projectParams1 = {
        projectName: "Cyber Art Project",
        description: "First project",
        imageUrl: "https://example.com/test1.jpg",
        fundingGoal: ethers.parseEther("5"),
        fundingPeriod: 7 * 24 * 60 * 60,
        totalSupply: 1000000,
        crowdsaleAllocation: 50,
        tokenName: "Cyber Token",
        tokenSymbol: "CYBER",
        holderPercentage: 40,
        creatorPercentage: 60,
        dividendThreshold: ethers.parseEther("1")
      };

      const projectParams2 = {
        projectName: "Fantasy Collection",
        description: "Second project",
        imageUrl: "https://example.com/test2.jpg",
        fundingGoal: ethers.parseEther("3"),
        fundingPeriod: 14 * 24 * 60 * 60,
        totalSupply: 500000,
        crowdsaleAllocation: 60,
        tokenName: "Fantasy Token",
        tokenSymbol: "FANTASY",
        holderPercentage: 30,
        creatorPercentage: 70,
        dividendThreshold: ethers.parseEther("1.5")
      };

      await projectFactory.connect(creator1).createProject(projectParams1);
      await projectFactory.connect(creator2).createProject(projectParams2);
    });

    it("应该能够搜索项目", async function () {
      const searchResults = await projectFactory.searchProjects("Cyber");
      expect(searchResults).to.deep.equal([BigInt(1)]);
    });

    it("应该返回空数组如果没有匹配结果", async function () {
      const searchResults = await projectFactory.searchProjects("Nonexistent");
      expect(searchResults).to.deep.equal([]);
    });
  });
});