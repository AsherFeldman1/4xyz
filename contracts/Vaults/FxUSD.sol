// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./FxBase.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract FxUSD is FxBase {

	using SafeMath for uint256;

	constructor(address[] memory _collateralWhitelist, address _oracle, address _OrderBook, uint _debtTokenIndex, string memory _name, string memory _symbol)
		FxBase(_collateralWhitelist, _oracle, _OrderBook, _debtTokenIndex, _name, _symbol) {}

	function withdraw(uint _vaultID, uint _amount) external override onlyVaultOwner(_vaultID) {
		Vault storage vault = Vaults[_vaultID];
		uint newCollateral = convertTokenDenomintation(vault.CollateralIndex, vault.Collateral.sub(_amount));
		require(vault.Debt.mul(BONE).div(newCollateral) > MIN_DEBT_RATIO);
		vault.Collateral = vault.Collateral.sub(_amount);
	}

	function borrow(uint _vaultID, uint _amount) external override onlyVaultOwner(_vaultID) {
		Vault storage vault = Vaults[_vaultID];
		uint newDebt = vault.Debt.add(_amount);
		uint collateral = convertTokenDenomintation(vault.CollateralIndex, vault.Collateral);
		require(newDebt.mul(BONE).div(collateral) > MIN_DEBT_RATIO);
		_mint(msg.sender, _amount);
		vault.Debt = vault.Debt.add(_amount);
	}

	function detectLiquidation(uint _vaultID) internal view override returns(bool) {
		Vault memory vault = Vaults[_vaultID];
		uint collateral = convertTokenDenomintation(vault.CollateralIndex, vault.Collateral);
		if (vault.Debt.mul(BONE).div(collateral) <= MIN_DEBT_RATIO && (collateral != 0 && vault.Debt != 0)) {
			return true;
		} else {
			return false;
		}
	}
}