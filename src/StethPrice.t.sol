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

import "./StethPrice.sol";

interface Hevm {
    function store(address, bytes32, bytes32) external;
}

contract ETHstETHPoolTest is DSTest {

    uint256 constant WAD = 10**18;
    address constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address constant WSTETH_ORACLE = 0x2F73b6567B866302e132273f67661fB89b5a66F2;

    Hevm hevm;
    StethPrice stethPrice;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

        stethPrice = new StethPrice(STETH, WSTETH_ORACLE);

        // Whitelist price converter to read from wstETH oracle
        hevm.store(
            WSTETH_ORACLE,
            keccak256(abi.encode(address(stethPrice), uint256(4))),
            bytes32(uint256(1))
        );

        // Whitelist this contract to read from the wstETH oracle
        hevm.store(
            WSTETH_ORACLE,
            keccak256(abi.encode(address(this), uint256(4))),
            bytes32(uint256(1))
        );

        stethPrice.kiss(address(this));
    }

    function test_read_and_peek() public {
        uint256 expected = OracleLike(WSTETH_ORACLE).read() * WAD / StethLike(STETH).getPooledEthByShares(1 ether);
        assertEq(stethPrice.read(), expected);

        (, bool has) = OracleLike(WSTETH_ORACLE).peek();
        (uint256 actual, bool haz) = stethPrice.peek();
        assertEq(actual, expected);
        assertTrue(has == haz);
    }
}
