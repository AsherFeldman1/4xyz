const { expect } = require("chai");
const { ethers } = require("hardhat");
const BN = ethers.BigNumber;
const BONE = BN.from(10).pow(BN.from(18));
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

describe("Static and dynamic tokens", function () {

  it("0 should equal 0", async function () {
    expect(0).to.equal(0);
  });

  it("Before each", async function () {
    const Oracle = await ethers.getContractFactory("RateOracle");
    oracleInstance = await Oracle.deploy();
    const Dummy = await ethers.getContractFactory("DummyToken");
    dummyInstance = await Dummy.deploy();
    const Vaults = await ethers.getContractFactory("FxVaults");
    vaultsInstance = await Vaults.deploy([dummyInstance.address], oracleInstance.address, 1);
    const Static = await ethers.getContractFactory("FxPerpStatic");
    staticInstance = await Static.deploy("Static", "STA", vaultsInstance.address);
    const Dynamic = await ethers.getContractFactory("FxPerpDynamic");
    dynamicInstance = await Dynamic.deploy("Dynamic", "DYN", vaultsInstance.address, staticInstance.address)
    const OrderBook = await ethers.getContractFactory("OrderBook");
    orderBookInstance = await OrderBook.deploy([dynamicInstance.address], [vaultsInstance.address], [0], [0], dummyInstance.address, oracleInstance.address);
    await staticInstance.setDynamic(dynamicInstance.address);
    await vaultsInstance.setState(staticInstance.address, dynamicInstance.address, orderBookInstance.address);
    accounts = await ethers.getSigners();
  });

  it("Should get static tokens from vault", async function () {
    await oracleInstance.setPrice(BONE);
    await vaultsInstance.connect(accounts[0]).openVault(0);
    await dummyInstance.connect(accounts[0]).mint(BN.from(10).mul(BONE));
    await dummyInstance.connect(accounts[0]).approve(vaultsInstance.address, BN.from(5).mul(BONE));
    await vaultsInstance.connect(accounts[0]).supply(0, BN.from(5).mul(BONE));
    await vaultsInstance.connect(accounts[0]).borrow(0, BN.from(2).mul(BONE));
    expect(await staticInstance.balanceOf(accounts[0].address)).to.equal(BN.from(2).mul(BONE));
  });

  it("Should transfer tokens from one account to another", async function () {
    await staticInstance.connect(accounts[0]).transfer(accounts[1].address, BN.from(2).mul(BONE));
    expect(await staticInstance.balanceOf(accounts[0].address)).to.equal(0);
    expect(await staticInstance.balanceOf(accounts[1].address)).to.equal(BN.from(2).mul(BONE));
  });
  
  it("Should revert on port to dynamic", async function () {
    await expect(staticInstance.connect(accounts[1]).portToDynamic(BN.from(3).mul(BONE))).to.be.reverted;
  }) 
  
  it("Should port tokens to dynamic", async function () {
    await staticInstance.connect(accounts[1]).portToDynamic(BN.from(2).mul(BONE));
    expect(await dynamicInstance.balanceOf(accounts[1].address)).to.equal(BN.from(2).mul(BONE));
    expect(await staticInstance.balanceOf(accounts[1].address)).to.equal(0);
  });

  it("Should transfer tokens from one account to another in dynamic tokens", async function () {
    await dynamicInstance.connect(accounts[1]).transfer(accounts[0].address, BN.from(2).mul(BONE));
    expect(await dynamicInstance.balanceOf(accounts[1].address)).to.equal(0);
    expect(await dynamicInstance.balanceOf(accounts[0].address)).to.equal(BN.from(2).mul(BONE));
  });

  it("Should revert on port back to static", async function () {
    await expect(dynamicInstance.connect(accounts[0]).portToStatic(BN.from(3).mul(BONE))).to.be.reverted;
  });

  it("Should port tokens from dynamic back to static", async function () {
    await dynamicInstance.connect(accounts[0]).portToStatic(BN.from(2).mul(BONE));
    expect(await dynamicInstance.balanceOf(accounts[0].address)).to.equal(0);
    expect(await staticInstance.balanceOf(accounts[0].address)).to.equal(BN.from(2).mul(BONE));
  });
});