pragma solidity ^0.8.4;

contract RateOracle {

	uint public price;
	int public twap;

	function getPrice(uint _id) public view returns(uint) {
		return price;
	}

	function getTWAP(uint _id) public view returns(int) {
		return twap;
	}

	function setPrice(uint _price) public {
		price = _price;
	}

	function setTWAP(int _twap) public {
		twap = _twap;
	}
}