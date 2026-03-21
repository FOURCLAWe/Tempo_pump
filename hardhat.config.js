require("@nomicfoundation/hardhat-toolbox");

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
      url: "https://rpc.tempochain.com",
      chainId: 202411,
      accounts: [process.env.PRIVATE_KEY]
    }
  }
};
