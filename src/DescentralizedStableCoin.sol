// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {ERC20Burnable, ERC20} from "openzeppelin/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "openzeppelin/access/Ownable.sol";

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
    error DescentralizedStableCoin__NotZeroAddress();

    constructor() ERC20("DescentralizedStableCoin", "DSC") {}

    /// @dev Burn tokens from the owner's balance
    /// @param amount The amount of tokens to burn
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

    /// @dev Mint new tokens
    /// @param to The address to mint tokens to
    /// @param amount The amount of tokens to mint
    function mint(
        address to,
        uint256 amount
    ) external onlyOwner returns (bool) {
        if (to == address(0)) {
            revert DescentralizedStableCoin__NotZeroAddress();
        }
        if (amount <= 0) {
            revert DescentralizedStableCoin__MustBeMoreThanZero();
        }

        _mint(to, amount);

        return true;
    }
}
