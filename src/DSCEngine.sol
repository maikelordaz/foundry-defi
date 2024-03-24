// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {DescentralizedStableCoin} from "./DescentralizedStableCoin.sol";
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

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount))
        private s_collateralDeposited;

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

    function mintDsc() external {}

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

    function getDscAddress() external view returns (address) {
        return address(i_dsc);
    }

    function _moreThanZero(uint256 _amount) internal pure {
        if (_amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
    }

    function _isTokenAllowed(address _token) internal view {
        if (s_priceFeeds[_token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
    }
}
