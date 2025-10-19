const { ethers } = require("hardhat");

async function main() {
  console.log("开始部署 PromptDAO 智能合约...");

  // 获取部署账户
  const [deployer] = await ethers.getSigners();
  console.log("部署账户:", deployer.address);
  console.log("账户余额:", ethers.formatEther(await deployer.provider.getBalance(deployer.address)), "ETH");

  try {
    // 1. 部署 ProjectFactory 合约
    console.log("\n正在部署 ProjectFactory 合约...");
    const ProjectFactory = await ethers.getContractFactory("ProjectFactory");
    const projectFactory = await ProjectFactory.deploy();
    await projectFactory.waitForDeployment();

    const factoryAddress = await projectFactory.getAddress();
    console.log("✅ ProjectFactory 部署成功!");
    console.log("地址:", factoryAddress);

    // 2. 创建示例项目进行测试
    console.log("\n正在创建示例项目...");

    const projectParams = {
      projectName: "CyberArt Genesis",
      description: "第一个AI生成的赛博朋克艺术项目，包含100个独特的数字艺术作品",
      imageUrl: "https://example.com/cyberart.jpg",
      fundingGoal: ethers.parseEther("10"), // 10 ETH
      fundingPeriod: 14 * 24 * 60 * 60, // 14天
      totalSupply: 1000000, // 1,000,000 代币
      crowdsaleAllocation: 50, // 50% 用于众筹
      tokenName: "CyberArt Genesis Token",
      tokenSymbol: "CAG",
      holderPercentage: 40, // 40% 给代币持有者
      creatorPercentage: 60, // 60% 给创作者
      dividendThreshold: ethers.parseEther("2") // 2 ETH 分红阈值
    };

    const tx = await projectFactory.createProject(projectParams);
    await tx.wait();

    console.log("✅ 示例项目创建成功!");
    console.log("交易哈希:", tx.hash);

    // 获取项目信息
    const projectCount = await projectFactory.getNextProjectId();
    console.log("项目总数:", projectCount.toString());

    if (projectCount > 0) {
      const projectInfo = await projectFactory.getProject(1);
      console.log("\n项目信息:");
      console.log("- 项目ID:", projectInfo.projectId.toString());
      console.log("- 项目名称:", projectInfo.projectName);
      console.log("- 创作者:", projectInfo.creator);
      console.log("- 众筹合约:", projectInfo.crowdsaleContract);
      console.log("- 创建时间:", new Date(Number(projectInfo.createdAt) * 1000).toLocaleString());
    }

    // 输出部署信息
    console.log("\n🎉 部署完成!");
    console.log("\n📋 部署摘要:");
    console.log("=====================================");
    console.log("ProjectFactory 地址:", factoryAddress);
    console.log("部署者地址:", deployer.address);
    console.log("网络:", await deployer.provider.getNetwork());
    console.log("=====================================");

    console.log("\n📝 前端配置:");
    console.log("将以下地址添加到前端配置中:");
    console.log(`NEXT_PUBLIC_FACTORY_ADDRESS=${factoryAddress}`);

  } catch (error) {
    console.error("❌ 部署失败:", error);
    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });