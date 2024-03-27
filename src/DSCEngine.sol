// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {ReentrancyGuard} from "openzeppelin/security/ReentrancyGuard.sol";
import {DescentralizedStableCoin} from "./DescentralizedStableCoin.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

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
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_BONUS = 10; // 10%

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;

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
    event CollateralRedeemed(
        address indexed redemedFrom,
        address indexed redeemedTo,
        address indexed token,
        uint256 amount
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

    /// @param tokenCollateralAddress The address of the token to be deposited as collateral
    /// @param amountCollateral The amount of the token to be deposited as collateral
    /// @param amountDscToMint The amount of DSC to mint
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        _depositCollateral(tokenCollateralAddress, amountCollateral);
        _mintDsc(amountDscToMint);
    }

    /// @param tokenCollateralAddress The address of the token to be redeemed
    /// @param amountDscToBurn The amount of DSC to burn
    function redeemCollateralForDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToBurn
    ) external {
        _burnDsc(amountDscToBurn, msg.sender, msg.sender);
        _redeemCollateral(
            tokenCollateralAddress,
            amountCollateral,
            msg.sender,
            msg.sender
        );
        revertIfHealthFactorIsBroken(msg.sender);
    }

    /// @param tokenCollateralAddress The address of the token to be redeemed
    /// @param amountCollateral The amount of the token to be redeemed
    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) external moreThanZero(amountCollateral) nonReentrant {
        _redeemCollateral(
            tokenCollateralAddress,
            amountCollateral,
            msg.sender,
            msg.sender
        );

        _revertIfHeathFactorIsBroken(msg.sender);
    }

    /// @param amount The amount of DSC to burn
    function burnDsc(uint256 amount) external moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHeathFactorIsBroken(msg.sender);
    }

    /// @param collateral The address of the collateral token
    /// @param user The user who broke the health factor
    /// @param debtToCover The amount of debt to cover
    /// @notice You can partially liquidate the user
    /// @notice You will get a bonus for liquidating the user
    /// @notice This function working assumes the protocol will be roughly 200% overcollateralized
    function liquidate(
        address collateral,
        address user,
        uint256 debtToCover
    ) external moreThanZero(debtToCover) nonReentrant {
        uint256 startingUserHealthFactor = _healthFactor(user);

        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }

        uint256 tokenAmountFromDebtCovered = _getTokenAmountFromUsd(
            collateral,
            debtToCover
        );

        uint256 bonusCollateral = (tokenAmountFromDebtCovered *
            LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered +
            bonusCollateral;

        _redeemCollateral(
            collateral,
            totalCollateralToRedeem,
            user,
            msg.sender
        );

        _burnDsc(debtToCover, user, msg.sender);

        uint256 finalUserHealthFactor = _healthFactor(user);
        if (finalUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHeathFactorIsBroken(msg.sender);
    }

    /// @param amountDscToMint The amount of DSC to mint
    /// @notice must have more collateral than minimum threshold
    function mintDsc(
        uint256 amountDscToMint
    ) external moreThanZero(amountDscToMint) nonReentrant {
        _mintDsc(amountDscToMint);
    }

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
        _depositCollateral(tokenCollateralAddress, amountCollateral);
    }

    /// @param token The address of the token to be redeemed
    /// @param amount The amount of the token to be redeemed
    /// @return The amount in USD
    function getUsdValue(
        address token,
        uint256 amount
    ) external view returns (uint256) {
        return _getUsdValue(token, amount);
    }

    /// @param user The address of the user
    /// @return totalDscMinted The total DSC minted by the user
    /// @return collateralValueInUsd The total collateral value in USD
    function getAccountInformation(
        address user
    )
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
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

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

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
    /// @return The amount of DSC minted
    function getDscMinted(address user) external view returns (uint256) {
        return s_DSCMinted[user];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    /// @param user The address of the user
    /// @return totalCollateralValueInUsd The total collateral value in USD
    function getAccountCollateralValueInUsd(
        address user
    ) external view returns (uint256 totalCollateralValueInUsd) {
        totalCollateralValueInUsd = _getAccountCollateralValueInUsd(user);
    }

    function getTokenAmountFromUsd(
        address token,
        uint256 usdAmountInWei
    ) external view returns (uint256 tokenAmount) {
        tokenAmount = _getTokenAmountFromUsd(token, usdAmountInWei);
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    ) external pure returns (uint256) {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    /// @param _amountDscToMint The amount of DSC to mint
    /// @notice must have more collateral than minimum threshold
    function _mintDsc(uint256 _amountDscToMint) internal {
        s_DSCMinted[msg.sender] += _amountDscToMint;
        _revertIfHeathFactorIsBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, _amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    /// @param _tokenCollateralAddress The address of the token to be deposited as collateral
    /// @param _amountCollateral The amount of the token to be deposited as collateral
    function _depositCollateral(
        address _tokenCollateralAddress,
        uint256 _amountCollateral
    ) internal {
        s_collateralDeposited[msg.sender][
            _tokenCollateralAddress
        ] += _amountCollateral;

        emit CollateralDeposited(
            msg.sender,
            _tokenCollateralAddress,
            _amountCollateral
        );

        bool success = IERC20(_tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            _amountCollateral
        );

        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /// @param _tokenCollateralAddress The address of the token to be redeemed
    /// @param _amountCollateral The amount of the token to be redeemed
    /// @param _from The address of the user who wants to redeem the collateral
    /// @param _to The address of the user who will receive the collateral
    function _redeemCollateral(
        address _tokenCollateralAddress,
        uint256 _amountCollateral,
        address _from,
        address _to
    ) internal {
        s_collateralDeposited[_from][
            _tokenCollateralAddress
        ] -= _amountCollateral;

        emit CollateralRedeemed(
            _from,
            _to,
            _tokenCollateralAddress,
            _amountCollateral
        );

        bool success = IERC20(_tokenCollateralAddress).transfer(
            _to,
            _amountCollateral
        );

        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /// @param _amountDscToBurn The amount of DSC to burn
    /// @param _onBehalfOf The address of the user who wants to burn the DSC
    /// @param _dscFrom The address of the user who has the DSC
    function _burnDsc(
        uint256 _amountDscToBurn,
        address _onBehalfOf,
        address _dscFrom
    ) internal {
        s_DSCMinted[_onBehalfOf] -= _amountDscToBurn;
        bool success = i_dsc.transferFrom(
            _dscFrom,
            address(this),
            _amountDscToBurn
        );

        // This condition is a backup. If something fails should revert on the transferFrom call
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(_amountDscToBurn);
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
        internal
        view
        returns (uint256 _totalDscMinted, uint256 _collateralValueInUsd)
    {
        _totalDscMinted = s_DSCMinted[_user];
        _collateralValueInUsd = _getAccountCollateralValueInUsd(_user);
    }

    /// @param _user The address of the user
    /// @return The health factor of the user
    /// @dev If the user's health factor is below 1, can get liquidated
    function _healthFactor(address _user) internal view returns (uint256) {
        (
            uint256 totalDscMinted,
            uint256 collateralValueInUsd
        ) = _getAccountInformation(_user);
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function _getUsdValue(
        address _token,
        uint256 _amount
    ) internal view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[_token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();

        // 1 ETH = 1000$
        // The returned value from CL will be 1000 * 1e8
        return
            ((uint256(price) * ADDITIONAL_FEED_PRECISION) * _amount) /
            PRECISION;
    }

    /// @param _user The address of the user
    function _revertIfHeathFactorIsBroken(address _user) internal view {
        uint256 userHealthFactor = _healthFactor(_user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    /// @param _user The address of the user
    /// @return totalCollateralValueInUsd The total collateral value in USD
    function _getAccountCollateralValueInUsd(
        address _user
    ) internal view returns (uint256 totalCollateralValueInUsd) {
        uint256 length = s_collateralTokens.length;

        for (uint256 i; i < length; ) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[_user][token];
            totalCollateralValueInUsd += _getUsdValue(token, amount);

            /// @custom:unchecked without risk
            unchecked {
                ++i;
            }
        }
    }

    function _getTokenAmountFromUsd(
        address _token,
        uint256 _usdAmountInWei
    ) internal view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[_token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();

        return
            (_usdAmountInWei * PRECISION) /
            (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function _calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    ) internal pure returns (uint256) {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    /// @param _amount The amount to check
    function _moreThanZero(uint256 _amount) internal pure {
        if (_amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
    }
}
