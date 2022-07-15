// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

  // Add aggregators to our oracle contract
  const Oracle = await ethers.getContractFactory("RateOracle");
  oracleInstance = await upgrades.deployProxy(Oracle, []);
  let audKey = ethers.utils.formatBytes32String("AUD");
  await oracleInstance.addAggregator(audKey, "0x77f9710e7d0a19669a13c055f62cd80d313df022")
  let eurKey = ethers.utils.formatBytes32String("EUR");
  await oracleInstance.addAggregator(eurKey, "0xb49f677943bc038e9857d61e7d053caa2c1734c1");
  let cadKey = ethers.utils.formatBytes32String("CAD");
  await oracleInstance.addAggregator(cadKey, "0xa34317db73e77d453b1b8d04550c44d10e981c8e");
  let gbpKey = ethers.utils.formatBytes32String("GBP");
  await oracleInstance.addAggregator(gbpKey, "0x5c0ab2d9b5a7ed9f470386e82bb36a3613cdd4b5");
  let chfKey = ethers.utils.formatBytes32String("CHF");
  await oracleInstance.addAggregator(chfKey, "0x449d117117838ffa61263b61da6301aa2a88b13a");
  let jpyKey = ethers.utils.formatBytes32String("JPY");
  await oracleInstance.addAggregator(jpyKey, "0xbce206cae7f0ec07b545edde332a47c2f75bbeb3");
  let cnyKey = ethers.utils.formatBytes32String("CNY");
  await oracleInstance.addAggregator(cnyKey, "0xef8a4af35cd47424672e3c590abd37fbb7a7759a");
  let krwKey = ethers.utils.formatBytes32String("KRW");
  await oracleInstance.addAggregator(krwKey, "0x01435677fb11763550905594a16b645847c1d0f3");
  let nzdKey = ethers.utils.formatBytes32String("NZD");
  await oracleInstance.addAggregator(nzdKey, "0x3977cfc9e4f29c184d4675f4eb8e0013236e5f3e");
  let brlKey = ethers.utils.formatBytes32String("BRL");
  await oracleInstance.addAggregator(brlKey, "0x971e8f1b779a5f1c36e1cd7ef44ba1cc2f5eee0f");
  let sgdKey = ethers.utils.formatBytes32String("SGD");
  await oracleInstance.addAggregator(sgdKey, "0xe25277ff4bbf9081c75ab0eb13b4a13a721f3e13");
  let tryKey = ethers.utils.formatBytes32String("TRY");
  await oracleInstance.addAggregator(tryKey, "0xb09fc5fd3f11cf9eb5e1c5dba43114e3c9f477b5");
  let zarKey = ethers.utils.formatBytes32String("ZAR");
  await oracleInstance.addAggregator(zarKey, "0x438f81d95761d7036cd2617295827d9d01cf593f");
  let usdKey = ethers.utils.formatBytes32String("USD");
  await oracleInstance.addAggregator(usdKey, "0x8fffffd4afb6115b954bd326cbe7b4ba576818f6");
  let keyArray = [audKey, eurKey, cadKey, gbpKey, chfKey, jpyKey, cnyKey, krwKey, nzdKey, brlKey, sgdKey, tryKey, zarKey];
  let collateralKeyArray = [usdKey, audKey, eurKey, cadKey, gbpKey, chfKey, jpyKey, cnyKey, krwKey, nzdKey, brlKey, sgdKey, tryKey, zarKey];
  let collateralStrings = []

  for (let i = 0; i < collateralKeyArray.length; i++) {
    collateralStrings.push(hre.ethers.utils.parseBytes32String(collateralKeyArray[i]));
  }

  const Vaults = await ethers.getContractFactory("FxUSDVaults");
  let vaultsInstance = await upgrades.deployProxy(Vaults, [[dummyInstance.address], collateralKeyArray, oracleInstance.address, 0]);
  const Static = await ethers.getContractFactory("FxPerpStatic");
  let staticInstance = await upgrades.deployProxy(Static, ["StaticFxUSD", "SFXUSD", vaultsInstance.address]);
  const Dynamic = await ethers.getContractFactory("FxPerpDynamic");
  let dynamicInstance = await upgrades.deployProxy(Dynamic, ["DynamicFxUSD", "DFXUSD", vaultsInstance.address, staticInstance.address]);
  await staticInstance.setDynamic(dynamicInstance.address);

  for (let i = 1; i < collateralKeyArray.length; i++) {
    const Vaults = await ethers.getContractFactory("FxVaults");
    let vaultsInstance1 = await upgrades.deployProxy(Vaults, [[dummyInstance.address], collateralKeyArray, oracleInstance.address, i]);
    const Static = await ethers.getContractFactory("FxPerpStatic");
    let staticInstance1 = await upgrades.deployProxy(Static, [`StaticFx${collateralStrings[i]}`, `SFX${collateralStrings[i]}`, vaultsInstance.address]);
    const Dynamic = await ethers.getContractFactory("FxPerpDynamic");
    let dynamicInstance1 = await upgrades.deployProxy(Dynamic, [`DynamicFx${collateralStrings[i]}`, `DFX${collateralStrings[i]}`, vaultsInstance.address, staticInstance.address]);
    await staticInstance.setDynamic(dynamicInstance.address);
  }


  const OrderBook = await ethers.getContractFactory("OrderBook");
  orderBookInstance = await upgrades.deployProxy(OrderBook, [[dynamicInstance.address], [vaultsInstance.address], keyArray,
  "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", oracleInstance.address]);
  await vaultsInstance.setState(staticInstance.address, dynamicInstance.address, orderBookInstance.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
