// SPDX-License-Identifier: GPL-3.0-or-later

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

pragma solidity 0.8.9;

import "ds-test/test.sol";

import "./CurveLPOracle.sol";

interface Hevm {
    function store(address, bytes32, bytes32) external;
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

    uint256 constant WAD = 10**18;
    address constant REGISTRY   = 0x7D86446dDb609eD0F5f8684AcF30380a356b2B4c;
    address constant POOL       = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address constant ETH_ORACLE = 0x64DE91F5A373Cd4c28de3600cB34C7C6cE410C85;

    Hevm hevm;
    CurveLPOracleFactory factory;
    address[] orbs;
    CurveLPOracle oracle;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        factory = new CurveLPOracleFactory(REGISTRY);
        orbs.push(ETH_ORACLE);
        orbs.push(address(new MockOracle()));
        oracle  = CurveLPOracle(factory.build(address(this), POOL, "steCRV", orbs));
        oracle.kiss(address(this));

        // Whitelist steCRV oracle to read from the ETH oracle
        hevm.store(
            ETH_ORACLE,
            keccak256(abi.encode(address(oracle), uint256(4))),
            bytes32(uint256(1))
        );

        // Whitelist this contract to read from the ETH oracle
        hevm.store(
            ETH_ORACLE,
            keccak256(abi.encode(address(this), uint256(4))),
            bytes32(uint256(1))
        );
    }

    function test_build() public {
        assertEq(oracle.wards(address(factory)), 0);
        assertEq(oracle.wards(address(this)), 1);
        assertTrue(oracle.pool() == POOL);
        assertTrue(oracle.wat() == "steCRV");
        assertEq(oracle.ncoins(), orbs.length);
        for (uint256 i = 0; i < orbs.length; i++) {
            assertTrue(orbs[i] == oracle.orbs(i)); 
        }
    }

    function test_poke() public {
        uint256 p_ETH = OracleLike(orbs[0]).read();
        uint256 p_steETH = 3_479 * WAD / 1000;
        MockOracle(orbs[1]).setPrice(p_steETH);
        uint256 min = p_ETH > p_steETH ? p_steETH : p_ETH;
        uint256 p_virt = CurvePoolLike(POOL).get_virtual_price();
        uint256 expectation = p_virt * min / WAD;

        oracle.poke();

        (bytes32 val, bool has) = oracle.peep();
        assertTrue(has);
        assertEq(expectation, uint256(val));
    }
}
