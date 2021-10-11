// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.9;

import "ds-test/test.sol";

import "./CurveLPOracle.sol";

contract MockCurveRegistry {
    mapping (address => uint256) ncoins;
    function addPool(address _pool, uint256 _ncoins) external {
        ncoins[_pool] = _ncoins;
    }
    function get_n_coins(address _pool) external view returns (uint256[2] memory ncoins_) {
        ncoins_[0] = ncoins[_pool];
        ncoins_[1] = 42;  // return nonsense value so it's obvious if this is accessed when it shouldn't be
    }
}

contract CurveLPOracleFactoryTest is DSTest {
    address[] orbs;
    MockCurveRegistry registry;
    CurveLPOracleFactory factory;

    function setUp() public {
        registry = new MockCurveRegistry();
        registry.addPool(address(0x9001), 3);
        factory = new CurveLPOracleFactory(address(registry));
        orbs.push(address(0x1));
        orbs.push(address(0x2));
        orbs.push(address(0x3));
    }

    function test_build() public {
        CurveLPOracle oracle = CurveLPOracle(factory.build(address(0x123), address(0x9001), "CRVPOOL", orbs));
        assertTrue(factory.isOracle(address(oracle)));
        assertEq(oracle.wards(address(factory)), 0);
        assertEq(oracle.wards(address(0x123)), 1);
        assertTrue(oracle.pool() == address(0x9001));
        assertTrue(oracle.wat() == "CRVPOOL");
        assertEq(oracle.ncoins(), orbs.length);
        for (uint256 i = 0; i < orbs.length; i++) {
            assertTrue(orbs[i] == oracle.orbs(i));
        }
    }
}