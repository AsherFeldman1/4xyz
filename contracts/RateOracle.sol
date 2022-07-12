pragma solidity ^0.8.4;

contract RateOracle {

	uint public price;
	uint public price2;
	int public twap;

	function getPrice(uint _id) public view returns(uint) {
		if (_id == 0) {
			return price;
		} else {
			return price2;
		}
	}

	function getTWAP(uint _id) public view returns(int) {
		return twap;
	}

	function setPrice(uint _price) public {
		price = _price;
	}

	function setPrice2(uint _price2) public {
		price2 = _price2;
	}

	function setTWAP(int _twap) public {
		twap = _twap;
	}
}