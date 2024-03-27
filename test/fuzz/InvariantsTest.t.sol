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

contract InvariantsTest is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine engine;
    DescentralizedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (, , weth, wbtc, ) = config.activeNetworkConfig();
        targetContract(address(engine));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(engine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(engine));

        uint256 wethValue = engine.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = engine.getUsdValue(wbtc, totalWbtcDeposited);

        assert(wethValue + wbtcValue >= totalSupply);
    }
}
