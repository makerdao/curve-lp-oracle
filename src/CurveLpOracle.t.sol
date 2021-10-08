// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

import "ds-test/test.sol";

import "./CurveLpOracle.sol";

contract CurveLpOracleTest is DSTest {
    CurveLpOracle oracle;

    function setUp() public {
        oracle = new CurveLpOracle();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
