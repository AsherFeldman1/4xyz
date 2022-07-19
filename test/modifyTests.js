const { expect } = require("chai");
const { ethers } = require("hardhat");
const BN = ethers.BigNumber;
const BONE = BN.from(10).pow(BN.from(18));
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

describe("Order Book", function () {

  it("0 should equal 0", async function () {
    expect(0).to.equal(0);
  });

  it("Before each", async function () {
    const Oracle = await ethers.getContractFactory("RateOracle");
    oracleInstance = await Oracle.deploy();
    const Dummy = await ethers.getContractFactory("DummyToken");
    dummyInstance = await upgrades.deployProxy(Dummy, []);
    const Vaults = await ethers.getContractFactory("FxVaults");
    vaultsInstance = await upgrades.deployProxy(Vaults, [[dummyInstance.address], oracleInstance.address, 1]);
    const Static = await ethers.getContractFactory("FxPerpStatic");
    staticInstance = await upgrades.deployProxy(Static, ["Static", "STA", vaultsInstance.address]);
    const Dynamic = await ethers.getContractFactory("FxPerpDynamic");
    dynamicInstance = await upgrades.deployProxy(Dynamic, ["Dynamic", "DYN", vaultsInstance.address, staticInstance.address])
    const OrderBook = await ethers.getContractFactory("OrderBook");
    orderBookInstance = await upgrades.deployProxy(OrderBook, [[dynamicInstance.address], [vaultsInstance.address], dummyInstance.address, oracleInstance.address]);
    await staticInstance.setDynamic(dynamicInstance.address);
    await vaultsInstance.setState(staticInstance.address, dynamicInstance.address, orderBookInstance.address);
    accounts = await ethers.getSigners();
  });

  it("Should place buy", async function () {
    await dummyInstance.connect(accounts[0]).mint(BN.from(100).mul(BONE));
    await dummyInstance.connect(accounts[0]).approve(orderBookInstance.address, BN.from(100).mul(BONE));
    await orderBookInstance.connect(accounts[0]).limitBuy(0, BN.from(100).mul(BONE), BONE, 0);
    console.log(await orderBookInstance.getBuy(1));
    console.log(await dummyInstance.balanceOf(accounts[0].address));
    console.log(await dummyInstance.balanceOf(orderBookInstance.address));
  })

  it("Should place buy", async function () {
    await dummyInstance.connect(accounts[0]).mint(BN.from(100).mul(BONE));
    await dummyInstance.connect(accounts[0]).approve(orderBookInstance.address, BN.from(100).mul(BONE));
    await orderBookInstance.connect(accounts[0]).limitBuy(0, BN.from(50).mul(BONE), BONE, 0);
    console.log(await orderBookInstance.getBuy(2));
    console.log(await dummyInstance.balanceOf(accounts[0].address));
    console.log(await dummyInstance.balanceOf(orderBookInstance.address));
  })

  it("Should place buy", async function () {
    await dummyInstance.connect(accounts[0]).mint(BN.from(100).mul(BONE));
    await dummyInstance.connect(accounts[0]).approve(orderBookInstance.address, BN.from(100).mul(BONE));
    await orderBookInstance.connect(accounts[0]).limitBuy(0, BN.from(90).mul(BONE), BONE, 0);
    console.log(await orderBookInstance.getBuy(3));
    console.log(await dummyInstance.balanceOf(accounts[0].address));
    console.log(await dummyInstance.balanceOf(orderBookInstance.address));
  })

  it("Should modify buy", async function () {
    await orderBookInstance.connect(accounts[0]).modifyBuy(1, BN.from(10).mul(BONE), BONE);
    console.log(await orderBookInstance.getBuy(1));
    console.log(await dummyInstance.balanceOf(accounts[0].address));
    console.log(await dummyInstance.balanceOf(orderBookInstance.address));
  })
});