// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

// testGetTimeout
// testPriceRevertOnStaleCheck

import {Test} from "forge-std/Test.sol";
import {OracleLib} from "src/libraries/OracleLib.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract OracleLibTest is Test {
    using OracleLib for AggregatorV3Interface;
    
    MockV3Aggregator aggregator;
    uint8 public constant DECIMALS = 8;
    int256 public constant INITIAL_PRICE = 2000 ether;
    uint256 private constant TIMEOUT = 3 hours; // 3 * 60 * 60 = 10800 seconds

    function setUp() public {
        aggregator = new MockV3Aggregator(DECIMALS, INITIAL_PRICE);
    }

    function testGetTimeout() public pure {
        uint256 expectedTimeout = 3 hours;
        assertEq(OracleLib.getTimeout(), expectedTimeout);
    }

    function testPriceRevertOnStaleCheck() public {
        vm.warp(block.timestamp + TIMEOUT + 1 seconds);

        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        AggregatorV3Interface(address(aggregator)).staleCheckLatestRoundData();
    }
}