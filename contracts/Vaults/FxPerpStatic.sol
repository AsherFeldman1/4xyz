// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./FxVaults.sol";
import "./FxPerpDynamic.sol";

contract FxPerpStatic is ERC20 {

	address internal vaults;

	FxPerpDynamic internal perpDynamic;

	bool internal set;

	constructor(string memory _name, string memory _symbol, address _vaults) ERC20(_name, _symbol) {
		vaults = _vaults;
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