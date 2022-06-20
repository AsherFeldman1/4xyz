const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Greeter", function () {

  it("Before each", async function () {
    const Oracle = await ethers.getContractFactory("RateOracle");
    const oracle = await Oracle.deploy()
    const AUD = await ethers.getContractFactory("FxAUD");
    const aud = await AUD.deploy()
  });

  it("0 should equal 0", async function () {
    expect(0).to.equal(0);
  });

  it("0 should equal 0", async function () {
    const AUD = await ethers.getContractFactory("FxAUD");
    const greeter = await Greeter.deploy("Hello, world!");
    await greeter.deployed();

    expect(await greeter.greet()).to.equal("Hello, world!");

    const setGreetingTx = await greeter.setGreeting("Hola, mundo!");

    // wait until the transaction is mined
    await setGreetingTx.wait();

    expect(await greeter.greet()).to.equal("Hola, mundo!");
  });

});
