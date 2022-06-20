// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./FxBase.sol";

contract FxAUD is FxBase {

	constructor(address[] memory _collateralOptions, address _oracle, address _OrderBook,
	uint _debtTokenIndex, string memory _name, string memory _symbol) FxBase(_collateralOptions, _oracle, _OrderBook, _debtTokenIndex, _name, _symbol) {}

}