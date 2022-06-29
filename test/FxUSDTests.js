const { expect } = require("chai");
const { ethers } = require("hardhat");
const BN = ethers.BigNumber;
const BONE = BN.from(10).pow(BN.from(18));
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

describe("Vaults", function () {

  it("0 should equal 0", async function () {
    expect(0).to.equal(0);
  });

  it("Before each", async function () {
    const Oracle = await ethers.getContractFactory("RateOracle");
    oracleInstance = await Oracle.deploy();
    const Dummy = await ethers.getContractFactory("DummyToken");
    dummyInstance = await Dummy.deploy();
    const Vaults = await ethers.getContractFactory("FxUSDVaults");
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

  it("Should mint", async function () {
    await dummyInstance.connect(accounts[0]).mint(10);
    let bal = await dummyInstance.balanceOf(accounts[0].address)
    expect(bal).to.equal(10)
  });

  it("Should open a vault", async function () {
    await vaultsInstance.connect(accounts[0]).openVault(0);
    let vault1 = await vaultsInstance.getVault(0);
    expect(vault1.collateral).to.equal(0);
    expect(vault1.collateralIndex).to.equal(0);
    expect(vault1.debt).to.equal(0);
    expect(vault1.id).to.equal(0);
    expect(vault1.vaultOwner).to.equal(accounts[0].address);
  });

  it("Should try to access vault from different address and revert", async function () {
    await oracleInstance.setPrice(BONE);
    await oracleInstance.setPrice2(BONE);
    await expect(vaultsInstance.connect(accounts[1]).withdraw(0, 1)).to.be.reverted;
  })

  it("Should supply collateral", async function () {
    await dummyInstance.connect(accounts[0]).approve(vaultsInstance.address, 6);
    await vaultsInstance.connect(accounts[0]).supply(0, 6);
    let vault = await vaultsInstance.getVault(0);
    expect(vault.collateral).to.equal(6);
    expect(await dummyInstance.balanceOf(accounts[0].address)).to.equal(4);
  });

  it("Should open another vault", async function () {
    await vaultsInstance.connect(accounts[0]).openVault(0);
    let vault2 = await vaultsInstance.getVault(1);
    expect(vault2.collateral).to.equal(0);
    expect(vault2.collateralIndex).to.equal(0);
    expect(vault2.debt).to.equal(0);
    expect(vault2.id).to.equal(1);
    expect(vault2.vaultOwner).to.equal(accounts[0].address);
  });

  it("Should withdraw from vault", async function () {
    await vaultsInstance.connect(accounts[0]).withdraw(0, 1);
    let vault1 = await vaultsInstance.getVault(0);
    expect(vault1.collateral).to.equal(5);
    expect(await dummyInstance.balanceOf(accounts[0].address)).to.equal(5);
  });

  it("Should withdraw invalid amount from vault", async function () {
    await expect(vaultsInstance.connect(accounts[0]).withdraw(0, 6)).to.be.reverted;
  });

  it("Should borrow invalid amount from vault", async function () {
    await dummyInstance.connect(accounts[0]).mint(10);
    await dummyInstance.connect(accounts[0]).approve(vaultsInstance.address, 5);
    await await vaultsInstance.connect(accounts[0]).supply(0, 5);
    await expect(vaultsInstance.connect(accounts[0]).borrow(0, 9)).to.be.reverted;
  });

  it("Should borrow valid amount from vault", async function () {
    await vaultsInstance.connect(accounts[0]).borrow(0, 3);
    let vault1 = await vaultsInstance.getVault(0);
    expect(vault1.collateral).to.equal(10);
    expect(vault1.debt).to.equal(3);
    expect(await staticInstance.balanceOf(accounts[0].address)).to.equal(3);
  });

  it("Should repay invalid amount", async function () {
     await expect(vaultsInstance.connect(accounts[0]).repay(0, 4)).to.be.reverted;
  })

  it("Should repay 1 token", async function () {
    await vaultsInstance.connect(accounts[0]).repay(0, 1);
    let vault1 = await vaultsInstance.getVault(0);
    expect(vault1.debt).to.equal(2);
    expect(await staticInstance.balanceOf(accounts[0].address)).to.equal(2);
  });

  it("Shouldn't be able to liquidate vault", async function () {
    await vaultsInstance.connect(accounts[1]).openVault(0);
    await dummyInstance.connect(accounts[1]).mint(10);
    await dummyInstance.connect(accounts[1]).approve(vaultsInstance.address, 5);
    await vaultsInstance.connect(accounts[1]).supply(2, 5);
    await vaultsInstance.connect(accounts[1]).borrow(2, 2);
    await expect(vaultsInstance.connect(accounts[1]).liquidate(0)).to.be.reverted;
  });

  it("Should should borrow tokens from different account and change price so liquidation can occur", async function () {
    await oracleInstance.setPrice(BONE.div(10));
    await vaultsInstance.connect(accounts[1]).liquidate(0);
    let vault1 = await vaultsInstance.getVault(0);
    expect(vault1.collateral).to.equal(0);
    expect(vault1.collateralIndex).to.equal(0);
    expect(vault1.debt).to.equal(0);
    expect(vault1.id).to.equal(0);
    expect(vault1.vaultOwner.toString()).to.equal(ZERO_ADDRESS);
    let vault2 = await vaultsInstance.getVault(2);
    expect(vault2.collateral).to.equal(5);
    expect(vault2.collateralIndex).to.equal(0);
    expect(vault2.debt).to.equal(2);
    expect(vault2.id).to.equal(2);
    expect(vault2.vaultOwner).to.equal(accounts[1].address);
    expect(await staticInstance.balanceOf(accounts[1].address)).to.equal(0);
    expect(await dummyInstance.balanceOf(accounts[1].address)).to.equal(15);
  });

  it("Should open a vault borrow and close the vault", async function() {
    await oracleInstance.setPrice(BONE);
    await vaultsInstance.connect(accounts[2]).openVault(0);
    await dummyInstance.connect(accounts[2]).mint(10);
    await dummyInstance.connect(accounts[2]).approve(vaultsInstance.address, 5);
    await vaultsInstance.connect(accounts[2]).supply(3, 5);
    await vaultsInstance.connect(accounts[2]).borrow(3, 2);
    let vault1 = await vaultsInstance.getVault(3);
    expect(vault1.collateral).to.equal(5);
    expect(vault1.collateralIndex).to.equal(0);
    expect(vault1.debt).to.equal(2);
    expect(vault1.id).to.equal(3);
    expect(vault1.vaultOwner).to.equal(accounts[2].address);
    await vaultsInstance.connect(accounts[2]).closeVault(3);
    let vault2 = await vaultsInstance.getVault(3);
    expect(vault2.collateral).to.equal(0);
    expect(vault2.collateralIndex).to.equal(0);
    expect(vault2.debt).to.equal(0);
    expect(vault2.id).to.equal(0);
    expect(vault2.vaultOwner.toString()).to.equal(ZERO_ADDRESS);
    expect(await dummyInstance.balanceOf(accounts[2].address)).to.equal(10);
    expect(await staticInstance.balanceOf(accounts[2].address)).to.equal(0);
  });

});