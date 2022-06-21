// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/SignedSafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../Vaults/RateOracle.sol";
import "../Vaults/FxBase.sol";

contract OrderBook is Ownable {
	
	using SafeMath for uint256;
	using SignedSafeMath for int256;

	IERC20 internal USD;

	RateOracle internal Oracle;

	address[] public FxPerpetuals;

	uint[] public TWAPs;
	uint[] public buyHeads;
	uint[] public sellHeads;
	uint[] public openBuyOrders;
	uint[] public openSellOrders;
	uint[][] internal recentSales;
	uint[] internal lastSalesUpdates;
	uint[] internal salesIndicesToSet;
	uint[] internal oracleIndices;

	uint internal buyID;
	uint internal sellID;

	uint internal BONE;

	uint internal lastFundingRateCalculation;

	uint internal fundingInterval;

	int internal fundingDivisor;

	mapping(uint => BuyOrder) internal buys;

	mapping(uint => SellOrder) internal sells;

	struct BuyOrder {
		address Maker;
		uint TokenIndex;
		uint ID;
		uint Price;
		uint Volume;
		uint Next;
		uint Prev;
	}

	struct SellOrder {
		address Maker;
		uint TokenIndex;
		uint ID;
		uint Price;
		uint Volume;
		uint Next;
		uint Prev;
	}

	constructor(address[] memory _FxPerpetuals, uint[] memory _baseTokenInfoArray, uint[] memory _oracleIndices,
	uint[][] memory _recentSalesBaseArray, address _USD, address _Oracle) {
		FxPerpetuals = _FxPerpetuals;
		USD = IERC20(_USD);
		Oracle = RateOracle(_Oracle);
		TWAPs = _baseTokenInfoArray;
		buyHeads = _baseTokenInfoArray;
		sellHeads = _baseTokenInfoArray;
		openBuyOrders = _baseTokenInfoArray;
		openSellOrders = _baseTokenInfoArray;
		lastSalesUpdates = _baseTokenInfoArray;
		salesIndicesToSet = _baseTokenInfoArray;
		oracleIndices = _oracleIndices;
		recentSales = _recentSalesBaseArray;
		BONE = 1e18;
		fundingInterval = 3600;
		fundingDivisor = 24;
	}

	modifier checkFundingRateCalculation() {
		if (block.timestamp >= lastFundingRateCalculation.add(fundingInterval)) {
			calculateFundingRates();
		}
		_;
	}

	function limitBuy(uint _tokenIndex, uint _price, uint _volume, uint _targetInsertion) public {
		require(USD.allowance(msg.sender, address(this)) >= _volume.mul(_price));
		uint newVolume;
		if (openSellOrders[_tokenIndex] > 0) {
			newVolume = marketBuy(_tokenIndex, _price, _volume);
			if (newVolume == 0) {
				return;
			}
			USD.transferFrom(msg.sender, address(this), newVolume);
		} else {
			USD.transferFrom(msg.sender, address(this), _volume);
		}
		buyID++;
		BuyOrder memory order = BuyOrder(
			msg.sender,
			_tokenIndex,
			buyID,
			_price,
			newVolume == 0 ? _volume : newVolume,
			0,
			0
		);
		buys[buyID] = order;
		if (openBuyOrders[_tokenIndex] == 0) {
			buyHeads[_tokenIndex] = buyID;
			openBuyOrders[_tokenIndex]++;
			return;
		}
		BuyOrder storage head = buys[buyHeads[_tokenIndex]];
		if (_price > head.Price) {
			buyHeads[_tokenIndex] = order.ID;
			order.Next = head.ID;
			head.Prev = order.ID;
			openBuyOrders[_tokenIndex]++;
			return;
		} else {
			uint curr = head.Next;
			if (curr == 0) {
				head.Next = order.ID;
				order.Prev = head.ID;
				openBuyOrders[_tokenIndex]++;
				return;
			}
			if (buys[_targetInsertion].TokenIndex == _tokenIndex && buys[_targetInsertion].Price > _price) {
				curr = _targetInsertion;
			}
			while (buys[curr].Price > _price) {
				if (buys[curr].Next == 0) {
					break;
				}
				curr = buys[curr].Next;
			}
			if (buys[curr].Next == 0) {
				buys[curr].Next = order.ID;
				order.Prev = curr;
				openBuyOrders[_tokenIndex]++;
				return;
			}
			buys[buys[curr].Prev].Next = order.ID;
			order.Prev = buys[curr].Prev;
			order.Next = curr;
			buys[curr].Prev = order.ID;
			openBuyOrders[_tokenIndex]++;
		}
	}

	function limitSell(uint _tokenIndex, uint _price, uint _volume, uint _targetInsertion) public {
		IERC20 Fiat = IERC20(FxPerpetuals[_tokenIndex]);
		require(Fiat.allowance(msg.sender, address(this)) >= _volume.mul(_price));
		uint newVolume;
		if (openBuyOrders[_tokenIndex] > 0) {
			newVolume = marketSell(_tokenIndex, _price, _volume);
			if (newVolume == 0) {
				return;
			}
			Fiat.transferFrom(msg.sender, address(this), newVolume);
		} else {
			Fiat.transferFrom(msg.sender, address(this), _volume);
		}
		sellID++;
		SellOrder memory order = SellOrder(
			msg.sender,
			_tokenIndex,
			sellID,
			_price,
			newVolume == 0 ? _volume : newVolume,
			0,
			0
		);
		sells[sellID] = order;
		if (openSellOrders[_tokenIndex] == 0) {
			sellHeads[_tokenIndex] = sellID;
			openSellOrders[_tokenIndex]++;
			return;
		}
		SellOrder storage head = sells[sellHeads[_tokenIndex]];
		if (_price < head.Price) {
			sellHeads[_tokenIndex] = order.ID;
			order.Next = head.ID;
			head.Prev = order.ID;
			openSellOrders[_tokenIndex]++;
			return;
		} else {
			uint curr = head.Next;
			if (curr == 0) {
				head.Next = order.ID;
				order.Prev = head.ID;
				openSellOrders[_tokenIndex]++;
				return;
			}
			if (sells[_targetInsertion].TokenIndex == _tokenIndex && sells[_targetInsertion].Price < _price) {
				curr = _targetInsertion;
			}
			while (sells[curr].Price < _price) {
				if (sells[curr].Next == 0) {
					break;
				}
				curr = sells[curr].Next;
			}
			if (sells[curr].Next == 0) {
				sells[curr].Next = order.ID;
				order.Prev = curr;
				openSellOrders[_tokenIndex]++;
				return;
			}
			sells[sells[curr].Prev].Next = order.ID;
			order.Prev = sells[curr].Prev;
			order.Next = curr;
			sells[curr].Prev = order.ID;
			openSellOrders[_tokenIndex]++;
		}
	}

	function marketSell(uint _tokenIndex, uint _minPrice, uint _volume) public returns(uint) {
		IERC20 Fiat = IERC20(FxPerpetuals[_tokenIndex]);
		require(Fiat.allowance(msg.sender, address(this)) >= _volume);
		require(openBuyOrders[_tokenIndex] > 0);
		uint curr = buyHeads[_tokenIndex];
		while (_volume > 0 && buys[curr].Price > _minPrice) {
			BuyOrder storage currOrder = buys[curr];
			if (currOrder.Volume >= _volume) {
				USD.transfer(msg.sender, _volume.mul(currOrder.Price));
				Fiat.transferFrom(msg.sender, currOrder.Maker, _volume);
				currOrder.Volume = currOrder.Volume.sub(_volume);
				if (currOrder.Volume == 0) {
					delete buys[curr];
				}
				if (block.number > lastSalesUpdates[_tokenIndex]) {
					updateSalesList(_tokenIndex, currOrder.Price);
				}
				return 0;
			} else {
				USD.transfer(msg.sender, currOrder.Volume.mul(currOrder.Price));
				Fiat.transferFrom(msg.sender, currOrder.Maker, currOrder.Volume);
				_volume = _volume.sub(currOrder.Volume);

				delete buys[curr];
			}
		}
		return _volume;
	}

	function marketBuy(uint _tokenIndex, uint _maxPrice, uint _volume) public returns(uint) {
		IERC20 Fiat = IERC20(FxPerpetuals[_tokenIndex]);
		require(USD.allowance(msg.sender, address(this)) >= _maxPrice.mul(_volume));
		require(openSellOrders[_tokenIndex] > 0);
		uint curr = sellHeads[_tokenIndex];
		while (_volume > 0 && sells[curr].Price < _maxPrice) {
			SellOrder storage currOrder = sells[curr];
			if (currOrder.Volume >= _volume) {
				USD.transferFrom(msg.sender, currOrder.Maker, _volume.mul(currOrder.Price));
				Fiat.transfer(msg.sender, _volume);
				currOrder.Volume = currOrder.Volume.sub(_volume);
				if (currOrder.Volume == 0) {
					delete sells[curr];
				}
				if (block.number > lastSalesUpdates[_tokenIndex]) {
					updateSalesList(_tokenIndex, currOrder.Price);
				}
				return 0;
			} else {
				USD.transferFrom(msg.sender, currOrder.Maker, currOrder.Volume.mul(currOrder.Price));
				Fiat.transfer(msg.sender, currOrder.Volume);
				_volume = _volume.sub(currOrder.Volume);
				delete sells[curr];
			}
		}
		return _volume;
	}

	function deleteBuy(uint _ID) public {
		require(msg.sender == buys[_ID].Maker);
		require(_ID != buyHeads[buys[_ID].TokenIndex]);
		if (buys[_ID].Prev == 0) {
			deleteBuyHead(buys[_ID].TokenIndex);
		}
		if (buys[_ID].Next == 0) {
			buys[buys[_ID].Prev].Next = 0;
		} else {
			buys[buys[_ID].Prev].Next = buys[_ID].Next;
			buys[buys[_ID].Next].Prev = buys[_ID].Prev;
		}
		delete buys[_ID];
	}

	function deleteSell(uint _ID) public {
		require(msg.sender == sells[_ID].Maker);
		require(_ID != sellHeads[sells[_ID].TokenIndex]);
		if (sells[_ID].Prev == 0) {
			deleteSellHead(sells[_ID].TokenIndex);
		}
		if (sells[_ID].Next == 0) {
			sells[sells[_ID].Prev].Next = 0;
		} else {
			sells[sells[_ID].Prev].Next = sells[_ID].Next;
			sells[sells[_ID].Next].Prev = sells[_ID].Prev;
		}
		delete sells[_ID];
	}

	function deleteBuyHead(uint _tokenIndex) internal {
		uint head = buyHeads[_tokenIndex];
		buyHeads[_tokenIndex] = buys[head].Next;
		buys[buys[head].Next].Prev = 0;
		delete buys[head];
	}

	function deleteSellHead(uint _tokenIndex) internal {
		uint head = sellHeads[_tokenIndex];
		sellHeads[_tokenIndex] = sells[head].Next;
		sells[sells[head].Next].Prev = 0;
		delete sells[head];
	}

	function updateSalesList(uint _tokenIndex, uint _newDataPoint) internal checkFundingRateCalculation {
		if (salesIndicesToSet[_tokenIndex] < recentSales[_tokenIndex].length) {
			recentSales[_tokenIndex][salesIndicesToSet[_tokenIndex]] = _newDataPoint;
		} else {
			recentSales[_tokenIndex].push(_newDataPoint);
		}
		salesIndicesToSet[_tokenIndex]++;
		lastSalesUpdates[_tokenIndex] = block.number;
	}

	function calculateFundingRates() internal {
		for (uint i = 0; i < FxPerpetuals.length; i++) {
			calculateTWAP(i);
			int safeMarkPrice = int(TWAPs[i]);
			int indexPrice = Oracle.getTWAP(oracleIndices[i]);
			int dif = safeMarkPrice.sub(indexPrice);
			int fundingRate = dif.div(fundingDivisor);
			uint absRate = abs(fundingRate);
			uint boneRate = BONE;
			if (fundingRate < 0) {
				boneRate = boneRate.sub(absRate);
			} else {
				boneRate = boneRate.add(absRate);
			}
			FxBase perp = FxBase(payable(FxPerpetuals[i]));
			perp.updateDynamicMultiplier(boneRate);
		}
	}

	function calculateTWAP(uint _tokenIndex) internal {
		uint total;
		for (uint i = 0; i < salesIndicesToSet[_tokenIndex]; i++) {
			total = total.add(recentSales[_tokenIndex][i]);
		}
		TWAPs[_tokenIndex] = total.div(salesIndicesToSet[_tokenIndex]);
		salesIndicesToSet[_tokenIndex] = 0;
	}

	function addFxPerpetual(address _perpetual, uint _oracleIndex) public onlyOwner {
		FxPerpetuals.push(_perpetual);
		oracleIndices.push(_oracleIndex);
		buyHeads.push(0);
		sellHeads.push(0);
		openBuyOrders.push(0);
		TWAPs.push(0);
		salesIndicesToSet.push(0);
		lastSalesUpdates.push(0);
		recentSales.push([0, 0, 0, 0, 0]);
	}

	function abs(int x) private pure returns (uint) {
	    int intX = x >= 0 ? x : -x;
	    return(uint(intX));
	}
}