const { ethers } = require("hardhat");

async function main() {
  console.log("开始部署简单的 PromptDAO 智能合约...");

  // 获取部署账户
  const [deployer] = await ethers.getSigners();
  console.log("部署账户:", deployer.address);
  console.log("账户余额:", ethers.formatEther(await deployer.provider.getBalance(deployer.address)), "ETH");

  try {
    // 1. 部署 CreatorToken 合约
    console.log("\n正在部署 CreatorToken 合约...");
    const CreatorToken = await ethers.getContractFactory("CreatorToken");
    const creatorToken = await CreatorToken.deploy(
      "PromptDAO Creator Token",
      "PDCT",
      1000000, // 1M tokens (uint256, not wei)
      deployer.address
    );
    await creatorToken.waitForDeployment();

    const tokenAddress = await creatorToken.getAddress();
    console.log("✅ CreatorToken 部署成功!");
    console.log("地址:", tokenAddress);

    // 2. 部署 Treasury 合约
    console.log("\n正在部署 Treasury 合约...");
    const Treasury = await ethers.getContractFactory("TreasuryContract");
    const treasury = await Treasury.deploy(
      tokenAddress,
      deployer.address,
      40, // 40% 给代币持有者
      60  // 60% 给创作者
    );
    await treasury.waitForDeployment();

    const treasuryAddress = await treasury.getAddress();
    console.log("✅ Treasury 部署成功!");
    console.log("地址:", treasuryAddress);

    // 输出部署信息
    console.log("\n🎉 部署完成!");
    console.log("\n📋 部署摘要:");
    console.log("=====================================");
    console.log("CreatorToken 地址:", tokenAddress);
    console.log("Treasury 地址:", treasuryAddress);
    console.log("部署者地址:", deployer.address);
    console.log("网络:", await deployer.provider.getNetwork());
    console.log("=====================================");

    console.log("\n📝 前端配置:");
    console.log("将以下地址添加到前端配置中:");
    console.log(`NEXT_PUBLIC_TOKEN_ADDRESS=${tokenAddress}`);
    console.log(`NEXT_PUBLIC_TREASURY_ADDRESS=${treasuryAddress}`);

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