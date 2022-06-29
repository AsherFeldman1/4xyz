// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./FxVaults.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract FxUSDVaults is FxVaults {

	using SafeMath for uint256;

	constructor(address[] memory _collateralWhitelist, address _oracle, uint _debtTokenIndex)
		FxVaults(_collateralWhitelist, _oracle, _debtTokenIndex) {}

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