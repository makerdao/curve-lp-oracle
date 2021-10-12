// SPDX-License-Identifier: GPL-3.0-or-later

// Copyright (C) 2017-2021 Maker Ecosystem Growth Holdings, INC.

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

pragma solidity 0.8.9;

import "ds-test/test.sol";

import "./CurveLPOracle.sol";

interface Hevm {
    function warp(uint256) external;
}

contract MockOracle {
    uint256 private price;
    function read() external view returns (uint256) {
        return price;
    }
    function setPrice(uint256 _price) external {
        price = _price;
    }
}

contract ETHstETHPoolTest is DSTest {

    address constant REGISTRY = address(0x7D86446dDb609eD0F5f8684AcF30380a356b2B4c);
    address constant POOL = address(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);

    Hevm hevm;
    CurveLPOracleFactory factory;
    address[] orbs;
    CurveLPOracle oracle;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        factory = new CurveLPOracleFactory(REGISTRY);
        orbs.push(address(new MockOracle()));
        orbs.push(address(new MockOracle()));
        oracle  = CurveLPOracle(factory.build(address(this), POOL, "steCRV", orbs));
    }

    function test_build() public {
        assertTrue(factory.isOracle(address(oracle)));
        assertEq(oracle.wards(address(factory)), 0);
        assertEq(oracle.wards(address(this)), 1);
        assertTrue(oracle.pool() == POOL);
        assertTrue(oracle.wat() == "steCRV");
        assertEq(oracle.ncoins(), orbs.length);
        for (uint256 i = 0; i < orbs.length; i++) {
            assertTrue(orbs[i] == oracle.orbs(i)); 
        }
    }
}
