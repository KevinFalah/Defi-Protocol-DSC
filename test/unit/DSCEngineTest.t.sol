// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockFailedTransfer} from "test/mocks/MockFailedTransfer.sol";
import {MockFailedTransferFrom} from "test/mocks/MockFailedTransferFrom.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;

    address[] tokenAddresses;
    address[] priceFeedAddresses;
    address dscAddress;

    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant AMOUNT_TO_MINT = 100 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant COLLATERAL_TO_COVER = 20 ether;

    address public USER = makeAddr("USER");
    address public LIQUIDATOR = makeAddr("liquidator");

    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(
            weth,
            AMOUNT_COLLATERAL,
            AMOUNT_TO_MINT
        );
        vm.stopPrank();
        _;
    }

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, , ) = config
            .activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    //! Constructor Tests

    function testRevertIfTokenLengthNotMatchWithPriceFeed() public {
        tokenAddresses.push(weth);
        dscAddress = address(dsc);

        vm.expectRevert(
            DSCEngine
                .DSCEngine__TokenAddressAndPriceFeedAddresMustBeSameLength
                .selector
        );
        new DSCEngine(tokenAddresses, priceFeedAddresses, dscAddress);
    }

    //! Price Tests
    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        //* 15e18 * 2000$/ETH = 30.000e18
        uint256 expectedResult = 30000e18;
        uint256 resultUsdValue = dsce.getUsdValue(weth, ethAmount);

        assertEq(expectedResult, resultUsdValue);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 60 ether;
        uint256 expectedWeth = 0.03 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);

        //? 60e18 (usdAmountInWei) / 2000 (ETH/USD) * 1e8 (default chainlink) * 1e10 (precision feed)
        assert(actualWeth == expectedWeth);
    }

    //! depositCollateral Tests

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(address(weth), AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testRevertsIfMintedDscBreaksHealthFactor() public {
        (, int256 price, , , ) = MockV3Aggregator(ethUsdPriceFeed)
            .latestRoundData();

        uint256 amountToMint = (AMOUNT_COLLATERAL *
            (uint256(price) * dsce.getAdditionalFeedPrecision())) /
            dsce.getPrecision();

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        uint256 expectedHealthFactor = dsce.calculateHealthFactor(
            amountToMint,
            dsce.getUsdValue(weth, AMOUNT_COLLATERAL)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BreaksHealthFactor.selector,
                expectedHealthFactor
            )
        );
        console.log(expectedHealthFactor, amountToMint, '<---');
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();
    }

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(address(weth), 0);
        vm.stopPrank();
    }

    function testSuccessDepositCollateral() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        uint256 amountDeposit = 3 ether;
        dsce.depositCollateral(address(weth), amountDeposit);
    }

    function testRevertIfDepositNotAllowedToken() public {
        ERC20Mock randToken = new ERC20Mock(
            "RANDOMTOKEN",
            "RAND",
            USER,
            STARTING_ERC20_BALANCE
        );
        uint256 amountDeposit = 3 ether;

        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        dsce.depositCollateral(address(randToken), amountDeposit);
        vm.stopPrank();
    }

    function testCanDepositAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce
            .getAccountInformation(USER);

        uint256 expectedDscMinted = 0;
        uint256 expectedDepositAmountInUsd = dsce.getTokenAmountFromUsd(
            weth,
            collateralValueInUsd
        );
        assertEq(totalDscMinted, expectedDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmountInUsd);
    }

    function testRevertsIfTransferFromFails() public {
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedTransferFrom mockDsc = new MockFailedTransferFrom();
        tokenAddresses = [address(mockDsc)];
        priceFeedAddresses = [ethUsdPriceFeed];
        vm.prank(owner);
        DSCEngine mockDsce = new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(mockDsc)
        );
        mockDsc.mint(USER, AMOUNT_COLLATERAL);

        vm.prank(owner);
        mockDsc.transferOwnership(address(mockDsce));
        // Arrange - USER
        vm.startPrank(USER);
        ERC20Mock(address(mockDsc)).approve(
            address(mockDsce),
            AMOUNT_COLLATERAL
        );
        // Act / Assert
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDsce.depositCollateral(address(mockDsc), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    //! Redeem Tests
    function testRedeemSucess() public depositedCollateral {
        vm.startPrank(USER);
        dsce.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRevertsIfTransferFails() public {
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedTransfer mockDsc = new MockFailedTransfer();
        tokenAddresses = [address(mockDsc)];
        priceFeedAddresses = [ethUsdPriceFeed];
        vm.prank(owner);
        DSCEngine mockDsce = new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(mockDsc)
        );
        mockDsc.mint(USER, AMOUNT_COLLATERAL);

        vm.prank(owner);
        mockDsc.transferOwnership(address(mockDsce));

        vm.startPrank(USER);
        ERC20Mock(address(mockDsc)).approve(
            address(mockDsce),
            AMOUNT_COLLATERAL
        );

        mockDsce.depositCollateral(address(mockDsc), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDsce.redeemCollateral(address(mockDsc), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testMustRedeemMoreThanZero() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.redeemCollateral(weth, uint256(0));
        vm.stopPrank();
    }

    //! Mint Tests
    function testMintSuccess() public depositedCollateral {
        vm.prank(USER);
        dsce.mintDsc(3 ether);
    }

    //! Health Factor Tests
    function testHealthFactorIsOne() public depositedCollateral {
        vm.startPrank(USER);

        // Mint DSC equivalent to half of the collateral value
        // Collateral: 10 ETH -> $20,000 (assuming 1 ETH = 2000 USD)
        // To achieve health factor of 1, mint DSC worth $10,000
        uint256 dscToMint = 10000 ether; // Minting exactly half the collateral value
        dsce.mintDsc(dscToMint);

        uint256 userHealthFactor = dsce.getHealthFactor(USER);

        // The health factor should now be exactly 1
        assertEq(userHealthFactor, 1e18); // 1e18 represents 1 in fixed-point math

        vm.stopPrank();
    }

    //! Liquidation Tests

    modifier liquidated() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(
            weth,
            AMOUNT_COLLATERAL,
            AMOUNT_TO_MINT
        );
        vm.stopPrank();
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        uint256 userHealthFactor = dsce.getHealthFactor(USER);

        ERC20Mock(weth).mint(LIQUIDATOR, COLLATERAL_TO_COVER);

        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(dsce), COLLATERAL_TO_COVER);
        dsce.depositCollateralAndMintDsc(
            weth,
            COLLATERAL_TO_COVER,
            AMOUNT_TO_MINT
        );
        dsc.approve(address(dsce), AMOUNT_TO_MINT);
        dsce.liquidate(weth, USER, AMOUNT_TO_MINT); // We are covering their whole debt
        vm.stopPrank();
        _;
    }

    function testLiquidationPayoutIsCorrect() public liquidated {
        uint256 liquidatorWethBalance = ERC20Mock(weth).balanceOf(LIQUIDATOR);
        uint256 expectedWeth = dsce.getTokenAmountFromUsd(
            weth,
            AMOUNT_TO_MINT
        ) +
            (dsce.getTokenAmountFromUsd(weth, AMOUNT_TO_MINT) /
                dsce.getLiquidationBonus());
        uint256 hardCodedExpected = 6_111_111_111_111_111_110;
        assertEq(liquidatorWethBalance, hardCodedExpected);
        assertEq(liquidatorWethBalance, expectedWeth);
    }

    function testCantLiquidateGoodHealthFactor()
        public
        depositedCollateralAndMintedDsc
    {
        ERC20Mock(weth).mint(LIQUIDATOR, COLLATERAL_TO_COVER);

        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(dsce), COLLATERAL_TO_COVER);
        dsce.depositCollateralAndMintDsc(
            weth,
            COLLATERAL_TO_COVER,
            AMOUNT_TO_MINT
        );
        dsc.approve(address(dsce), AMOUNT_TO_MINT);

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorGood.selector);
        dsce.liquidate(weth, USER, AMOUNT_TO_MINT);
        vm.stopPrank();
    }

    //! View Function Tests
    function testLiquidationPrecision() public {
        uint256 expectedLiquidationPrecision = 100;
        uint256 actualLiquidationPrecision = dsce.getLiquidationPrecision();
        assertEq(actualLiquidationPrecision, expectedLiquidationPrecision);
    }
}

// contract MaliciousReentrant {
//     DSCEngine public dsce;
//     address public tokenCollateral;

//     constructor(address _dsce, address _tokenCollateral) {
//         dsce = DSCEngine(_dsce);
//         tokenCollateral = _tokenCollateral;
//     }

//     function attack(uint256 amount) public {
//         // Initial deposit to trigger the reentrant function
//         dsce.depositCollateral(tokenCollateral, amount);
//     }

//     // Fallback function to reenter the contract
//     fallback() external payable {
//         // Try to reenter the depositCollateral function
//         dsce.depositCollateral(tokenCollateral, 1 ether);
//     }
// }
