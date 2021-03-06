// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.9;
import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract CameloCoin is ERC20PresetFixedSupply, AccessControlEnumerable {
    using Address for address;

    constructor() ERC20PresetFixedSupply ("CameloCoin", "CMC", 1000000000 * 10**decimals(), _msgSender()){
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        console.log("Contract created");

    }

    function burn(uint256 amount) public virtual override {
        _burn(_msgSender(), amount);
    }

    function burnFrom(address account, uint256 amount) public virtual override {
        _spendAllowance(account, _msgSender(), amount);
        _burn(account, amount);
    }


    function withdraw(address payable to, uint256 amount) external virtual onlyRole(DEFAULT_ADMIN_ROLE){
        require(to != address(0), "transfer to the zero address");
        require(amount <= payable(address(this)).balance, "You are trying to withdraw more founds than avaiable");
        to.transfer(amount);
    }

    function withdrawERC20(address tokenAddress, address to, uint256 amount) external virtual onlyRole(DEFAULT_ADMIN_ROLE){
        require(tokenAddress.isContract(), "ERC20 token address must be a contract");

        IERC20 tokenContract = IERC20(tokenAddress);
            require(tokenContract.balanceOf(address(this)) >= amount, "You are trying to withdraw more funds than available");
    }
 
}



