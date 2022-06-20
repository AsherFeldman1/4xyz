// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./RateOracle.sol";

contract FxBase is ERC20 {

	using SafeMath for uint256;

	uint internal vaultID;

	uint internal debtTokenIndex;

	uint internal BONE;
	uint internal MIN_DEBT_RATIO;

	uint public DYNAMIC_BALANCE_MULTIPLIER;

	address[] public collateralWhitelist;

	address owner;

	address OrderBook;

	RateOracle internal oracle;

	mapping(uint => Vault) public Vaults;
	mapping(uint => bool) public isClosed;

	struct Vault {
		address Owner;
		uint CollateralIndex;
		uint Collateral;
		uint Debt;
		uint ID;
	}

	constructor(address[] memory _collateralWhitelist, address _oracle, address _OrderBook,
	 uint _debtTokenIndex, string memory _name, string memory _symbol) ERC20(_name, _symbol) {
		oracle = RateOracle(_oracle);
		debtTokenIndex = _debtTokenIndex;
		collateralWhitelist = _collateralWhitelist;
		BONE = 1e18;
		MIN_DEBT_RATIO = 1e17;
		owner = msg.sender;
		OrderBook = _OrderBook;
	}

	receive() external payable {}

	modifier onlyVaultOwner(uint _vaultID) {
		Vault memory vault = Vaults[_vaultID];
		require(msg.sender == vault.Owner);
		_;
	}

	function openVault(uint _collateralIndex) external returns(uint) {
		Vault memory vault = Vault(
			msg.sender,
			_collateralIndex,
			0,
			0,
			vaultID	
		);
		Vaults[vault.ID] = vault;
		vaultID++;
		return vault.ID;
	}

	function supply(uint _vaultID, uint _amount) external {
		Vault storage vault = Vaults[_vaultID];
		IERC20 collateral = IERC20(collateralWhitelist[vault.CollateralIndex]);
		require(collateral.transferFrom(msg.sender, address(this), _amount));
		vault.Collateral = vault.Collateral.add(_amount);
	}

	function withdraw(uint _vaultID, uint _amount) external virtual onlyVaultOwner(_vaultID) {
		Vault storage vault = Vaults[_vaultID];
		uint debt = convertTokenDenomintation(debtTokenIndex, vault.Debt.mul(DYNAMIC_BALANCE_MULTIPLIER).div(BONE));
		uint newCollateral = convertTokenDenomintation(vault.CollateralIndex, vault.Collateral.sub(_amount));
		require(debt.mul(BONE).div(newCollateral) > MIN_DEBT_RATIO);
		vault.Collateral = vault.Collateral.sub(_amount);
	}

	function borrow(uint _vaultID, uint _amount) external virtual onlyVaultOwner(_vaultID) {
		Vault storage vault = Vaults[_vaultID];
		uint newDebt = convertTokenDenomintation(debtTokenIndex, vault.Debt.add(_amount));
		uint dynamicNewDebt = newDebt.mul(DYNAMIC_BALANCE_MULTIPLIER).div(BONE);
		uint collateral = convertTokenDenomintation(vault.CollateralIndex, vault.Collateral);
		require(dynamicNewDebt.mul(BONE).div(collateral) > MIN_DEBT_RATIO);
		vault.Debt = vault.Debt.add(_amount);
		_mint(msg.sender, _amount);
	}

	function repay(uint _vaultID, uint _amount) external {
		Vault storage vault = Vaults[_vaultID];
		uint dynamicAmount = _amount.mul(BONE).div(DYNAMIC_BALANCE_MULTIPLIER);
		vault.Debt = vault.Debt.sub(dynamicAmount);
		_burn(msg.sender, _amount);
	}

	function closePosition(uint _vaultID) external onlyVaultOwner(vaultID) {
		require(!detectLiquidation(_vaultID));
		_close(_vaultID);
	}

	function liquidate(uint _vaultID) external {
		require(detectLiquidation(_vaultID));
		_close(_vaultID);
	}

	function _close(uint _vaultID) internal {
		Vault storage vault = Vaults[_vaultID];
		IERC20 collateral = IERC20(collateralWhitelist[vault.CollateralIndex]);
		require(transferFrom(msg.sender, address(this), vault.Debt.mul(DYNAMIC_BALANCE_MULTIPLIER).div(BONE)));
		collateral.transfer(msg.sender, vault.Collateral);
		vault.Collateral = 0;
		vault.Debt = 0;
		isClosed[_vaultID] = true;
	}

	function detectLiquidation(uint _vaultID) internal virtual view returns(bool success) {
		Vault memory vault = Vaults[_vaultID];
		uint dynamicDebt = vault.Debt.mul(DYNAMIC_BALANCE_MULTIPLIER).div(BONE);
		uint debt = convertTokenDenomintation(debtTokenIndex, dynamicDebt);
		uint collateral = convertTokenDenomintation(vault.CollateralIndex, vault.Collateral);
		success = debt.mul(BONE).div(collateral) <= MIN_DEBT_RATIO && (collateral != 0 && debt != 0);
	}

	function convertTokenDenomintation(uint _tokenIndex, uint _amount) internal view returns(uint _price) {
		uint price = uint(oracle.getPrice(_tokenIndex));
		_price = price == 0 ? 0 : price.mul(_amount).div(BONE);
	}

	function addCollateralOption(address _collateral) external {
		require(msg.sender == owner);
		collateralWhitelist.push(_collateral);
	}

	function updateDynamicMultipliers(int _fundingRate) external {
		require(msg.sender == OrderBook);
		
	}

	function _transfer(address from, address to, uint amount) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(from, to, amount);

        uint256 fromBalance = _balances[from];
        require(amount <= fromBalance.mul(DYNAMIC_BALANCE_MULTIPLIER).div(BONE));

        uint256 dynamicAmount = amount.div(DYNAMIC_BALANCE_MULTIPLIER);
        _balances[from] = fromBalance.sub(dynamicAmount);

        _balances[to] += amount;

        emit Transfer(from, to, amount);

        _afterTokenTransfer(from, to, amount);
	}
}