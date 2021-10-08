// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.9;

import "ds-test/test.sol";

import "./CurveLPOracle.sol";

contract MockCurvePool {
    uint256 public get_virtual_price;
    address[] public coins;

    function setVirtualPrice(uint256 _vp) external {
        get_virtual_price = _vp;
    }
    function addCoin(address a) external {
        coins.push(a);
    }
    function ncoins() external view returns (uint256) {
        return coins.length;
    }
}

contract MockOracle {
}

contract CurveLpOracleTest is DSTest {
    MockCurvePool pool;
    address[] orbs;
    CurveLPOracle oracle;

    function setUp() public {
        pool = new MockCurvePool();
        pool.addCoin(address(0x1));
        pool.addCoin(address(0x2));
        pool.addCoin(address(0x3));
        orbs.push(address(new MockOracle()));
        orbs.push(address(new MockOracle()));
        orbs.push(address(new MockOracle()));
        oracle = new CurveLPOracle(address(pool), "123CRV", orbs);
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
