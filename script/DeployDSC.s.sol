// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {DescentralizedStableCoin} from "../src/DescentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (DescentralizedStableCoin, DSCEngine) {
        HelperConfig config = new HelperConfig();

        (
            address wethUsdPriceFeed,
            address wbtcUsdPriceFeed,
            address weth,
            address wbtc,
            uint256 deployerKey
        ) = config.activeNetworkConfig();

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);

        DescentralizedStableCoin dsc = new DescentralizedStableCoin();
        DSCEngine engine = new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(dsc)
        );

        dsc.transferOwnership(address(engine));

        vm.stopBroadcast();

        return (dsc, engine);
    }
}
