// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "./TimeLockDexTransactions.sol";

/**
* Transações tiram fees
* Fee de liquidez pode ir para todos ou o user ou a empresa(configurável pela empresa) [done: Ailton, Tolsta]
* Fee de ecossistema da empresa(configurável pela empresa) [done: Ailton]
* Fee de burn. (configurável pela empresa até certo limite) [done: Ailton]
* Fees totais limitados a 10% [done: Tolsta]
* Upgradeable para próximo token
* Anti whale fees baseado em volume da dex. Configurável até certo limite pela empresa.
* Time lock dex transactions [done: Ailton]
* Receber fees em BNB ou BUSD (não obrigatório)
*/
contract ERC20FLiqFEcoFBurnAntiDumpDexTempBan is ERC20, ERC20Burnable, Pausable, Ownable, TimeLockDexTransactions {
    using SafeMath for uint256;
    using Address for address;

    // @dev dead address
    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    // @dev the fee the ecosystem takes. value uses decimals() as multiplicative factor
    uint256 public ecoSystemFee;

    // @dev which wallet will receive the ecosystem fee
    address public ecoSystemAddress;

    // @dev the fee the liquidity takes. value uses decimals() as multiplicative factor
    uint256 public liquidityFee;

    // @dev which wallet will receive the ecosystem fee. If dead is used, it goes to the msgSender
    address public liquidityAddress;

    // @dev the fee the burn takes. value uses decimals() as multiplicative factor
    uint256 public burnFee;

    // @dev the total max value of the fee
    uint256 public constant _maxFee = 10 ** 17;

    // @dev the defauld dex router
    IUniswapV2Router02 public dexRouter;

    // @dev the dex factory address
    address public uniswapFactoryAddress;

    // @dev just to simplify to the user, the total fees
    uint256 public totalFees = 0;

    // @dev antiwhale mechanics
    uint256 public maxTransferFee;

    // @dev mapping of excluded from fees elements
    mapping(address => bool) public isExcludedFromFees;

    // @dev the default dex pair
    address public dexPair;

    // @dev what pairs are allowed to work in the token
    mapping(address => bool) public automatedMarketMakerPairs;

    mapping (address => bool) internal authorizations;

    //max wallet holding of 3% 
    uint256 public _maxWalletToken = ( totalSupply * 3 ) / 100;

    constructor(string memory name, string memory symbol, uint256 totalSupply) ERC20(name, symbol) {
        excludeFromFees(address(this), true);
        excludeFromFees(owner(), true);

        ecoSystemAddress = owner();
        liquidityAddress = DEAD_ADDRESS;
        maxTransferFee = 1 ether;

        _mint(owner(), totalSupply);

        authorizations[_owner] = true;

        dexRouter = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E); // bsc mainnet router
        uniswapFactoryAddress = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73; // pancakeswap factory address

        // Create a uniswap pair for this new token
        dexPair = IUniswapV2Factory(dexRouter.factory()).createPair(address(this), dexRouter.WETH());
        _setAutomatedMarketMakerPair(dexPair, true);

        isExcludedFromFees[owner()] = true;
        isExcludedFromFees[address(this)] = true;
        isExcludedFromFees[DEAD_ADDRESS] = true;
        emit ExcludeFromFees(owner(), true);
        emit ExcludeFromFees(address(this), true);
        emit ExcludeFromFees(DEAD_ADDRESS, true);
    }

    function setAutomatedMarketMakerPair(address pair, bool value) external onlyOwner {
        require(pair != dexPair, "cannot be removed");
        _setAutomatedMarketMakerPair(pair, value);
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private onlyOwner {
        automatedMarketMakerPairs[pair] = value;
        emit SetAutomatedMarketMakerPair(pair, value);
    }

    // @dev create and add a new pair for a given token
    function addNewPair(address tokenAddress) external onlyOwner returns (address np) {
        address newPair = IUniswapV2Factory(dexRouter.factory()).createPair(address(this), tokenAddress);
        _setAutomatedMarketMakerPair(newPair, true);
        emit AddNewPair(tokenAddress, newPair);
        return newPair;
    }
    event AddNewPair(address indexed tokenAddress, address indexed newPair);

    receive() external payable {}

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        require(isExcludedFromFees[account] != excluded, "Already set");
        isExcludedFromFees[account] = excluded;
        emit ExcludeFromFees(account, excluded);
    }

    function checkFeesChanged(uint256 _oldFee, uint256 _newFee) internal view {
        uint256 _fees = ecoSystemFee.add(liquidityFee).add(burnFee).add(_newFee).sub(_oldFee);
        require(_fees <= _maxFee, "Fees exceeded max limitation");
    }

    function setEcoSystemAddress(address newAddress) public onlyOwner {
        require(ecoSystemAddress != newAddress, "EcoSystem address already setted");
        ecoSystemAddress = newAddress;
        emit EcoSystemAddressUpdated(newAddress);
    }

    function setEcosystemFee(uint256 newFee) public onlyOwner {
        checkFeesChanged(ecoSystemFee, newFee);
        ecoSystemFee = newFee;
        _updateTotalFee();
        emit EcosystemFeeUpdated(newFee);
    }

    function setLiquidityAddress(address newAddress) public onlyOwner {
        require(liquidityAddress != newAddress, "Liquidity address already setted");
        liquidityAddress = newAddress;
        emit LiquidityAddressUpdated(newAddress);
    }

    function setLiquidityFee(uint256 newFee) public onlyOwner {
        checkFeesChanged(liquidityFee, newFee);
        liquidityFee = newFee;
        _updateTotalFee();
        emit LiquidityFeeUpdated(newFee);
    }

    function setBurnFee(uint256 newFee) public onlyOwner {
        checkFeesChanged(burnFee, newFee);
        burnFee = newFee;
        _updateTotalFee();
        emit BurnFeeUpdated(newFee);
    }

    function setLockTime(uint timeBetweenTransactions) external onlyOwner {
        _setLockTime(timeBetweenTransactions);
    }

    function setMaxTransferFee(uint mtf) external onlyOwner {
        maxTransferFee = mtf;
    }

    function startLiquidity(address router) external onlyOwner {
        require(router != address(0), "zero address is not allowed");

        IUniswapV2Router02 _dexRouter = IUniswapV2Router02(router);

        address _dexPair = IUniswapV2Factory(_dexRouter.factory()).createPair(address(this), _dexRouter.WETH());

        dexRouter = _dexRouter;
        dexPair = _dexPair;

        _setAutomatedMarketMakerPair(_dexPair, true);

        emit LiquidityStarted(router, _dexPair);
    }

    function _updateTotalFee() internal {
        totalFees = liquidityFee.add(burnFee).add(ecoSystemFee);
    }

    function _swapAndLiquify(uint256 amount) private {
        uint256 half = amount.div(2);
        uint256 otherHalf = amount.sub(half);

        uint256 initialAmount = address(this).balance;

        _swapTokensForBNB(half);

        uint256 newAmount = address(this).balance.sub(initialAmount);

        _addLiquidity(otherHalf, newAmount);

        emit SwapAndLiquify(half, newAmount, otherHalf);
    }

    function _swapTokensForBNB(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = dexRouter.WETH();

        _approve(address(this), address(dexRouter), tokenAmount);

        dexRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp.add(300)
        );
    }

    function _addLiquidity(uint256 tokenAmount, uint256 bnbAmount) private {
        _approve(address(this), address(dexRouter), tokenAmount);

        dexRouter.addLiquidityETH{ value: bnbAmount }(
            address(this),
            tokenAmount,
            0,
            0,
            liquidityAddress == DEAD_ADDRESS ? _msgSender() : liquidityAddress,
            block.timestamp.add(300)
        );
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");

        bool excludedAccount = isExcludedFromFees[from] || isExcludedFromFees[to];
        (uint112 reserve0, , ) = IUniswapV2Pair(dexPair).getReserves();
        uint maxTransferAmount = uint256(reserve0).div(100).mul(maxTransferFee);
        if (excludedAccount) {
            super._transfer(from, to, amount);
        } else {
            require(amount <= maxTransferAmount, "Max transfer amount limit reached");
            if(automatedMarketMakerPairs[to]) {
                require(canOperate(from), "the sender cannot operate yet");
                lockToOperate(from);
            } else {
                require(canOperate(to), "the recipient cannot sell yet");
                lockToOperate(to);
            }

            if (ecoSystemFee > 0) {
                uint256 tokenToEcoSystem = amount.mul(ecoSystemFee).div(100);
                super._transfer(from, ecoSystemAddress, tokenToEcoSystem);
            }

            if (!authorizations[from] && to != address(this)  && to != address(DEAD) && to != pair && to != ecoSystemFee && to != liquidityFee){
            uint256 heldTokens = balanceOf(to);
            require((heldTokens + amount) <= _maxWalletToken,"Total Holding is currently limited, you can not buy that much.");}


            if (liquidityFee > 0) {
                uint256 tokensToLiquidity = amount.mul(liquidityFee).div(100);
                super._transfer(from, address(this), tokensToLiquidity);
                _swapAndLiquify(tokensToLiquidity);
            }

            //@TODO burn tokens
            uint256 amountMinusFees = amount.sub(ecoSystemFee).sub(liquidityFee);
            super._transfer(from, to, amountMinusFees);
        }
    }

    event ExcludeFromFees(address indexed account, bool isExcluded);
    event LiquidityAddressUpdated(address indexed liquidityAddress);
    event EcoSystemAddressUpdated(address indexed ecoSystemAddress);
    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);
    event SwapAndLiquify(
        uint256 indexed tokensSwapped,
        uint256 indexed bnbReceived,
        uint256 indexed tokensIntoLiqudity
    );
    event EcosystemFeeUpdated(uint256 indexed fee);
    event LiquidityFeeUpdated(uint256 indexed fee);
    event BurnFeeUpdated(uint256 indexed fee);
    event BurnFeeLimitUpdated(uint256 indexed limit);
    event LiquidityStarted(address indexed routerAddress, address indexed pairAddress);


    // todo: make nonReentrant
    function withdraw() onlyOwner public {
        uint256 balance = address(this).balance;
        Address.sendValue(payable(msg.sender), balance);
        //        payable(msg.sender).transfer(balance);
    }

    // todo: make nonReentrant
    /**
     * @dev Withdraw any ERC20 token from this contract
     * @param tokenAddress ERC20 token to withdraw
     * @param to receiver address
     * @param amount amount to withdraw
     */
    function withdrawERC20(
        address tokenAddress,
        address to,
        uint256 amount
    ) external virtual onlyOwner {
       IERC20 tokenContract = IERC20(tokenAddress);
        require(
            tokenContract.balanceOf(address(this)) >= amount,
            "You are trying to withdraw more funds than available"
        );
        require(tokenAddress.isContract(), "ERC20 token address must be a contract");

        

        require(tokenContract.transfer(to, amount), "Fail on transfer");
    }
    
    //settting the maximum permitted wallet holding (percent of total supply)
    function setMaxWalletPercent(uint256 maxWallPercent) external onlyOwner() {
        _maxWalletToken = (TOTAL_SUPPLY * maxWallPercent ) / 100;
    }

    //Authorize address. Owner only
    function authorize(address adr) public onlyOwner {
        authorizations[adr] = true;
    }

    
    //Remove address' authorization. Owner only
    function unauthorize(address adr) public onlyOwner {
        authorizations[adr] = false;
    }

    //Return address' authorization status
    function isAuthorized(address adr) public view returns (bool) {
        return authorizations[adr];
    }
}