// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

interface IOrderBook {
	function limitBuy(uint _tokenIndex, uint _price, uint _volume, uint _targetInsertion) external returns(uint);
	function limitSell(uint _tokenIndex, uint _price, uint _volume, uint _targetInsertion) external returns(uint);
	function marketSell(uint _tokenIndex, uint _minPrice, uint _volume) external returns(uint);
	function marketBuy(uint _tokenIndex, uint _maxPrice, uint _volume) external returns(uint);
	function modifyBuy(uint _ID, uint _newPrice, uint _newVolume) external;
	function modifySell(uint _ID, uint _newPrice, uint _newVolume) external;
	function deleteBuy(uint _ID) external;
	function deleteSell(uint _ID) external;
	function getBuy(uint _ID) external view returns(address maker, uint index, uint id, uint price, uint volume, uint next, uint prev);
	function getSell(uint _ID) external view returns(address maker, uint index, uint id, uint price, uint volume, uint next, uint prev);
	function getBuyHead(uint _tokenIndex) external view returns(uint);
	function getSellHead(uint _tokenIndex) external view returns(uint);
	function getOpenBuyOrders(uint _tokenIndex) external view returns(uint);
	function getOpenSellOrders(uint _tokenIndex) external view returns(uint);
}