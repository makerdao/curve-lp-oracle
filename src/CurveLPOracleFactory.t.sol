// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2021 Dai Foundation

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity 0.8.13;

import "ds-test/test.sol";

import "./CurveLPOracle.sol";
import { MockCurvePool } from "./CurveLPOracle.t.sol";

contract MockAddressProvider {
    address immutable REGISTRY;
    constructor(address registry) {
        REGISTRY = registry;
    }
    function get_registry() external view returns (address) {
        return REGISTRY;
    }
}

contract MockCurveRegistry {
    mapping (address => uint256) ncoins;
    function addPool(address _pool, uint256 _ncoins) external {
        ncoins[_pool] = _ncoins;
    }
    function get_n_coins(address _pool) external view returns (uint256[2] memory ncoins_) {
        ncoins_[0] = 42;  // return nonsense value so it's obvious if this is accessed when it shouldn't be
        ncoins_[1] = ncoins[_pool];
    }
}

contract CurveLPOracleFactoryTest is DSTest {
    address[] orbs;
    MockCurveRegistry registry;
    CurveLPOracleFactory factory;
    MockCurvePool pool;

    function setUp() public {
        registry = new MockCurveRegistry();
        pool = new MockCurvePool();
        registry.addPool(address(pool), 3);
        MockAddressProvider addressProvider = new MockAddressProvider(address(registry));
        factory = new CurveLPOracleFactory(address(addressProvider));
        orbs.push(address(0x1));
        orbs.push(address(0x2));
        orbs.push(address(0x3));
    }

    function test_build() public {
        CurveLPOracle oracle = CurveLPOracle(payable(factory.build(address(0x123), address(pool), "CRVPOOL", orbs, false)));
        assertEq(oracle.wards(address(factory)), 0);
        assertEq(oracle.wards(address(0x123)), 1);
        assertTrue(oracle.pool() == address(pool));
        assertTrue(oracle.wat() == "CRVPOOL");
        assertEq(oracle.ncoins(), orbs.length);
        for (uint256 i = 0; i < orbs.length; i++) {
            assertTrue(orbs[i] == oracle.orbs(i));
        }
        assertTrue(!oracle.nonreentrant());

        oracle = CurveLPOracle(payable(factory.build(address(0x123), address(pool), "CRVPOOL", orbs, true)));
        assertTrue(oracle.nonreentrant());
    }
}
