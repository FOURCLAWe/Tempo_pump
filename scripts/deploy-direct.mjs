import { ethers } from 'ethers';
import { readFileSync } from 'fs';
import * as dotenv from 'dotenv';
dotenv.config();

const USDC = '0x20c000000000000000000000b9537d11c60e8b50';

// 读取编译结果
const abi = JSON.parse(readFileSync('build/contracts_TempoUSDCLaunch_sol_TempoUSDCLaunch.abi', 'utf8'));
const bytecode = '0x' + readFileSync('build/contracts_TempoUSDCLaunch_sol_TempoUSDCLaunch.bin', 'utf8').trim();

// 连接网络
const provider = new ethers.JsonRpcProvider('https://rpc.tempo.xyz');
const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);

console.log('部署账户:', wallet.address);
const balance = await provider.getBalance(wallet.address);
console.log('账户余额:', ethers.formatEther(balance), 'pathUSD');

// 部署合约
const factory = new ethers.ContractFactory(abi, bytecode, wallet);
console.log('正在部署 TempoUSDCLaunch...');

const contract = await factory.deploy(USDC);
console.log('交易已发送:', contract.deploymentTransaction().hash);
console.log('等待确认...');
await contract.waitForDeployment();

const address = await contract.getAddress();
console.log('✅ 合约部署成功！');
console.log('合约地址:', address);
