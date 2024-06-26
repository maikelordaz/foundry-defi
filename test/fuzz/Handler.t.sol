// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DescentralizedStableCoin} from "../../src/DescentralizedStableCoin.sol";
import {ERC20Mock} from "openzeppelin/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    // Contract the handler will handle
    DSCEngine engine;
    DescentralizedStableCoin dsc;

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 public timesMintIsCalled;
    address[] public usersWithCollateralDeposited;
    MockV3Aggregator public ethUsdPriceFeed;

    uint256 constant MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSCEngine _engine, DescentralizedStableCoin _dsc) {
        engine = _engine;
        dsc = _dsc;

        address[] memory collateralTokens = engine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(
            engine.getPriceFeedAddress(address(weth))
        );
    }

    // Deposit collateral Handler
    // As in fuzzing the inputs are randomised
    function depositCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        // Bound the amount of collateral to deposit from 1 to MAX_DEPOSIT_SIZE
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);

        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(engine), amountCollateral);

        engine.depositCollateral(address(collateral), amountCollateral);

        vm.stopPrank();

        // Maybe there is double push
        usersWithCollateralDeposited.push(msg.sender);
    }

    function mintDsc(uint256 amount, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }

        // Use someone that already has collateral deposited
        address sender = usersWithCollateralDeposited[
            addressSeed % usersWithCollateralDeposited.length
        ];

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine
            .getAccountInformation(sender);

        int256 maxDscToMint = (int256(collateralValueInUsd) / 2) -
            int256(totalDscMinted);

        // Can't mint more than the collateral you have
        if (maxDscToMint < 0) {
            return;
        }

        amount = bound(amount, 0, uint256(maxDscToMint));

        if (amount == 0) {
            return;
        }

        vm.startPrank(sender);
        engine.mintDsc(amount);
        vm.stopPrank();

        timesMintIsCalled++;
    }

    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    // }

    // // Redeem collateral Handler
    // function redeemCollateral(
    //     uint256 collateralSeed,
    //     uint256 amountCollateral
    // ) public {
    //     ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
    //     uint256 maxCollateral = engine.getCollateralBalanceOfUser(
    //         msg.sender,
    //         address(collateral)
    //     );

    //     amountCollateral = bound(amountCollateral, 0, maxCollateral);
    //     vm.prank(msg.sender);
    //     if (amountCollateral == 0) {
    //         return;
    //     }
    //     vm.prank(msg.sender);
    //     engine.redeemCollateral(address(collateral), amountCollateral);
    // }

    // Helpers
    function _getCollateralFromSeed(
        uint256 _seed
    ) private view returns (ERC20Mock) {
        if (_seed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }
}
