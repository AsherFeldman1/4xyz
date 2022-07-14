// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./FxVaults.sol";
import "./FxPerpStatic.sol";
import "hardhat/console.sol";

contract FxPerpDynamic is Initializable, ERC20Upgradeable {

	using SafeMathUpgradeable for uint256;

	address internal vaults;

	FxPerpStatic internal perpStatic;

	uint public DYNAMIC_BALANCE_MULTIPLIER;

	uint internal BONE;

	uint[50] private __gap;

	function initialize(string memory _name, string memory _symbol, address _vaults, address _perpStatic) public initializer {
		vaults = _vaults;
		perpStatic = FxPerpStatic(_perpStatic);
		BONE = 1e18;
		DYNAMIC_BALANCE_MULTIPLIER = 1e18;
		ERC20Upgradeable.__ERC20_init(_name, _symbol);
	}

	function mint(address _account, uint _amount) external {
		require(msg.sender == address(perpStatic));
		_mint(_account, _amount);
	}

	function updateDynamicMultiplier(uint _multiplier) external {
		require(msg.sender == vaults);
		DYNAMIC_BALANCE_MULTIPLIER = _multiplier;
	}

	function portToStatic(uint _staticAmount) external {
		require(_balances[msg.sender] >= _staticAmount);
		_burn(msg.sender, _staticAmount);
		perpStatic.mint(msg.sender, _staticAmount);
	}

	// OVERIDE ERC20

	function balanceOf(address account) public view override returns(uint) {
		return _balances[account].mul(DYNAMIC_BALANCE_MULTIPLIER).div(BONE);
	}

	function allowance(address owner, address spender) public view override returns(uint) {
		return _allowances[owner][spender].mul(DYNAMIC_BALANCE_MULTIPLIER).div(BONE);
	}

	function _mint(address account, uint amount) internal override  {
		uint staticAmount = amount.mul(BONE).div(DYNAMIC_BALANCE_MULTIPLIER);
		super._mint(account, staticAmount);
	}

	function _burn(address account, uint amount) internal override  {
		uint staticAmount = amount.mul(BONE).div(DYNAMIC_BALANCE_MULTIPLIER);
		super._burn(account, staticAmount);
	}

	function _transfer(address from, address to, uint amount) internal override {
		uint staticAmount = amount.mul(BONE).div(DYNAMIC_BALANCE_MULTIPLIER);
		super._transfer(from, to, staticAmount);
	}

	function _approve(address owner, address spender, uint amount) internal override {
		uint staticAmount = amount.mul(BONE).div(DYNAMIC_BALANCE_MULTIPLIER);
		super._approve(owner, spender, staticAmount);
	}
}