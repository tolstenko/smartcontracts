//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.9;
import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

contract JuniorCoin is ERC20PresetFixedSupply, AccessControlEnumerable, Ownable {
    using Address for address;

    address private walletTeamDev = address(0xfC438bCD0f268b91f81b091Dc965D4EA3acB9556);
    address private walletTeamMkt = address(0x631fDB5b5971275D573b065B8b920B1eDe5c67c4);

    constructor() ERC20PresetFixedSupply("JuniorCoin", "JRC", 1000000000 * 10**decimals(), _msgSender()){
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
     }

     function withdraw(address payable to, uint256 amount) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "transfer to the zero address");
        require(amount <= payable(address(this)).balance, "You are trying to withdraw more funds than available");
        to.transfer(amount);
    }

    function withdrawERC20(
        address tokenAddress,
        address to,
        uint256 amount
    ) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        require(tokenAddress.isContract(), "ERC20 token address must be a contract");

        IERC20 tokenContract = IERC20(tokenAddress);
        require(
            tokenContract.balanceOf(address(this)) >= amount,
            "You are trying to withdraw more funds than available"
        );

        require(tokenContract.transfer(to, amount), "Fail on transfer");
    }

    // TRANSFER TO TEAM DEV
    function withdrawTeamDev(uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE)  {
        require(_amount <= balanceOf(_msgSender()), "You are trying to withdraw more funds than available");
        transfer(walletTeamDev , _amount);
    }

        // TRANSFER TO TEAM MARKETING 
    function withdrawTeamMkt(uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE)  {
        require(_amount <= balanceOf(_msgSender()), "You are trying to withdraw more funds than available");
        transfer(walletTeamMkt , _amount);
    }

    // GIVEBACK FROM OWNER 
    function giveback(uint256 _amount) external {
        require(_amount <= balanceOf(_msgSender()), "You are trying to withdraw more funds than available");
        transfer(address(owner()) , _amount);  
    }
}
