// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

interface IFxVaults {
	function openVault(uint _collateralIndex) external returns(uint);
	function getVault(uint _index) external view returns(address vaultOwner, uint collateralIndex, uint collateral, uint debt, uint id, bool closed);
	function getID() external view returns(uint);
	function supply(uint _vaultID, uint _amount) external;
	function withdraw(uint _vaultID, uint _amount) external;
	function borrow(uint _vaultID, uint _amount) external;
	function repay(uint _vaultID, uint _amount) external;
	function closeVault(uint _vaultID) external;
	function liquidate(uint _vaultID) external;
	function detectLiquidation(uint _vaultID) external returns(bool);
}