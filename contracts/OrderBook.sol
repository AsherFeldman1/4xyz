pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/SignedSafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Stablecoins/FiatRateOracle.sol";

contract OrderBook is Ownable {
	
	using SafeMath for uint256;
	using SignedSafeMath for int256;

	IERC20 internal USD;

	FiatRateOracle internal Oracle;

	address[] public FxPerpetuals;

	int[] public fundingRates;
	uint[] public prices;
	uint[] public buyHeads;
	uint[] public sellHeads;
	uint[] public openBuyOrders;
	uint[] public openSellOrders;
	uint[][] internal recentSales;
	uint[] internal lastSalesUpdates;
	uint[] internal salesIndecesToSet;

	uint internal buyID;
	uint internal sellID;

	uint internal constant BONE = 1e18;

	uint internal lastFundingRateCalculation;

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

	constructor(address[] memory _FxPerpetuals, uint[] memory _baseTokenInfoArray,
	int[] memory _fundingRateBaseArray, uint[][] memory _recentSalesBaseArray, address _USD, address _Oracle) {
		FxPerpetuals = _FxPerpetuals;
		USD = IERC20(_USD);
		Oracle = FiatRateOracle(_Oracle);
		fundingRates = _fundingRateBaseArray;
		prices = _baseTokenInfoArray;
		buyHeads = _baseTokenInfoArray;
		sellHeads = _baseTokenInfoArray;
		openBuyOrders = _baseTokenInfoArray;
		openSellOrders = _baseTokenInfoArray;
		lastSalesUpdates = _baseTokenInfoArray;
		salesIndecesToSet = _baseTokenInfoArray;
		recentSales = _recentSalesBaseArray;

	}

	modifier calculatePrice(uint _tokenIndex) {
		uint total;
		for (uint i = 0; i < 5; i++) {
			total = total.add(recentSales[_tokenIndex][i]);
		}
		prices[_tokenIndex] = total.div(5);
		_;
	}

	modifier checkFundingRateCalculation() {
		if (block.timestamp >= lastFundingRateCalculation.add(28800)) {
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

	function marketSell(uint _tokenIndex, uint _minPrice, uint _volume) public calculatePrice(_tokenIndex) returns(uint) {
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

	function marketBuy(uint _tokenIndex, uint _maxPrice, uint _volume) public calculatePrice(_tokenIndex) returns(uint) {
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

	function updateSalesList(uint _tokenIndex, uint _newDataPoint) internal {
		if (salesIndecesToSet[_tokenIndex] < 5) {
			recentSales[_tokenIndex][salesIndecesToSet[_tokenIndex]] = _newDataPoint;
		} else {
			recentSales[_tokenIndex][0] = _newDataPoint;
			salesIndecesToSet[_tokenIndex] = 1;
			return;
		}
		salesIndecesToSet[_tokenIndex]++;
		lastSalesUpdates[_tokenIndex] = block.number;
	}

	function calculateFundingRates() internal {
		for (uint i = 0; i < FxPerpetuals.length; i++) {
			int safeMarkPrice = int(prices[i]);
			int indexPrice = Oracle.getPrice(i);
			int dif = safeMarkPrice.sub(indexPrice);
			int fee = int(BONE).mul(dif).div(indexPrice);
			fundingRates[i] = fee;
		}
	}

	function addFxPerpetual(address _perpetual) public onlyOwner {
		FxPerpetuals.push(_perpetual);
		fundingRates.push(0);
		buyHeads.push(0);
		sellHeads.push(0);
		openBuyOrders.push(0);
		prices.push(0);
		salesIndecesToSet.push(0);
		lastSalesUpdates.push(0);
		recentSales.push([0, 0, 0, 0, 0]);
	}
}