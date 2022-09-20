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

        // Whitelist price converter to read from wstETH stethPrice
        hevm.store(
            WSTETH_ORACLE,
            keccak256(abi.encode(address(stethPrice), uint256(4))),
            bytes32(uint256(1))
        );

        // Whitelist this contract to read from the wstETH stethPrice
        hevm.store(
            WSTETH_ORACLE,
            keccak256(abi.encode(address(this), uint256(4))),
            bytes32(uint256(1))
        );
    }

    function test_read_and_peek() public {
        stethPrice.kiss(address(this));

        uint256 expected = OracleLike(WSTETH_ORACLE).read() * WAD / StethLike(STETH).getPooledEthByShares(1 ether);
        assertEq(stethPrice.read(), expected);

        (, bool has) = OracleLike(WSTETH_ORACLE).peek();
        (uint256 actual, bool haz) = stethPrice.peek();
        assertEq(actual, expected);
        assertTrue(has == haz);
    }

    function test_kiss_single() public {
        assertTrue(stethPrice.bud(address(this)) == 0);         // Verify caller is not whitelisted
        stethPrice.kiss(address(this));                         // Whitelist caller
        assertTrue(stethPrice.bud(address(this)) == 1);         // Verify caller is whitelisted
        stethPrice.kiss(address(this));
        assertTrue(stethPrice.bud(address(this)) == 1);         // Ensure idempotency
    }

    function testFail_kiss_single_not_authed() public {
        stethPrice.deny(address(this));                         // Remove owner
        stethPrice.kiss(address(this));                         // Attempt to whitelist caller
    }

    function testFail_kiss_single_zero_address() public {
        stethPrice.kiss(address(0));                            // Attempt to whitelist 0 address
    }

    function test_diss_single() public {
        stethPrice.kiss(address(this));                         // Whitelist caller
        assertTrue(stethPrice.bud(address(this)) == 1);         // Verify caller is whitelisted
        stethPrice.diss(address(this));                         // Remove caller from whitelist
        assertTrue(stethPrice.bud(address(this)) == 0);         // Verify caller is not whitelisted
        stethPrice.diss(address(this));
        assertTrue(stethPrice.bud(address(this)) == 0);         // Ensure idempotency
    }

    function testFail_diss_single() public {
        stethPrice.deny(address(this));                         // Remove owner
        stethPrice.diss(address(this));                         // Attempt to remove caller from whitelist
    }

    function testFail_peek_not_whitelisted() public {
        stethPrice.diss(address(this));  // Ensure caller not authorized to read prices
        stethPrice.peek();
    }

    function testFail_read_not_whitelisted() public {
        stethPrice.diss(address(this));  // Ensure caller not authorized to read prices
        stethPrice.read();
    }

    function test_kiss_and_diss_multiple() public {
        address[] memory guys = new address[](4);
        for (uint256 i = 0; i < guys.length; i++) {
            guys[i] = address(uint160(17 * i + 1));
            assertEq(stethPrice.bud(guys[i]), 0);
        }
        stethPrice.kiss(guys);
        for (uint256 i = 0; i < guys.length; i++) {
            assertEq(stethPrice.bud(guys[i]), 1);
        }
        stethPrice.kiss(guys);  // Idempotency
        for (uint256 i = 0; i < guys.length; i++) {
            assertEq(stethPrice.bud(guys[i]), 1);
        }
        stethPrice.diss(guys);
        for (uint256 i = 0; i < guys.length; i++) {
            assertEq(stethPrice.bud(guys[i]), 0);
        }
        stethPrice.diss(guys);  // Idempotency
        for (uint256 i = 0; i < guys.length; i++) {
            assertEq(stethPrice.bud(guys[i]), 0);
        }
    }

    function testFail_kiss_multiple_not_authed() public {
        stethPrice.deny(address(this));
        address[] memory guys = new address[](4);
        for (uint256 i = 0; i < guys.length; i++) {
            guys[i] = address(uint160(17 * i + 1));
            assertEq(stethPrice.bud(guys[i]), 0);
        }
        stethPrice.kiss(guys);
    }

    function testFail_kiss_multiple_zero_address() public {
        address[] memory guys = new address[](4);
        for (uint256 i = 0; i < guys.length; i++) {
            guys[i] = address(uint160(17 * i + 1));
            assertEq(stethPrice.bud(guys[i]), 0);
        }
        guys[1] = address(0);
        stethPrice.kiss(guys);
    }

    function testFail_diss_multiple_not_authed() public {
        stethPrice.deny(address(this));
        address[] memory guys = new address[](4);
        for (uint256 i = 0; i < guys.length; i++) {
            guys[i] = address(uint160(17 * i + 1));
            assertEq(stethPrice.bud(guys[i]), 0);
        }
        stethPrice.diss(guys);
    }
}
