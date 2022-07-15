// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../RateOracle.sol";
import "./FxPerpStatic.sol";
import "./FxPerpDynamic.sol";

contract FxVaults is Initializable {

	using SafeMathUpgradeable for uint256;

	uint internal vaultID;

	uint internal debtTokenIndex;

	uint internal BONE;
	uint internal MAX_DEBT_RATIO;

	uint public DYNAMIC_DEBT_MULTIPLIER;

	address[] public collateralWhitelist;
	bytes32[] public priceFeedKeys;

	address public owner;

	address internal OrderBook;

	bool internal set;

	FxPerpDynamic internal perpDynamic;

	RateOracle internal oracle;

	FxPerpStatic internal perpStatic;

	Vault[] public Vaults;

	mapping(uint => bool) public isClosed;

	struct Vault {
		address Owner;
		uint CollateralIndex;
		uint Collateral;
		uint Debt;
		uint ID;
	}

	uint[50] private __gap;

	function initialize(address[] memory _collateralWhitelist, bytes32[] memory _priceFeedKeys,
	 address _oracle, uint _debtTokenIndex) public virtual initializer {
		oracle = RateOracle(_oracle);
		debtTokenIndex = _debtTokenIndex;
		collateralWhitelist = _collateralWhitelist;
		priceFeedKeys = _priceFeedKeys;
		BONE = 1e18;
		DYNAMIC_DEBT_MULTIPLIER = 1e18;
		MAX_DEBT_RATIO = 9e17;
		owner = msg.sender;
	}

	function setState(address _perpStatic, address _perpDynamic, address _OrderBook) external {
		require(!set);
		perpStatic = FxPerpStatic(_perpStatic);
		perpDynamic = FxPerpDynamic(_perpDynamic);
		OrderBook = _OrderBook;
		set = true;
	}

	receive() external payable {}

	modifier onlyVaultOwner(uint _vaultID) {
		Vault memory vault = Vaults[_vaultID];
		require(msg.sender == vault.Owner);
		_;
	}

	modifier vaultNotClosed(uint _vaultID) {
		require(!isClosed[_vaultID]);
		_;
	}

	function openVault(uint _collateralIndex) external returns(uint) {
		require(_collateralIndex < collateralWhitelist.length);
		Vault memory vault = Vault(
			msg.sender,
			_collateralIndex,
			0,
			0,
			vaultID	
		);
		Vaults.push(vault);
		vaultID++;
		return vault.ID;
	}

	function getVault(uint _index) external view returns(address vaultOwner, uint collateralIndex, uint collateral, uint debt, uint id) {
		Vault memory vault = Vaults[_index];
		return (vault.Owner, vault.CollateralIndex, vault.Collateral, vault.Debt, vault.ID);
	}

	function supply(uint _vaultID, uint _amount) external vaultNotClosed(_vaultID) {
		Vault storage vault = Vaults[_vaultID];
		IERC20 collateral = IERC20(collateralWhitelist[vault.CollateralIndex]);
		require(collateral.transferFrom(msg.sender, address(this), _amount));
		vault.Collateral = vault.Collateral.add(_amount);
	}

	function withdraw(uint _vaultID, uint _amount) external virtual onlyVaultOwner(_vaultID) vaultNotClosed(_vaultID) {
		Vault storage vault = Vaults[_vaultID];
		require(vault.Collateral >= _amount);
		uint debt = convertTokenDenomintation(debtTokenIndex, vault.Debt);
		uint newCollateral = convertTokenDenomintation(vault.CollateralIndex, vault.Collateral.sub(_amount));
		require(vaultStateIsValid(debt, newCollateral));
		vault.Collateral = vault.Collateral.sub(_amount);
		IERC20 collateral = IERC20(collateralWhitelist[vault.CollateralIndex]);
		collateral.transfer(msg.sender, _amount);
	}

	function borrow(uint _vaultID, uint _amount) external virtual onlyVaultOwner(_vaultID) vaultNotClosed(_vaultID) {
		Vault storage vault = Vaults[_vaultID];
		uint newDebt = convertTokenDenomintation(debtTokenIndex, vault.Debt.add(_amount));
		uint collateral = convertTokenDenomintation(vault.CollateralIndex, vault.Collateral);
		require(vaultStateIsValid(newDebt, collateral));
		vault.Debt = vault.Debt.add(_amount);
		perpStatic.mint(msg.sender, _amount);
	}

	function repay(uint _vaultID, uint _amount) external vaultNotClosed(_vaultID) {
		Vault storage vault = Vaults[_vaultID];
		require(vault.Debt >= _amount);
		vault.Debt = vault.Debt.sub(_amount);
		perpStatic.burn(msg.sender, _amount);
	}

	function closeVault(uint _vaultID) external onlyVaultOwner(_vaultID) vaultNotClosed(_vaultID) {
		_close(_vaultID);
	}

	function liquidate(uint _vaultID) external vaultNotClosed(_vaultID) {
		require(detectLiquidation(_vaultID));
		_close(_vaultID);
	}

	function _close(uint _vaultID) internal {
		Vault storage vault = Vaults[_vaultID];
		IERC20 collateral = IERC20(collateralWhitelist[vault.CollateralIndex]);
		require(perpStatic.balanceOf(msg.sender) >= vault.Debt);
		perpStatic.burn(msg.sender, vault.Debt);
		collateral.transfer(msg.sender, vault.Collateral);
		delete Vaults[_vaultID];
		isClosed[_vaultID] = true;
	}

	function detectLiquidation(uint _vaultID) internal virtual view returns(bool success) {
		Vault memory vault = Vaults[_vaultID];
		uint debt = convertTokenDenomintation(debtTokenIndex, vault.Debt.mul(DYNAMIC_DEBT_MULTIPLIER).div(BONE));
		uint collateral = convertTokenDenomintation(vault.CollateralIndex, vault.Collateral);
		success = debt.mul(BONE).div(collateral) >= MAX_DEBT_RATIO && debt != 0;
	}

	function vaultStateIsValid(uint _staticDebt, uint _collateral) internal view returns(bool success) {
		uint debt = _staticDebt.mul(DYNAMIC_DEBT_MULTIPLIER).div(BONE);
		success = debt.mul(BONE).div(_collateral) < MAX_DEBT_RATIO;
	}

	function convertTokenDenomintation(uint _tokenIndex, uint _amount) internal view returns(uint _price) {
		uint price = uint(oracle.getPrice(priceFeedKeys[_tokenIndex]));
		_price = price == 0 ? 0 : price.mul(_amount).div(BONE);
	}

	function addCollateralOption(address _collateral, bytes32 _priceFeedKey) external {
		require(msg.sender == owner);
		require(collateralWhitelist.length == priceFeedKeys.length);
		collateralWhitelist.push(_collateral);
		priceFeedKeys.push(_priceFeedKey);
	}

	function updateDynamicMultiplier(uint _fundingRate) external {
		require(msg.sender == OrderBook);
		uint inflatedMultiplier = DYNAMIC_DEBT_MULTIPLIER.mul(_fundingRate);
		DYNAMIC_DEBT_MULTIPLIER = inflatedMultiplier.div(BONE);
		perpDynamic.updateDynamicMultiplier(DYNAMIC_DEBT_MULTIPLIER);
	}
}