// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {DeployDSC} from "../../../scripts/DeployDSC.s.sol";
import {DSCEngine} from "../../../src/DSCEngine.sol";
import {DescentralizedStableCoin} from "../../../src/DescentralizedStableCoin.sol";
import {HelperConfig} from "../../../scripts/HelperConfig.s.sol";
import {ERC20Mock} from "openzeppelin/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../../mocks/MockV3Aggregator.sol";
import {MockMoreDebtDSC} from "../../mocks/MockMoreDebtDSC.sol";
import {MockFailedMintDSC} from "../../mocks/MockFailedMintDSC.sol";
import {MockFailedTransferFrom} from "../../mocks/MockFailedTransferFrom.sol";
import {MockFailedTransfer} from "../../mocks/MockFailedTransfer.sol";
import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract DSCEngineMintTest is StdCheats, Test {
    event CollateralRedeemed(
        address indexed redeemFrom,
        address indexed redeemTo,
        address token,
        uint256 amount
    ); // if redeemFrom != redeemedTo, then it was liquidated

    DSCEngine public engine;
    DescentralizedStableCoin public dsc;
    HelperConfig public helperConfig;

    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public weth;
    address public wbtc;
    uint256 public deployerKey;
    address[] public tokenAddresses;
    address[] public feedAddresses;

    uint256 amountToMint = 100 ether;
    address public USER = address(1);

    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;

    // Liquidation
    address public liquidator = makeAddr("liquidator");
    uint256 public collateralToCover = 20 ether;

    function setUp() external {
        DeployDSC deployer = new DeployDSC();
        (dsc, engine, helperConfig) = deployer.run();
        (
            ethUsdPriceFeed,
            btcUsdPriceFeed,
            weth,
            wbtc,
            deployerKey
        ) = helperConfig.activeNetworkConfig();
        if (block.chainid == 31337) {
            vm.deal(USER, STARTING_USER_BALANCE);
        }

        ERC20Mock(weth).mint(USER, STARTING_USER_BALANCE);
        ERC20Mock(wbtc).mint(USER, STARTING_USER_BALANCE);
    }

    // This test needs it's own custom setup
    function testRevertsIfMintFails() public {
        // Arrange - Setup
        MockFailedMintDSC mockDsc = new MockFailedMintDSC();
        tokenAddresses = [weth];
        feedAddresses = [ethUsdPriceFeed];
        address owner = msg.sender;
        vm.prank(owner);
        DSCEngine mockDsce = new DSCEngine(
            tokenAddresses,
            feedAddresses,
            address(mockDsc)
        );
        mockDsc.transferOwnership(address(mockDsce));
        // Arrange - USER
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(mockDsce), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        mockDsce.depositCollateralAndMintDsc(
            weth,
            AMOUNT_COLLATERAL,
            amountToMint
        );
        vm.stopPrank();
    }

    function testRevertsIfMintAmountIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(
            weth,
            AMOUNT_COLLATERAL,
            amountToMint
        );
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.mintDsc(0);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanMintDsc() public depositedCollateral {
        vm.prank(USER);
        engine.mintDsc(amountToMint);

        uint256 USERBalance = dsc.balanceOf(USER);
        assertEq(USERBalance, amountToMint);
    }
}
