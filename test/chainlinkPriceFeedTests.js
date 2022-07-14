const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const { advanceTime, advanceBlocks } = require("./advanceTime.js");
const BN = ethers.BigNumber;
const BONE = BN.from(10).pow(BN.from(18));
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

describe("Funding rates", function () {

  it("0 should equal 0", async function () {
    expect(0).to.equal(0);
  });

  it("Before each", async function () {
    const Oracle = await ethers.getContractFactory("RateOracle");
    oracleInstance = await upgrades.deployProxy(Oracle, []);
    key = ethers.utils.formatBytes32String("EUR");
    await oracleInstance.addAggregator(key, "0xb49f677943bc038e9857d61e7d053caa2c1734c1");
  });

  it("Should return a value for twap", async function () {
    console.log(await oracleInstance.getTwapPrice(key, BN.from(3600)));
  });
});