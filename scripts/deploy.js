const { ethers } = require("hardhat");

async function main() {
  const USDC = "0x20c000000000000000000000b9537d11c60e8b50";

  console.log("正在部署 TempoUSDCLaunch...");

  const Launch = await ethers.getContractFactory("TempoUSDCLaunch");
  const launch = await Launch.deploy(USDC);
  await launch.deployed();

  console.log("✅ 合约地址:", launch.address);
}

main().catch((e) => { console.error(e); process.exit(1); });
