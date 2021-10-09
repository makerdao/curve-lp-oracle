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

    function test_constructor_and_public_fields() public {
        oracle = new CurveLPOracle(address(pool), "123CRV", orbs);
        assertEq(oracle.wards(address(this)), 1);
        assertTrue(oracle.pool() == address(pool));
        assertTrue(oracle.wat() == "123CRV");
        assertEq(oracle.ncoins(), pool.ncoins());
        for (uint256 i = 0; i < orbs.length; i++) {
            assertTrue(oracle.orbs(i) == orbs[i]);
        }
    }

    function testFail_constructor_pool_addr_zero() public {
        new CurveLPOracle(address(0), "123CRV", orbs);
    }

    function testFail_constructor_too_few_orbs() public {
        address[] memory palantirs = new address[](2);
        palantirs[0] = address(0x111);
        palantirs[1] = address(0x222);
        new CurveLPOracle(address(pool), "123CRV", palantirs);
    }

    function testFail_constructor_zero_orb() public {
        orbs[1] = address(0);
        new CurveLPOracle(address(pool), "123CRV", orbs);
    }

    function test_stop() public {
        // TODO
    }

    function testFail_stop_not_authed() public {
        oracle.deny(address(this));
        oracle.stop();
    }

    function test_start() public {
        oracle.stop();
        oracle.start();
        assertEq(oracle.stopped(), 0);
    }

    function testFail_start_not_authed() public {
        oracle.stop();
        oracle.deny(address(this));
        oracle.start();
    }

    function test_link() public {
        oracle.link(0, address(0x123));
        assertTrue(oracle.orbs(0) == address(0x123));
        oracle.link(2, address(0x321));
        assertTrue(oracle.orbs(2) == address(0x321));
        assertTrue(oracle.orbs(0) == address(0x123));  // should be unaffected
    }

    function testFail_link_zero_orb() public {
        oracle.link(0, address(0));
    }

    function testFail_link_invalid_index() public {
        oracle.link(oracle.ncoins(), address(0x42));
    }
}
