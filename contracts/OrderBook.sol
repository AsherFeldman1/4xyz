import "@openzeppelin/contracts/utils/SafeMath.sol";
import "../FxyzStablecoins/FxyzInterface.sol";

contract OrderBook {
	
	using SafeMath for uint256;
	using SafeMath for int;

	FxyzInterface USD;

	address[] public stableCoins;

	int[] public fundingRates;
	uint[] public prices;
	uint[] internal buyHeads;
	uint[] internal sellHeads;
	uint[][] internal recentSales;
	uint[] openBuyOrders;
	uint[] openSellOrders;

	uint buyID;
	uint sellID;

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

	constructor(address[] calldata _stableCoins, address _USD) {
		stableCoins = _stableCoins;
		USD = FxyzInterface(_USD);
	}

	modifier calculatePrice(uint _tokenIndex) {
		_;
		uint total;
		for (uint i = 0; i < 5; i++) {
			total = total.add(recentSales[_tokenIndex][i]);
			prices[_tokenIndex][i] = total.div(5);
		}
	}

	function limitBuy(uint _tokenIndex, uint _price, uint _volume, uint _targetInsertion) public {
		require(USD.allowance(msg.sender, address(this)) >= _volume.mul(_price));
		if (openSellOrders[_tokenIndex] > 0) {
			uint newVolume = marketBuy(_tokenIndex, _price, _volume);
			if (newVolume == 0) {
				return;
			}
			USD.transferFrom(msg.sender, address(this), newVolume);
		} else {
			USD.transferFrom(msg.sender, address(this), _volume);
		}
		buyID++;
		BuyOrder memory order = new BuyOrder(
			msg.sender,
			_tokenIndex,
			buyID,
			_price,
			newVolume,
			0,
			0
		)
		if (openBuyOrders[_tokenIndex] == 0) {
			openBuyOrders[_tokenIndex]++;
			return;
		}
		BuyOrder memory head = buys[buyHeads[_tokenIndex]];
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
				return
			}
			if (buys[_targetInsertion].TokenIndex == _tokenIndex && buys[_targetInsertion].Price > _price) {
				curr = _targetInsertion;
			}
			while (buys[curr].price > _price) {
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
			curr.Prev = order.ID;
			openBuyOrders[_tokenIndex]++;
		}
	}

	function limitSell(uint _tokenIndex, uint _price, uint _volume, uint _targetInsertion) public {
		FxyzInterface Fiat = FxyzInterface(stableCoins[_tokenIndex]);
		require(Fiat.allowance(msg.sender, address(this)) >= _volume.mul(_price));
		if (openBuyOrders[_tokenIndex] > 0) {
			uint newVolume = marketSell(_tokenIndex, _price, _volume);
			if (newVolume == 0) {
				return;
			}
			Fiat.transferFrom(msg.sender, address(this), newVolume);
		} else {
			Fiat.transferFrom(msg.sender, address(this), _volume);
		}
		sellID++;
		SellOrder memory order = new SellOrder(
			msg.sender,
			_tokenIndex,
			sellID,
			_price,
			newVolume,
			0,
			0
		)
		if (openSellOrders[_tokenIndex] == 0) {
			openSellOrders[_tokenIndex]++;
			return;
		}
		SellOrder memory head = sells[sellHeads[_tokenIndex]];
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
				return
			}
			if (sells[_targetInsertion].TokenIndex == _tokenIndex && sells[_targetInsertion].Price < _price) {
				curr = _targetInsertion;
			}
			while (sells[curr].price < _price) {
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
			curr.Prev = order.ID;
			openSellOrders[_tokenIndex]++;
		}
	}

	function marketSell(uint _tokenIndex, uint _minPrice, uint _volume) public returns(uint) {
		FxyzInterface Fiat = FxyzInterface(stableCoins[_tokenIndex]);
		require(Fiat.allowance(msg.sender, address(this)) >= _volume);
		require(openBuyOrders[_tokenIndex] > 0);
		uint curr = buyHeads[_tokenIndex];
		while (_volume > 0 && buys[curr].Price > _minPrice) {
			BuyOrder currOrder = buys[curr];
			if (currOrder.Volume >= _volume) {
				USD.transfer(msg.sender, _volume.mul(currOrder.Price));
				Fiat.transferFrom(msg.sender, currOrder.Maker, _volume);
				currOrder.Volume = currOrder.Volume.sub(_volume);
				if (currOrder.Volume == 0) {
					currOrder.Next = 0;
					currOrder.Prev = 0;
				}
				return 0;
			} else {
				USD.transfer(msg.sender, currOrder.Volume.mul(currOrder.Price));
				Fiat.transferFrom(msg.sender, currOrder.Maker, currOrder.Volume);
				_volume = _volume.sub(currOrder.Volume);
				currOrder.Volume = 0;
				currOrder.Next = 0;
				currOrder.Prev = 0;
			}
		}
		return _volume;
	}

	function marketBuy(uint _tokenIndex, uint _maxPrice, uint _volume) public returns(uint) {
		FxyzInterface Fiat = FxyzInterface(stableCoins[_tokenIndex]);
		require(USD.allowance(msg.sender, address(this)) >= _maxPrice.mul(_volume));
		require(openSellOrders[_tokenIndex] > 0);
		uint curr = sellHeads[_tokenIndex];
		while (_volume > 0 && sells[curr].Price < _maxPrice) {
			SellOrder currOrder = sells[curr];
			if (currOrder.Volume >= _volume) {
				USD.transfer(msg.sender, _volume.mul(currOrder.Price));
				Fiat.transferFrom(msg.sender, currOrder.Maker, _volume);
				currOrder.Volume = currOrder.Volume.sub(_volume);
				if (currOrder.Volume == 0) {
					currOrder.Next = 0;
					currOrder.Prev = 0;
				}
				return 0;
			} else {
				USD.transfer(msg.sender, currOrder.Volume.mul(currOrder.Price));
				Fiat.transferFrom(msg.sender, currOrder.Maker, currOrder.Volume);
				_volume = _volume.sub(currOrder.Volume);
				currOrder.Volume = 0;
				currOrder.Next = 0;
				currOrder.Prev = 0;
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
			buys[_ID].Prev = 0;
		} else {
			buys[buys[_ID].Prev].Next = buys[_ID].Next;
			buys[buys[_ID].Next].Prev = buys[_ID].Prev;
			buys[_ID].Prev = 0;
			buys[_ID].Next = 0;
		}
	}

	function deleteSell(uint _ID) public {
		require(msg.sender == sells[_ID].Maker);
		require(_ID != sellHeads[sells[_ID].TokenIndex]);
		if (sells[_ID].Prev == 0) {
			deleteSellHead(sells[_ID].TokenIndex);
		}
		if (sells[_ID].Next == 0) {
			sells[sells[_ID].Prev].Next = 0;
			sells[_ID].Prev = 0;
		} else {
			sells[sells[_ID].Prev].Next = sells[_ID].Next;
			sells[sells[_ID].Next].Prev = sells[_ID].Prev;
			sells[_ID].Prev = 0;
			sells[_ID].Next = 0;
		}
	}

	function deleteBuyHead(uint _tokenIndex) internal {
		uint head = buyHeads[_tokenIndex];
		buyHeads[_tokenIndex] = buys[head].Next;
		buys[buys[head].Next].Prev = 0;
		buys[head].Next = 0;
	}

	function deleteSellHead(uint _tokenIndex) internal {
		uint head = sellHeads[_tokenIndex];
		sellHeads[_tokenIndex] = sells[head].Next;
		sells[sells[head].Next].Prev = 0;
		sells[head].Next = 0;
	}

	function calculateFundingRate() public {
		require(lastFundingRateCalculation + 28800 <= block.timestamp);
	}
}