// SPDX-License-Identifier: MIT
// Have the invariants

// 1. The total supply of DSC should be less than the total value of the collateral

// 2. Getters should never revert

pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../scripts/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DescentralizedStableCoin} from "../../src/DescentralizedStableCoin.sol";
import {HelperConfig} from "../../scripts/HelperConfig.s.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract Invariants is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine engine;
    DescentralizedStableCoin dsc;
    HelperConfig config;
    Handler handler;
    address weth;
    address wbtc;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (, , weth, wbtc, ) = config.activeNetworkConfig();
        // targetContract(address(engine));
        handler = new Handler(engine, dsc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(engine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(engine));

        uint256 wethValue = engine.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = engine.getUsdValue(wbtc, totalWbtcDeposited);

        console.log("WETH Value: ", wethValue);
        console.log("WBTC Value: ", wbtcValue);
        console.log("Total Supply: ", totalSupply);
        console.log("Times mint called", handler.timesMintIsCalled());

        assert(wethValue + wbtcValue >= totalSupply);
    }

    function invariant_gettersShouldNeverRevert() public view {
        engine.getCollateralTokens();
        engine.getDscAddress();
        engine.getPrecision();
        engine.getAdditionalFeedPrecision();
        engine.getLiquidationThreshold();
        engine.getLiquidationBonus();
        engine.getLiquidationPrecision();
        engine.getMinHealthFactor();
    }
}
