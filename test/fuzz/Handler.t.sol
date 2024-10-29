// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    ERC20Mock weth;
    ERC20Mock wbtc;
    MockV3Aggregator public ethUsdPriceFeed;
    address[] private userWithCollateralDeposited;

    uint256 public timesMintCalled;

    uint256 constant MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(
        DSCEngine _dscEngine,
        DecentralizedStableCoin _decentralizedStableCoin
    ) {
        dsce = _dscEngine;
        dsc = _decentralizedStableCoin;

        address[] memory collateralTokens = dsce.getCollateralTokens();

        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
        ethUsdPriceFeed = MockV3Aggregator(dsce.getCollateralTokenPriceFeed(address(weth)));
    }

    //! redeem collateral
    function depositCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        ERC20Mock tokenCollateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        vm.startPrank(msg.sender);
        tokenCollateral.mint(msg.sender, amountCollateral);
        tokenCollateral.approve(address(dsce), amountCollateral);
        dsce.depositCollateral(address(tokenCollateral), amountCollateral);
        vm.stopPrank();

        for (uint256 i = 0; i < userWithCollateralDeposited.length; i++) {
            if (userWithCollateralDeposited[i] == msg.sender) {
                return;
            }
        }
        userWithCollateralDeposited.push(msg.sender);
    }

    function redeemCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        vm.startPrank(msg.sender);
        ERC20Mock tokenCollateral = _getCollateralFromSeed(collateralSeed);
        uint256 tokenCollateralExist = dsce.getCollateralBalanceOfUser(
            msg.sender,
            address(tokenCollateral)
        );
        amountCollateral = bound(amountCollateral, 0, tokenCollateralExist);

        if (amountCollateral == 0) {
            return;
        }

        if (tokenCollateralExist < amountCollateral) {
            return;
        }

        dsce.redeemCollateral(address(tokenCollateral), amountCollateral);
        vm.stopPrank();
    }

    function mintDsc(uint256 amount, uint256 senderSeed) public {
        if (userWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = userWithCollateralDeposited[
            senderSeed % (userWithCollateralDeposited.length)
        ];
        amount = bound(amount, 0, MAX_DEPOSIT_SIZE);

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce
            .getAccountInformation(sender);
        int256 maxDscToMint = (int256(collateralValueInUsd) / 2) -
            int256(totalDscMinted);

        if (maxDscToMint < 0) {
            return;
        }

        amount = bound(amount, 0, uint256(maxDscToMint));

        if (amount == 0) {
            return;
        }

        vm.startPrank(sender);
        dsce.mintDsc(amount);
        vm.stopPrank();
        timesMintCalled++;
    }

    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    // }

    //! Helper functions
    function _getCollateralFromSeed(
        uint256 collateralSeed
    ) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }

        return wbtc;
    }
}
