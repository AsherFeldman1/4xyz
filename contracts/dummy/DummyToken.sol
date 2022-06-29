pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DummyToken is ERC20("DummyToken", "DT") {

	function mint(uint _amount) external {
		_mint(msg.sender, _amount);
	}
}