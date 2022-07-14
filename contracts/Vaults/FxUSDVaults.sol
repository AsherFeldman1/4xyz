// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./FxVaults.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract FxUSDVaults is Initializable, FxVaults {

	using SafeMathUpgradeable for uint256;

	function initialize(address[] memory _collateralWhitelist, bytes32[] memory _priceFeedKeys, address _oracle, uint _debtTokenIndex)
		public override initializer {
			FxVaults.initialize(_collateralWhitelist, _priceFeedKeys, _oracle, _debtTokenIndex);
		}

	function withdraw(uint _vaultID, uint _amount) external override onlyVaultOwner(_vaultID) vaultNotClosed(_vaultID) {
		Vault storage vault = Vaults[_vaultID];
		uint newCollateral = convertTokenDenomintation(vault.CollateralIndex, vault.Collateral.sub(_amount));
		uint debt = vault.Debt.mul(DYNAMIC_DEBT_MULTIPLIER).div(BONE);
		require(vaultStateIsValid(debt, newCollateral));
		vault.Collateral = vault.Collateral.sub(_amount);
		IERC20 collateral = IERC20(collateralWhitelist[vault.CollateralIndex]);
		collateral.transfer(msg.sender, _amount);
	}

	function borrow(uint _vaultID, uint _amount) external override onlyVaultOwner(_vaultID) vaultNotClosed(_vaultID) {
		Vault storage vault = Vaults[_vaultID];
		uint newDebt = vault.Debt.add(_amount);
		uint dynamicNewDebt = newDebt.mul(DYNAMIC_DEBT_MULTIPLIER).div(BONE);
		uint collateral = convertTokenDenomintation(vault.CollateralIndex, vault.Collateral);
		require(vaultStateIsValid(dynamicNewDebt, collateral));
		vault.Debt = newDebt;
		perpStatic.mint(msg.sender, _amount);
	}

	function detectLiquidation(uint _vaultID) internal view override returns(bool success) {
		Vault memory vault = Vaults[_vaultID];
		uint collateral = convertTokenDenomintation(vault.CollateralIndex, vault.Collateral);
		uint debt = vault.Debt.mul(DYNAMIC_DEBT_MULTIPLIER).div(BONE);
		success = debt.mul(BONE).div(collateral) >= MAX_DEBT_RATIO && debt != 0;
	}
}