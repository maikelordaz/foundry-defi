// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {DescentralizedStableCoin} from "./DescentralizedStableCoin.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title DSCEngine
 * @author Maikel Ordaz
 */
contract DSCEngine is ReentrancyGuard {
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAndAddressesLengthMissmatch();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount))
        private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;

    address[] private s_collateralTokens;

    DescentralizedStableCoin private immutable i_dsc;

    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 indexed amount
    );

    modifier moreThanZero(uint256 amount) {
        _moreThanZero(amount);
        _;
    }

    modifier isAllowedToken(address token) {
        _isTokenAllowed(token);
        _;
    }

    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address dscAddress
    ) {
        // USD price feeds
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAndAddressesLengthMissmatch();
        }

        uint256 length = tokenAddresses.length;
        for (uint256 i; i < length; ) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);

            /// @custom:unchecked without risk
            unchecked {
                ++i;
            }
        }

        i_dsc = DescentralizedStableCoin(dscAddress);
    }

    function depositCollateralAndMintDsc() external {}

    /// @param tokenCollateralAddress The address of the token to be deposited as collateral
    /// @param amountCollateral The amount of the token to be deposited as collateral
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][
            tokenCollateralAddress
        ] += amountCollateral;

        emit CollateralDeposited(
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );

        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            amountCollateral
        );

        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    /// @param amountDscToMint The amount of DSC to mint
    /// @notice must have more collateral than minimum threshold
    function mintDsc(
        uint256 amountDscToMint
    ) external moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        _revertIfHeathFactorIsBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

    function getDscAddress() external view returns (address) {
        return address(i_dsc);
    }

    /// @param token The address of the token
    /// @return The address of the price feed
    function getPriceFeedAddress(
        address token
    ) external view returns (address) {
        return s_priceFeeds[token];
    }

    /// @param user The address of the user
    /// @param token The address of the token
    /// @return The amount of collateral deposited
    function getCollateralDeposited(
        address user,
        address token
    ) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    /// @param user The address of the user
    /// @return The amount of DSC minted
    function getDscMinted(address user) external view returns (uint256) {
        return s_DSCMinted[user];
    }

    /// @return The collateral tokens
    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    /// @param user The address of the user
    /// @return totalCollateralValueInUsd The total collateral value in USD
    function getAccountCollateralValueInUsd(
        address user
    ) public view returns (uint256 totalCollateralValueInUsd) {
        uint256 length = s_collateralTokens.length;

        for (uint256 i; i < length; ) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);

            /// @custom:unchecked without risk
            unchecked {
                ++i;
            }
        }
    }

    function getUsdValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();

        // 1 ETH = 1000$
        // The returned value from CL will be 1000 * 1e8
        return
            ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    /// @param _amount The amount to check
    function _moreThanZero(uint256 _amount) internal pure {
        if (_amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
    }

    /// @param _token The address of the token
    function _isTokenAllowed(address _token) internal view {
        if (s_priceFeeds[_token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
    }

    /// @param _user The address of the user
    /// @return _totalDscMinted The total DSC minted by the user
    /// @return _collateralValueInUsd The total collateral value in USD
    function _getAccountInformation(
        address _user
    )
        private
        view
        returns (uint256 _totalDscMinted, uint256 _collateralValueInUsd)
    {
        _totalDscMinted = s_DSCMinted[_user];
        _collateralValueInUsd = getAccountCollateralValueInUsd(_user);
    }

    /// @param _user The address of the user
    /// @return The health factor of the user
    /// @dev If the user's health factor is below 1, can get liquidated
    function _healthFactor(address _user) private view returns (uint256) {
        (
            uint256 totalDscMinted,
            uint256 collateralValueInUsd
        ) = _getAccountInformation(_user);

        uint256 collateralAdjustedForThreshold = (collateralValueInUsd *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    /// @param _user The address of the user
    function _revertIfHeathFactorIsBroken(address _user) internal view {
        uint256 userHealthFactor = _healthFactor(_user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }
}
