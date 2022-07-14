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
    const Dummy = await ethers.getContractFactory("DummyToken");
    dummyInstance = await upgrades.deployProxy(Dummy, []);
    const Vaults = await ethers.getContractFactory("FxVaults");
    vaultsInstance = await upgrades.deployProxy(Vaults, [[dummyInstance.address], oracleInstance.address, 1]);
    const Static = await ethers.getContractFactory("FxPerpStatic");
    staticInstance = await upgrades.deployProxy(Static, ["Static", "STA", vaultsInstance.address]);
    const Dynamic = await ethers.getContractFactory("FxPerpDynamic");
    dynamicInstance = await upgrades.deployProxy(Dynamic, ["Dynamic", "DYN", vaultsInstance.address, staticInstance.address])
    const OrderBook = await ethers.getContractFactory("OrderBook");
    orderBookInstance = await upgrades.deployProxy(OrderBook, [[dynamicInstance.address], [vaultsInstance.address], [0], dummyInstance.address, oracleInstance.address]);
    await staticInstance.setDynamic(dynamicInstance.address);
    await vaultsInstance.setState(staticInstance.address, dynamicInstance.address, orderBookInstance.address);
    accounts = await ethers.getSigners();
  });

  it("Should affect price cumulative", async function () {
    await oracleInstance.setPrice(BONE);
    await oracleInstance.setTWAP(BONE);
    await vaultsInstance.connect(accounts[0]).openVault(0);
    await dummyInstance.connect(accounts[0]).mint(BN.from(100).mul(BONE));
    await dummyInstance.connect(accounts[0]).approve(vaultsInstance.address, BN.from(100).mul(BONE));
    await vaultsInstance.connect(accounts[0]).supply(0, BN.from(50).mul(BONE));
    await vaultsInstance.connect(accounts[0]).borrow(0, BN.from(40).mul(BONE));
    await staticInstance.connect(accounts[0]).portToDynamic(BN.from(40).mul(BONE));
    await dynamicInstance.connect(accounts[0]).approve(orderBookInstance.address, BONE);
    await orderBookInstance.connect(accounts[0]).limitSell(0, BN.from(2).mul(BONE), BONE, 0);
    await dummyInstance.connect(accounts[0]).approve(orderBookInstance.address, BN.from(2).mul(BONE));
    await orderBookInstance.connect(accounts[0]).marketBuy(0, BN.from(2).mul(BONE), BONE);
    expect(await orderBookInstance.priceCumulative(0)).to.equal(BONE.mul(BN.from(2)));
  });

  it("Should not affect price cumulative because not enough time has passed", async function () {
    await oracleInstance.setPrice(BONE);
    await dynamicInstance.connect(accounts[0]).approve(orderBookInstance.address, BONE);
    await orderBookInstance.connect(accounts[0]).limitSell(0, BN.from(2).mul(BONE), BONE, 0);
    await dummyInstance.connect(accounts[0]).approve(orderBookInstance.address, BN.from(2).mul(BONE));
    await orderBookInstance.connect(accounts[0]).marketBuy(0, BN.from(2).mul(BONE), BONE);
    expect(await orderBookInstance.priceCumulative(0)).to.equal(BONE.mul(BN.from(2)));
  });

  it("Should affect price cumulative because enough time has passed", async function () {
    await advanceTime(100);
    await dynamicInstance.connect(accounts[0]).approve(orderBookInstance.address, BONE);
    await orderBookInstance.connect(accounts[0]).limitSell(0, BN.from(3).mul(BONE), BONE, 0);
    await dummyInstance.connect(accounts[0]).approve(orderBookInstance.address, BN.from(3).mul(BONE));
    await orderBookInstance.connect(accounts[0]).marketBuy(0, BN.from(3).mul(BONE), BONE);
    expect(await orderBookInstance.priceCumulative(0)).to.equal(BONE.mul(BN.from(5)));
    expect(await orderBookInstance.totalPriceDataPoints(0)).to.equal(2);
  });

  it("Should have expected dynamic multipliers", async function () {
    await advanceTime(3600);
    await dynamicInstance.connect(accounts[0]).approve(orderBookInstance.address, BONE);
    await orderBookInstance.connect(accounts[0]).limitSell(0, BONE.div(BN.from(10)), BONE, 0);
    await dummyInstance.connect(accounts[0]).approve(orderBookInstance.address, BN.from(3).mul(BONE));
    await orderBookInstance.connect(accounts[0]).marketBuy(0, BONE.div(BN.from(10)), BONE);
    expect(await vaultsInstance.DYNAMIC_DEBT_MULTIPLIER()).to.equal(BONE.add(BN.from("62500000000000000")))
    expect(await vaultsInstance.DYNAMIC_DEBT_MULTIPLIER()).to.equal(await dynamicInstance.DYNAMIC_BALANCE_MULTIPLIER());
    expect(await orderBookInstance.priceCumulative(0)).to.equal(BONE.div(BN.from(10)));
    expect(await orderBookInstance.totalPriceDataPoints(0)).to.equal(1);
  });

  it("Should update multiplier again but now lower", async function () {
    let oldMultiplier = await vaultsInstance.DYNAMIC_DEBT_MULTIPLIER();
    await advanceTime(3600);
    await dynamicInstance.connect(accounts[0]).approve(orderBookInstance.address, BONE.add(BN.from(1)));
    await orderBookInstance.connect(accounts[0]).limitSell(0, BONE.div(BN.from(5)), BONE, 0);
    await dummyInstance.connect(accounts[0]).approve(orderBookInstance.address, BN.from(3).mul(BONE));
    await orderBookInstance.connect(accounts[0]).marketBuy(0, BONE.div(BN.from(5)), BONE);
    expect(await vaultsInstance.DYNAMIC_DEBT_MULTIPLIER()).to.be.below(oldMultiplier);
  });
});