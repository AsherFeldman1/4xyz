// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./FxVaults.sol";
import "./FxPerpDynamic.sol";

contract FxPerpStatic is Initializable, ERC20Upgradeable {

	address internal vaults;

	FxPerpDynamic internal perpDynamic;

	bool internal set;

	uint[50] private __gap;

	function initialize(string memory _name, string memory _symbol, address _vaults) public initializer {
		vaults = _vaults;
		ERC20Upgradeable.__ERC20_init(_name, _symbol);
	}

	function setDynamic(address _perpDynamic) external {
		require(!set);
		perpDynamic = FxPerpDynamic(_perpDynamic);
		set = true;
	}

	function burn(address _account, uint _amount) external {
		require(msg.sender == vaults || msg.sender == address(perpDynamic));
		_burn(_account, _amount);
	}

	function mint(address _account, uint _amount) external {
		require(msg.sender == vaults || msg.sender == address(perpDynamic));
		_mint(_account, _amount);
	}

	function portToDynamic(uint _staticAmount) external {
		require(_balances[msg.sender] >= _staticAmount);
		_burn(msg.sender, _staticAmount);
		perpDynamic.mint(msg.sender, _staticAmount);
	}
}