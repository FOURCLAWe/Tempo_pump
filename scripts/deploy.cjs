const { ethers } = require("hardhat");

async function main() {
  const USDC = "0x20c000000000000000000000b9537d11c60e8b50";

  console.log("正在部署 TempoUSDCLaunch...");
  
  const [deployer] = await ethers.getSigners();
  console.log("部署账户:", deployer.address);
  
  const balance = await deployer.provider.getBalance(deployer.address);
  console.log("账户余额:", ethers.formatEther(balance));

  const Launch = await ethers.getContractFactory("TempoUSDCLaunch");
  const launch = await Launch.deploy(USDC);
  await launch.waitForDeployment();

  console.log("✅ 合约地址:", await launch.getAddress());
}

main().catch((e) => { console.error(e); process.exit(1); });
