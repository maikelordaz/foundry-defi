// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DescentralizedStableCoin
 * @author Maikel Ordaz
 * @notice Collateral: Exogenous (ETH & BTC)
 * @notice Minting: Algorithmic
 * @notice Stability: Pegged to the US Dollar
 * @dev This contract is governed by DSCEngine contract, this is just the ERC20 token implementation contract
 */
contract DescentralizedStableCoin is ERC20Burnable, Ownable {
    error DescentralizedStableCoin__MustBeMoreThanZero();
    error DescentralizedStableCoin__BurnAmountExceedsBalance();

    constructor() ERC20("DescentralizedStableCoin", "DSC") {}

    function burn(uint256 amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (amount <= 0) {
            revert DescentralizedStableCoin__MustBeMoreThanZero();
        }
        if (balance < amount) {
            revert DescentralizedStableCoin__BurnAmountExceedsBalance();
        }

        super.burn(amount);
    }
}
