pragma solidity ^0.8.4;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract FiatRateOracle is Ownable {

	AggregatorV3Interface[] internal oracles;

	constructor(address[] memory _oracles) {
		for (uint i = 0; i < _oracles.length; i++) {
			oracles.push(AggregatorV3Interface(_oracles[i]));
		}
	}

	function getPrice(uint _oracleIndex) public view returns(int) {
        (
            /*uint80 roundID*/,
            int price,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = oracles[_oracleIndex].latestRoundData();
        return price;
	}

	function addOracle(address _oracle) public onlyOwner {
		oracles.push(AggregatorV3Interface(_oracle));
	}
}