// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SignedSafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../RateOracle.sol";
import "../Vaults/FxVaults.sol";
import "hardhat/console.sol";

contract OrderBook is Initializable, OwnableUpgradeable {
	
	using SafeMathUpgradeable for uint256;
	using SignedSafeMathUpgradeable for int256;

	IERC20 internal USD;

	RateOracle internal Oracle;

	address[] public FxPerpetuals;
	address[] public Vaults;

	mapping(uint => uint) public buyHeads;
	mapping(uint => uint) public sellHeads;
	mapping(uint => uint) public openBuyOrders;
	mapping(uint => uint) public openSellOrders;
	mapping(uint => uint) public priceCumulative;
	mapping(uint => uint) public lastPriceCumulative;
	mapping(uint => uint) public totalPriceDataPoints;
	mapping(uint => uint) public lastCumulativePriceUpdate;

	uint internal constant CUMULATIVE_UPDATE_THRESHOLD = 30;
	
	bytes32[] internal priceFeedKeys;

	uint public buyID;
	uint public sellID;

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

	uint[50] private __gap;

	function initialize(address[] memory _FxPerpetuals, address[] memory _Vaults, bytes32[] memory _priceFeedKeys,
	address _USD, address _Oracle) public initializer {
		FxPerpetuals = _FxPerpetuals;
		Vaults = _Vaults;
		USD = IERC20(_USD);
		Oracle = RateOracle(_Oracle);
		priceFeedKeys = _priceFeedKeys;
		BONE = 1e18;
		fundingInterval = 3600;
		fundingDivisor = 24;
		lastFundingRateCalculation = block.timestamp;
		OwnableUpgradeable.__Ownable_init();
	}

	modifier checkFundingRateCalculation() {
		if (block.timestamp >= lastFundingRateCalculation.add(fundingInterval)) {
			_calculateFundingRates();
		}
		_;
	}

	function limitBuy(uint _tokenIndex, uint _price, uint _volume, uint _targetInsertion) public {
		require(USD.allowance(msg.sender, address(this)) >= _volume.mul(_price).div(BONE));
		uint newVolume;
		if (openSellOrders[_tokenIndex] > 0) {
			newVolume = marketBuy(_tokenIndex, _price, _volume);
			if (newVolume == 0) {
				return;
			}
			USD.transferFrom(msg.sender, address(this), newVolume.mul(_price).div(BONE));
		} else {
			USD.transferFrom(msg.sender, address(this), _volume.mul(_price).div(BONE));
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
			buys[buyID] = order;
			return;
		} else {
			uint curr = head.Next;
			if (curr == 0) {
				head.Next = order.ID;
				order.Prev = head.ID;
				openBuyOrders[_tokenIndex]++;
				buys[buyID] = order;
				return;
			}
			if (buys[_targetInsertion].TokenIndex == _tokenIndex && buys[_targetInsertion].Price > _price && buys[_targetInsertion].Volume != 0) {
				curr = _targetInsertion;
			}
			while (buys[curr].Price > _price) {
				if (buys[curr].Next == 0) {
					break;
				}
				curr = buys[curr].Next;
			}
			if (buys[curr].Next == 0 && buys[curr].Price > _price) {
				buys[curr].Next = order.ID;
				order.Prev = curr;
				openBuyOrders[_tokenIndex]++;
				buys[buyID] = order;
				return;
			}
			buys[buys[curr].Prev].Next = order.ID;
			order.Prev = buys[curr].Prev;
			order.Next = curr;
			buys[curr].Prev = order.ID;
			openBuyOrders[_tokenIndex]++;
			buys[buyID] = order;
		}
	}

	function limitSell(uint _tokenIndex, uint _price, uint _volume, uint _targetInsertion) public {
		IERC20 Fiat = IERC20(FxPerpetuals[_tokenIndex]);
		require(Fiat.allowance(msg.sender, address(this)) >= _volume);
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
			sells[sellID] = order;
			return;
		} else {
			uint curr = head.Next;
			if (curr == 0) {
				head.Next = order.ID;
				order.Prev = head.ID;
				openSellOrders[_tokenIndex]++;
				sells[sellID] = order;
				return;
			}
			if (sells[_targetInsertion].TokenIndex == _tokenIndex && sells[_targetInsertion].Price < _price && sells[_targetInsertion].Volume != 0) {
				curr = _targetInsertion;
			}
			while (sells[curr].Price < _price) {
				if (sells[curr].Next == 0) {
					break;
				}
				curr = sells[curr].Next;
			}
			if (sells[curr].Next == 0 && sells[curr].Price < _price) {
				sells[curr].Next = order.ID;
				order.Prev = curr;
				openSellOrders[_tokenIndex]++;
				sells[sellID] = order;
				return;
			}
			sells[sells[curr].Prev].Next = order.ID;
			order.Prev = sells[curr].Prev;
			order.Next = curr;
			sells[curr].Prev = order.ID;
			openSellOrders[_tokenIndex]++;
			sells[sellID] = order;
		}
	}

	function marketSell(uint _tokenIndex, uint _minPrice, uint _volume) public returns(uint) {
		IERC20 Fiat = IERC20(FxPerpetuals[_tokenIndex]);
		require(Fiat.allowance(msg.sender, address(this)) >= _volume);
		require(openBuyOrders[_tokenIndex] > 0);
		uint curr = buyHeads[_tokenIndex];
		while (_volume > 0 && buys[curr].Price >= _minPrice && curr != 0) {
			BuyOrder storage currOrder = buys[curr];
			if (currOrder.Volume >= _volume) {
				USD.transfer(msg.sender, _volume.mul(currOrder.Price).div(BONE));
				Fiat.transferFrom(msg.sender, currOrder.Maker, _volume);
				currOrder.Volume = currOrder.Volume.sub(_volume);
				if (block.timestamp > lastCumulativePriceUpdate[_tokenIndex].add(CUMULATIVE_UPDATE_THRESHOLD)) {
					_updatePriceCumulative(_tokenIndex, currOrder.Price);
				}
				if (currOrder.Volume == 0) {
					_deleteBuy(curr);
				}
				return 0;
			} else {
				USD.transfer(msg.sender, currOrder.Volume.mul(currOrder.Price).div(BONE));
				Fiat.transferFrom(msg.sender, currOrder.Maker, currOrder.Volume);
				_volume = _volume.sub(currOrder.Volume);
				uint prevCurr = curr;
				curr = currOrder.Next;
				_deleteBuy(prevCurr);
			}
		}
		return _volume;
	}

	function marketBuy(uint _tokenIndex, uint _maxPrice, uint _volume) public returns(uint) {
		IERC20 Fiat = IERC20(FxPerpetuals[_tokenIndex]);
		require(USD.allowance(msg.sender, address(this)) >= _maxPrice.mul(_volume).div(BONE));
		require(openSellOrders[_tokenIndex] > 0);
		uint curr = sellHeads[_tokenIndex];
		while (_volume > 0 && sells[curr].Price <= _maxPrice && curr != 0) {
			SellOrder storage currOrder = sells[curr];
			if (currOrder.Volume >= _volume) {
				USD.transferFrom(msg.sender, currOrder.Maker, _volume.mul(currOrder.Price).div(BONE));
				Fiat.transfer(msg.sender, _volume);
				currOrder.Volume = currOrder.Volume.sub(_volume);
				if (block.timestamp > lastCumulativePriceUpdate[_tokenIndex].add(CUMULATIVE_UPDATE_THRESHOLD)) {
					_updatePriceCumulative(_tokenIndex, currOrder.Price);
				}
				if (currOrder.Volume == 0) {
					_deleteSell(curr);
				}
				return 0;
			} else {
				USD.transferFrom(msg.sender, currOrder.Maker, currOrder.Volume.mul(currOrder.Price).div(BONE));
				Fiat.transfer(msg.sender, currOrder.Volume);
				_volume = _volume.sub(currOrder.Volume);
				uint prevCurr = curr;
				curr = currOrder.Next;
				_deleteSell(prevCurr);
			}
		}
		return _volume;
	}

	function deleteBuy(uint _ID) public {
		uint amount = buys[_ID].Volume.mul(buys[_ID].Price).div(BONE);
		USD.transfer(msg.sender, amount);
		require(msg.sender == buys[_ID].Maker);
		_deleteBuy(_ID);
	}

	function deleteSell(uint _ID) public {
		IERC20 Fiat = IERC20(FxPerpetuals[sells[_ID].TokenIndex]);
		Fiat.transfer(msg.sender, sells[_ID].Volume);
		require(msg.sender == sells[_ID].Maker);
		_deleteSell(_ID);
	}

	function _deleteSell(uint _ID) internal {
		if (sells[_ID].Prev == 0) {
			deleteSellHead(sells[_ID].TokenIndex);
			return;
		}
		if (sells[_ID].Next == 0) {
			sells[sells[_ID].Prev].Next = 0;
		} else {
			sells[sells[_ID].Prev].Next = sells[_ID].Next;
			sells[sells[_ID].Next].Prev = sells[_ID].Prev;
		}
		delete sells[_ID];
		openSellOrders[sells[_ID].TokenIndex]--;
	}

	function _deleteBuy(uint _ID) internal {
		if (buys[_ID].Prev == 0) {
			deleteBuyHead(buys[_ID].TokenIndex);
			return;
		}
		if (buys[_ID].Next == 0) {
			buys[buys[_ID].Prev].Next = 0;
		} else {
			buys[buys[_ID].Prev].Next = buys[_ID].Next;
			buys[buys[_ID].Next].Prev = buys[_ID].Prev;
		}
		delete buys[_ID];
		openBuyOrders[buys[_ID].TokenIndex]--;
	}

	function deleteBuyHead(uint _tokenIndex) internal {
		uint head = buyHeads[_tokenIndex];
		buyHeads[_tokenIndex] = buys[head].Next;
		buys[buys[head].Next].Prev = 0;
		delete buys[head];
		openBuyOrders[_tokenIndex]--;
	}

	function deleteSellHead(uint _tokenIndex) internal {
		uint head = sellHeads[_tokenIndex];
		sellHeads[_tokenIndex] = sells[head].Next;
		sells[sells[head].Next].Prev = 0;
		delete sells[head];
		openSellOrders[_tokenIndex]--;
	}

	function getBuy(uint _ID) external view returns(address maker, uint index, uint id, uint price, uint volume, uint next, uint prev) {
		BuyOrder memory order = buys[_ID];
		return (
			order.Maker,
			order.TokenIndex,
			order.ID,
			order.Price,
			order.Volume,
			order.Next,
			order.Prev
		);
	}

	function getSell(uint _ID) external view returns(address maker, uint index, uint id, uint price, uint volume, uint next, uint prev) {
		SellOrder memory order = sells[_ID];
		return (
			order.Maker,
			order.TokenIndex,
			order.ID,
			order.Price,
			order.Volume,
			order.Next,
			order.Prev
		);
	}

	function getBuyHead(uint _tokenIndex) external view returns(uint) {
		return buyHeads[_tokenIndex];
	}

	function getSellHead(uint _tokenIndex) external view returns(uint) {
		return sellHeads[_tokenIndex];
	}

	function getOpenBuyOrders(uint _tokenIndex) external view returns(uint) {
		return openBuyOrders[_tokenIndex];
	}

	function getOpenSellOrders(uint _tokenIndex) external view returns(uint) {
		return openSellOrders[_tokenIndex];
	}

	function _updatePriceCumulative(uint _tokenIndex, uint _newDataPoint) internal checkFundingRateCalculation {
		priceCumulative[_tokenIndex] = priceCumulative[_tokenIndex].add(_newDataPoint);
		totalPriceDataPoints[_tokenIndex]++;
		lastCumulativePriceUpdate[_tokenIndex] = block.timestamp;
	}

	function _calculateFundingRates() internal {
		for (uint i = 0; i < Vaults.length; i++) {
			int safeMarkPrice = int(_calculateTWAP(i));
			int indexPrice = int(Oracle.getTwapPrice(priceFeedKeys[i], fundingInterval));
			int dif = safeMarkPrice.sub(indexPrice);
			int fundingRate = dif.div(fundingDivisor);
			int boneRate = int(BONE);
			boneRate = boneRate.add(fundingRate);
			FxVaults vaults = FxVaults(payable(Vaults[i]));
			vaults.updateDynamicMultiplier(uint(boneRate));
		}
	}

	function _calculateTWAP(uint _tokenIndex) internal returns(uint) {
		uint difference = priceCumulative[_tokenIndex].sub(lastPriceCumulative[_tokenIndex]);
		uint twap = difference.div(totalPriceDataPoints[_tokenIndex]);
		totalPriceDataPoints[_tokenIndex] = 0;
		priceCumulative[_tokenIndex] = 0;
		lastPriceCumulative[_tokenIndex] = priceCumulative[_tokenIndex];
		return twap;
	}

	function addFxPerpetual(address _perpetual, address _vault, bytes32 _priceFeedKey) external onlyOwner {
		FxPerpetuals.push(_perpetual);
		Vaults.push(_vault);
		priceFeedKeys.push(_priceFeedKey);
	}
}