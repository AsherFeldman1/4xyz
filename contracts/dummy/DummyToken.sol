pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract DummyToken is Initializable, ERC20Upgradeable {

	function initialize() public initializer {
		ERC20Upgradeable.__ERC20_init("DummyToken", "DT");
	}

	function mint(uint _amount) external {
		_mint(msg.sender, _amount);
	}
}