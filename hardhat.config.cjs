require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: { enabled: true, runs: 200 },
      viaIR: true
    }
  },
  networks: {
    tempo: {
      url: "https://rpc.tempo.xyz",
      chainId: 4217,
      accounts: [process.env.PRIVATE_KEY]
    }
  }
};
