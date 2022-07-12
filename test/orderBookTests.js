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
    dummyInstance = await Dummy.deploy();
    const Vaults = await ethers.getContractFactory("FxVaults");
    vaultsInstance = await Vaults.deploy([dummyInstance.address], oracleInstance.address, 1);
    const Static = await ethers.getContractFactory("FxPerpStatic");
    staticInstance = await Static.deploy("Static", "STA", vaultsInstance.address);
    const Dynamic = await ethers.getContractFactory("FxPerpDynamic");
    dynamicInstance = await Dynamic.deploy("Dynamic", "DYN", vaultsInstance.address, staticInstance.address)
    const OrderBook = await ethers.getContractFactory("OrderBook");
    orderBookInstance = await OrderBook.deploy([dynamicInstance.address], [vaultsInstance.address], [0], dummyInstance.address, oracleInstance.address);
    await staticInstance.setDynamic(dynamicInstance.address);
    await vaultsInstance.setState(staticInstance.address, dynamicInstance.address, orderBookInstance.address);
    accounts = await ethers.getSigners();
  });

  it("Should place mint tokens and place a limit order", async function () {
    await oracleInstance.setPrice(BONE);
    await vaultsInstance.connect(accounts[0]).openVault(0);
    await dummyInstance.connect(accounts[0]).mint(BN.from(100).mul(BONE));
    await dummyInstance.connect(accounts[0]).approve(vaultsInstance.address, BN.from(100).mul(BONE));
    await vaultsInstance.connect(accounts[0]).supply(0, BN.from(100).mul(BONE));
    await vaultsInstance.connect(accounts[0]).borrow(0, BN.from(90).mul(BONE));
    await staticInstance.connect(accounts[0]).portToDynamic(BN.from(90).mul(BONE));
    await dynamicInstance.connect(accounts[0]).approve(orderBookInstance.address, BONE);
    await orderBookInstance.connect(accounts[0]).limitSell(0, BN.from(2).mul(BONE), BONE, 0);
    expect(await orderBookInstance.getSellHead(0)).to.equal(1);
    let order = await orderBookInstance.getSell(1);
    expect(order.maker).to.equal(accounts[0].address);
    expect(order.index).to.equal(0);
    expect(order.id).to.equal(1);
    expect(order.price).to.equal(BN.from(2).mul(BONE));
    expect(order.volume).to.equal(BONE);
    expect(order.prev).to.equal(0);
    expect(order.next).to.equal(0);
  });

  it("Should place a more attractive limit sell", async function () {
    await dynamicInstance.connect(accounts[0]).approve(orderBookInstance.address, BONE);
    await orderBookInstance.connect(accounts[0]).limitSell(0, BONE, BONE, 0);
    expect(await orderBookInstance.getSellHead(0)).to.equal(2);
    let order1 = await orderBookInstance.getSell(1);
    let order2 = await orderBookInstance.getSell(2);
    expect(order1.prev).to.equal(2);
    expect(order2.next).to.equal(1);
    expect(await orderBookInstance.openSellOrders(0)).to.equal(2);
  });

  it("Should place least attractive offer", async function () {
    await dynamicInstance.connect(accounts[0]).approve(orderBookInstance.address, BONE);
    await orderBookInstance.connect(accounts[0]).limitSell(0, BONE.mul(BN.from(4)), BONE, 0);
    let order1 = await orderBookInstance.getSell(1);
    let order2 = await orderBookInstance.getSell(2);
    let order3 = await orderBookInstance.getSell(3);
    expect(order1.next).to.equal(3);
    expect(order1.prev).to.equal(2);
    expect(order2.next).to.equal(1);
    expect(order2.prev).to.equal(0);
    expect(order3.next).to.equal(0);
    expect(order3.prev).to.equal(1);
  });

  it("Should insert sell in the middle of list", async function () {
    await dynamicInstance.connect(accounts[0]).approve(orderBookInstance.address, BONE);
    await orderBookInstance.connect(accounts[0]).limitSell(0, BONE.mul(BN.from(3)), BONE, 0);
    let order1 = await orderBookInstance.getSell(1);
    let order2 = await orderBookInstance.getSell(2);
    let order3 = await orderBookInstance.getSell(3);
    let order4 = await orderBookInstance.getSell(4);
    expect(order1.next).to.equal(4);
    expect(order1.prev).to.equal(2);
    expect(order2.next).to.equal(1);
    expect(order2.prev).to.equal(0);
    expect(order3.next).to.equal(0);
    expect(order3.prev).to.equal(4);
    expect(order4.next).to.equal(3);
    expect(order4.prev).to.equal(1);
  });

  it("Should insert with a target insertion", async function () {
    await dynamicInstance.connect(accounts[0]).approve(orderBookInstance.address, BONE);
    await orderBookInstance.connect(accounts[0]).limitSell(0, BONE.mul(BN.from(5)), BONE, 1);
    let order1 = await orderBookInstance.getSell(1);
    let order2 = await orderBookInstance.getSell(2);
    let order3 = await orderBookInstance.getSell(3);
    let order4 = await orderBookInstance.getSell(4);
    let order5 = await orderBookInstance.getSell(5);
    expect(order1.next).to.equal(4);
    expect(order1.prev).to.equal(2);
    expect(order2.next).to.equal(1);
    expect(order2.prev).to.equal(0);
    expect(order3.next).to.equal(5);
    expect(order3.prev).to.equal(4);
    expect(order4.next).to.equal(3);
    expect(order4.prev).to.equal(1);
    expect(order5.next).to.equal(0);
    expect(order5.prev).to.equal(3);
    expect(await orderBookInstance.openSellOrders(0)).to.equal(5);
  });

  it("Should revert on order larger than allowance", async function () {
    await expect(orderBookInstance.connect(accounts[0]).limitSell(0, BONE.mul(BN.from(5)), BONE, 0)).to.be.reverted;
  });

  it("Should revert on order larger than balance", async function () {
    await dynamicInstance.connect(accounts[0]).approve(orderBookInstance.address, BONE.mul(BN.from(100)));
    await expect(orderBookInstance.connect(accounts[0]).limitSell(0, BONE.mul(BN.from(5)), BONE.mul(BN.from(100)), 0)).to.be.reverted;
  });

  it("Should buy the head through market buy", async function () {
    await dummyInstance.connect(accounts[1]).mint(BN.from(100).mul(BONE));
    await dummyInstance.connect(accounts[1]).approve(orderBookInstance.address, BONE);
    let bal = await dummyInstance.balanceOf(accounts[0].address);
    let bal2 = await dummyInstance.balanceOf(accounts[1].address);
    let bal3 = await dynamicInstance.balanceOf(accounts[1].address);
    let bal4 = await dynamicInstance.balanceOf(orderBookInstance.address);
    await orderBookInstance.connect(accounts[1]).marketBuy(0, BONE, BONE);
    let order2 = await orderBookInstance.getSell(2);
    expect(order2.maker.toString()).to.equal(ZERO_ADDRESS);
    expect(order2.index).to.equal(0);
    expect(order2.id).to.equal(0);
    expect(order2.price).to.equal(0);
    expect(order2.volume).to.equal(0);
    expect(order2.prev).to.equal(0);
    expect(order2.next).to.equal(0);
    expect(await orderBookInstance.getSellHead(0)).to.equal(1);
    expect(await dummyInstance.balanceOf(accounts[0].address)).to.equal(bal + BONE);
    expect(await dummyInstance.balanceOf(accounts[1].address)).to.equal(bal2.sub(BONE));
    expect(await dynamicInstance.balanceOf(orderBookInstance.address)).to.equal(bal4.sub(BONE));
    expect(await dynamicInstance.balanceOf(accounts[1].address)).to.equal(bal3 + BONE);
  });

  it("Should buy part of the new head", async function () {
    await dummyInstance.connect(accounts[1]).approve(orderBookInstance.address, BONE);
    let bal = await dummyInstance.balanceOf(accounts[0].address);
    let bal2 = await dummyInstance.balanceOf(accounts[1].address);
    let bal3 = await dynamicInstance.balanceOf(accounts[1].address);
    let bal4 = await dynamicInstance.balanceOf(orderBookInstance.address);
    await orderBookInstance.connect(accounts[1]).marketBuy(0, BONE.mul(BN.from(2)), 100);
    let order1 = await orderBookInstance.getSell(1);
    expect(order1.volume).to.equal(BONE.sub(BN.from(100)));
    expect(await dummyInstance.balanceOf(accounts[0].address)).to.equal(bal.add(BN.from(200)));
    expect(await dummyInstance.balanceOf(accounts[1].address)).to.equal(bal2.sub(BN.from(200)));
    expect(await dynamicInstance.balanceOf(orderBookInstance.address)).to.equal(bal4.sub(BN.from(100)));
    expect(await dynamicInstance.balanceOf(accounts[1].address)).to.equal(bal3.add(BN.from(100)));
  });

  it("Should buy through multiple sell orders", async function () {
    await dummyInstance.connect(accounts[1]).approve(orderBookInstance.address, BONE.mul(BN.from(30)));
    await orderBookInstance.connect(accounts[1]).marketBuy(0, BONE.mul(BN.from(5)), BONE.mul(BN.from(3)));
    expect(await orderBookInstance.openSellOrders(0)).to.equal(1);
    expect(await orderBookInstance.sellHeads(0)).to.equal(5);
  });

  it("Should place a buy order then place a limit sell that matches it exactly", async function () {
    await dummyInstance.connect(accounts[1]).approve(orderBookInstance.address, BONE);
    await orderBookInstance.connect(accounts[1]).limitBuy(0, BONE, BONE, 0);
    let order1 = await orderBookInstance.getBuy(1);
    expect(await orderBookInstance.getBuyHead(0)).to.equal(1);
    expect(order1.volume).to.equal(BONE);
    await dynamicInstance.connect(accounts[0]).approve(orderBookInstance.address, BONE);
    let id = await orderBookInstance.sellID();
    await orderBookInstance.connect(accounts[0]).limitSell(0, BONE, BONE, 0);
    let id2 = await orderBookInstance.sellID();
    order1 = await orderBookInstance.getBuy(1);
    expect(order1.volume).to.equal(0);
    expect(id).to.equal(id2);
  });

  it("Should place a buy order then place a limit sell that matches it partially", async function () {
    await dummyInstance.connect(accounts[1]).approve(orderBookInstance.address, BONE.mul(BN.from(3)));
    await orderBookInstance.connect(accounts[1]).limitBuy(0, BONE, BONE.mul(BN.from(3)), 0);
    let order2 = await orderBookInstance.getBuy(2);
    expect(await orderBookInstance.getBuyHead(0)).to.equal(2);
    expect(order2.volume).to.equal(BONE.mul(BN.from(3)));
    await dynamicInstance.connect(accounts[0]).approve(orderBookInstance.address, BONE);
    let id = await orderBookInstance.sellID();
    await orderBookInstance.connect(accounts[0]).limitSell(0, BONE, BONE, 0);
    let id2 = await orderBookInstance.sellID();
    order2 = await orderBookInstance.getBuy(2);
    expect(order2.volume).to.equal(BONE.mul(BN.from(2)));
    expect(id).to.equal(id2);
    await orderBookInstance.connect(accounts[1]).deleteBuy(2);
  });

  it("Should place a buy order then place a limit sell that matches it and some", async function () {
    await dummyInstance.connect(accounts[1]).approve(orderBookInstance.address, BONE);
    await orderBookInstance.connect(accounts[1]).limitBuy(0, BONE, BONE, 0);
    let order3 = await orderBookInstance.getBuy(3);
    expect(order3.volume).to.equal(BONE);
    await dynamicInstance.connect(accounts[0]).approve(orderBookInstance.address, BONE.mul(BN.from(3)));
    await orderBookInstance.connect(accounts[0]).limitSell(0, BONE, BONE.mul(BN.from(3)), 0);
    order3 = await orderBookInstance.getBuy(3);
    let order6 = await orderBookInstance.getSell(6);
    expect(order6.volume).to.equal(BONE.mul(BN.from(2)));
    expect(order3.volume).to.equal(0);
    await orderBookInstance.connect(accounts[0]).deleteSell(6);
    await orderBookInstance.connect(accounts[0]).deleteSell(5);
    expect(await orderBookInstance.openSellOrders(0)).to.equal(0);
    expect(await orderBookInstance.openBuyOrders(0)).to.equal(0);
  });

  it("Should place a sell order then place a limit buy that matches it exactly", async function () {
    await dynamicInstance.connect(accounts[0]).approve(orderBookInstance.address, BONE);
    await orderBookInstance.connect(accounts[0]).limitSell(0, BONE, BONE, 0);
    let order7 = await orderBookInstance.getSell(7);
    expect(order7.volume).to.equal(BONE);
    await dummyInstance.connect(accounts[1]).approve(orderBookInstance.address, BONE);
    let id = await orderBookInstance.buyID();
    await orderBookInstance.connect(accounts[1]).limitBuy(0, BONE, BONE, 0);
    let id2 = await orderBookInstance.buyID();
    order7 = await orderBookInstance.getSell(7);
    expect(order7.volume).to.equal(0);
    expect(id).to.equal(id2);
  });

  it("Should place a sell order then place a limit buy that matches it partially", async function () {
    await dynamicInstance.connect(accounts[0]).approve(orderBookInstance.address, BONE.mul(BN.from(3)));
    await orderBookInstance.connect(accounts[0]).limitSell(0, BONE, BONE.mul(BN.from(3)), 0);
    let order8 = await orderBookInstance.getSell(8);
    expect(order8.volume).to.equal(BONE.mul(BN.from(3)));
    await dummyInstance.connect(accounts[1]).approve(orderBookInstance.address, BONE);
    let id = await orderBookInstance.buyID();
    await orderBookInstance.connect(accounts[1]).limitBuy(0, BONE, BONE, 0);
    let id2 = await orderBookInstance.buyID();
    order8 = await orderBookInstance.getSell(8);
    expect(order8.volume).to.equal(BONE.mul(BN.from(2)));
    expect(id).to.equal(id2);
    await orderBookInstance.connect(accounts[0]).deleteSell(8);
  });

  it("Should place a sell order then place a limit buy that matches it and some", async function () {
    await dynamicInstance.connect(accounts[0]).approve(orderBookInstance.address, BONE);
    await orderBookInstance.connect(accounts[0]).limitSell(0, BONE, BONE, 0);
    let order9 = await orderBookInstance.getSell(9);
    expect(order9.volume).to.equal(BONE);
    await dummyInstance.connect(accounts[1]).approve(orderBookInstance.address, BONE.mul(BN.from(3)));
    await orderBookInstance.connect(accounts[1]).limitBuy(0, BONE, BONE.mul(BN.from(3)), 0);
    order9 = await orderBookInstance.getSell(9);
    expect(order9.volume).to.equal(0);
    order4 = await orderBookInstance.getBuy(4);
    expect(order4.volume).to.equal(BONE.mul(BN.from(2)));
    expect(await orderBookInstance.getBuyHead(0)).to.equal(4);
    await orderBookInstance.connect(accounts[1]).deleteBuy(4);
    expect(await orderBookInstance.getBuyHead(0)).to.equal(0);
  });

  it("Should place mint tokens and place a limit order", async function () {
    await dummyInstance.connect(accounts[1]).approve(orderBookInstance.address, BONE);
    await orderBookInstance.connect(accounts[1]).limitBuy(0, BONE, BONE, 0);
    expect(await orderBookInstance.getBuyHead(0)).to.equal(5);
    let order = await orderBookInstance.getBuy(5);
    expect(order.maker).to.equal(accounts[1].address);
    expect(order.index).to.equal(0);
    expect(order.id).to.equal(5);
    expect(order.price).to.equal(BONE);
    expect(order.volume).to.equal(BONE);
    expect(order.prev).to.equal(0);
    expect(order.next).to.equal(0);
  });

  it("Should place a more attractive limit buy", async function () {
    await dummyInstance.connect(accounts[1]).approve(orderBookInstance.address, BONE.mul(BN.from(2)));
    await orderBookInstance.connect(accounts[1]).limitBuy(0, BONE.mul(BN.from(2)), BONE, 0);
    expect(await orderBookInstance.getBuyHead(0)).to.equal(6);
    let order1 = await orderBookInstance.getBuy(5);
    let order2 = await orderBookInstance.getBuy(6);
    expect(order1.prev).to.equal(6);
    expect(order2.next).to.equal(5);
    expect(await orderBookInstance.openBuyOrders(0)).to.equal(2);
  });

  it("Should place least attractive offer", async function () {
    await dummyInstance.connect(accounts[1]).approve(orderBookInstance.address, BONE);
    await orderBookInstance.connect(accounts[1]).limitBuy(0, BONE.div(BN.from(3)), BONE, 0);
    let order1 = await orderBookInstance.getBuy(5);
    let order2 = await orderBookInstance.getBuy(6);
    let order3 = await orderBookInstance.getBuy(7);
    expect(order1.next).to.equal(7);
    expect(order1.prev).to.equal(6);
    expect(order2.next).to.equal(5);
    expect(order2.prev).to.equal(0);
    expect(order3.next).to.equal(0);
    expect(order3.prev).to.equal(5);
  });

  it("Should insert buy in the middle of list", async function () {
    await dummyInstance.connect(accounts[1]).approve(orderBookInstance.address, BONE);
    await orderBookInstance.connect(accounts[1]).limitBuy(0, BONE.div(BN.from(2)), BONE, 0);
    let order1 = await orderBookInstance.getBuy(5);
    let order2 = await orderBookInstance.getBuy(6);
    let order3 = await orderBookInstance.getBuy(7);
    let order4 = await orderBookInstance.getBuy(8);
    expect(order1.next).to.equal(8);
    expect(order1.prev).to.equal(6);
    expect(order2.next).to.equal(5);
    expect(order2.prev).to.equal(0);
    expect(order3.next).to.equal(0);
    expect(order3.prev).to.equal(8);
    expect(order4.next).to.equal(7);
    expect(order4.prev).to.equal(5);
  });

  it("Should insert with a target insertion", async function () {
    await dynamicInstance.connect(accounts[1]).approve(orderBookInstance.address, BONE);
    await orderBookInstance.connect(accounts[1]).limitBuy(0, BONE.div(BN.from(5)), BONE, 1);
    let order1 = await orderBookInstance.getBuy(5);
    let order2 = await orderBookInstance.getBuy(6);
    let order3 = await orderBookInstance.getBuy(7);
    let order4 = await orderBookInstance.getBuy(8);
    let order5 = await orderBookInstance.getBuy(9);
    expect(order1.next).to.equal(8);
    expect(order1.prev).to.equal(6);
    expect(order2.next).to.equal(5);
    expect(order2.prev).to.equal(0);
    expect(order3.next).to.equal(9);
    expect(order3.prev).to.equal(8);
    expect(order4.next).to.equal(7);
    expect(order4.prev).to.equal(5);
    expect(order5.next).to.equal(0);
    expect(order5.prev).to.equal(7);
    expect(await orderBookInstance.openBuyOrders(0)).to.equal(5);
  });

  it("Should revert on order larger than allowance", async function () {
    await expect(orderBookInstance.connect(accounts[1]).limitBuy(0, BONE.mul(BN.from(10)), BONE, 0)).to.be.reverted;
  });

  it("Should revert on order larger than balance", async function () {
    await dummyInstance.connect(accounts[1]).approve(orderBookInstance.address, BONE.mul(BN.from(100)));
    await expect(orderBookInstance.connect(accounts[1]).limitBuy(0, BONE, BONE.mul(BN.from(100)), 0)).to.be.reverted;
  });

  it("Should sell to the head through market sell", async function () {
    await dynamicInstance.connect(accounts[0]).approve(orderBookInstance.address, BONE);
    let bal = await dynamicInstance.balanceOf(accounts[0].address);
    let bal2 = await dynamicInstance.balanceOf(accounts[1].address);
    let bal3 = await dummyInstance.balanceOf(accounts[0].address);
    let bal4 = await dummyInstance.balanceOf(orderBookInstance.address);
    await orderBookInstance.connect(accounts[0]).marketSell(0, BONE, BONE);
    let order2 = await orderBookInstance.getBuy(6);
    expect(order2.maker.toString()).to.equal(ZERO_ADDRESS);
    expect(order2.index).to.equal(0);
    expect(order2.id).to.equal(0);
    expect(order2.price).to.equal(0);
    expect(order2.volume).to.equal(0);
    expect(order2.prev).to.equal(0);
    expect(order2.next).to.equal(0);
    expect(await orderBookInstance.getBuyHead(0)).to.equal(5);
    expect(await dynamicInstance.balanceOf(accounts[0].address)).to.equal(bal.sub(BONE));
    expect(await dynamicInstance.balanceOf(accounts[1].address)).to.equal(bal2.add(BONE));
    expect(await dummyInstance.balanceOf(orderBookInstance.address)).to.equal(bal4.sub(BONE.mul(BN.from(2))));
    expect(await dummyInstance.balanceOf(accounts[0].address)).to.equal(bal3.add(BONE.mul(BN.from(2))));
  });

  it("Should sell part of the new head", async function () {
    await dynamicInstance.connect(accounts[0]).approve(orderBookInstance.address, BONE);
    let bal = await dynamicInstance.balanceOf(accounts[0].address);
    let bal2 = await dynamicInstance.balanceOf(accounts[1].address);
    let bal3 = await dummyInstance.balanceOf(accounts[0].address);
    let bal4 = await dummyInstance.balanceOf(orderBookInstance.address);
    await orderBookInstance.connect(accounts[0]).marketSell(0, BONE, 100);
    let order1 = await orderBookInstance.getBuy(5);
    expect(order1.volume).to.equal(BONE.sub(BN.from(100)));
    expect(await dynamicInstance.balanceOf(accounts[0].address)).to.equal(bal.sub(BN.from(100)));
    expect(await dynamicInstance.balanceOf(accounts[1].address)).to.equal(bal2.add(BN.from(100)));
    expect(await dummyInstance.balanceOf(orderBookInstance.address)).to.equal(bal4.sub(BN.from(100)));
    expect(await dummyInstance.balanceOf(accounts[0].address)).to.equal(bal3.add(BN.from(100)));
  });

  it("Should buy through multiple sell orders", async function () {
    await dynamicInstance.connect(accounts[1]).approve(orderBookInstance.address, BONE.mul(BN.from(30)));
    await orderBookInstance.connect(accounts[1]).marketSell(0, BONE.div(BN.from(5)), BONE.mul(BN.from(3)));
    expect(await orderBookInstance.openBuyOrders(0)).to.equal(1);
  });

  it("Should delete buy head", async function () {
    await dummyInstance.connect(accounts[2]).mint(BONE);
    await dummyInstance.connect(accounts[2]).approve(orderBookInstance.address, BONE);
    await orderBookInstance.connect(accounts[2]).limitBuy(0, BONE, BONE, 0);
    expect(await dummyInstance.balanceOf(accounts[2].address)).to.equal(0);
    expect(await orderBookInstance.getBuyHead(0)).to.equal(10);
    await orderBookInstance.connect(accounts[2]).deleteBuy(10);
    expect(await orderBookInstance.getBuyHead(0)).to.equal(9);
    expect(await dummyInstance.balanceOf(accounts[2].address)).to.equal(BONE);
  });

  it("Should delete buy", async function () {
    await dummyInstance.connect(accounts[2]).mint(BONE.div(BN.from(10)));
    await dummyInstance.connect(accounts[2]).approve(orderBookInstance.address, BONE.div(BN.from(10)));
    await orderBookInstance.connect(accounts[2]).limitBuy(0, BONE.div(BN.from(10)), BONE, 0);
    expect(await dummyInstance.balanceOf(accounts[2].address)).to.equal(BONE);
    expect(await orderBookInstance.getBuyHead(0)).to.equal(9);
    await orderBookInstance.connect(accounts[2]).deleteBuy(11);
    expect(await orderBookInstance.getBuyHead(0)).to.equal(9);
    expect(await dummyInstance.balanceOf(accounts[2].address)).to.equal(BONE.add(BONE.div(BN.from(10))));
  });

  it("Should delete sell head", async function () {
    await vaultsInstance.connect(accounts[2]).openVault(0);
    await dummyInstance.connect(accounts[2]).mint(BN.from(100).mul(BONE));
    await dummyInstance.connect(accounts[2]).approve(vaultsInstance.address, BN.from(100).mul(BONE));
    await vaultsInstance.connect(accounts[2]).supply(1, BN.from(100).mul(BONE));
    await vaultsInstance.connect(accounts[2]).borrow(1, BN.from(90).mul(BONE));
    await staticInstance.connect(accounts[2]).portToDynamic(BONE);
    await dynamicInstance.connect(accounts[2]).approve(orderBookInstance.address, BONE);
    await orderBookInstance.connect(accounts[2]).limitSell(0, BONE, BONE, 0);
    expect(await dynamicInstance.balanceOf(accounts[2].address)).to.equal(0);
    expect(await orderBookInstance.getSellHead(0)).to.equal(10);
    await orderBookInstance.connect(accounts[2]).deleteSell(10);
    expect(await orderBookInstance.getSellHead(0)).to.equal(0);
    expect(await dynamicInstance.balanceOf(accounts[2].address)).to.equal(BONE);
  });

  it("Should delete sell", async function () {
    await staticInstance.connect(accounts[2]).portToDynamic(BONE.mul(BN.from(2)));
    await dynamicInstance.connect(accounts[2]).approve(orderBookInstance.address, BONE.mul(BN.from(2)));
    await orderBookInstance.connect(accounts[2]).limitSell(0, BONE, BONE, 0);
    await orderBookInstance.connect(accounts[2]).limitSell(0, BONE.div(BN.from(2)), BONE, 0);
    let bal = await dynamicInstance.balanceOf(accounts[2].address);
    expect(await orderBookInstance.getSellHead(0)).to.equal(12);
    expect(await orderBookInstance.openSellOrders(0)).to.equal(2);
    await orderBookInstance.connect(accounts[2]).deleteSell(11);
    expect(await orderBookInstance.getSellHead(0)).to.equal(12);
    expect(await orderBookInstance.openSellOrders(0)).to.equal(1);
    expect(await dynamicInstance.balanceOf(accounts[2].address)).to.equal(bal.add(BONE));
  })  
});