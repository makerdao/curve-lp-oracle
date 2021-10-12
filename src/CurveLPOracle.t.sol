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

contract MockCurvePool {
    uint256 public get_virtual_price;
    function setVirtualPrice(uint256 _vp) external {
        get_virtual_price = _vp;
    }
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

contract CurveLPOracleTest is DSTest {
    uint256 constant WAD = 10**18;
    uint256 constant DEFAULT_HOP = 3600;  // 1 hour in seconds

    Hevm hevm;
    MockCurvePool pool;
    address[] orbs;
    CurveLPOracle oracle;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        pool = new MockCurvePool();
        orbs.push(address(new MockOracle()));
        orbs.push(address(new MockOracle()));
        orbs.push(address(new MockOracle()));
        oracle = new CurveLPOracle(address(pool), orbs.length, "123CRV", orbs);
        oracle.step(DEFAULT_HOP);

        // set up some default price values
        MockOracle(orbs[0]).setPrice(100 * WAD);
        MockOracle(orbs[1]).setPrice(100 * WAD);
        MockOracle(orbs[2]).setPrice(100 * WAD);
        pool.setVirtualPrice(WAD);  // 1

        // Get valid cur and nxt
        oracle.poke();
        hevm.warp(oracle.zph());
        oracle.poke();
    }

    function test_constructor_and_public_fields() public {
        oracle = new CurveLPOracle(address(pool), orbs.length, "123CRV", orbs);
        assertEq(oracle.wards(address(this)), 1);
        assertTrue(oracle.pool() == address(pool));
        assertTrue(oracle.wat() == "123CRV");
        assertEq(oracle.ncoins(), orbs.length);
        for (uint256 i = 0; i < orbs.length; i++) {
            assertTrue(oracle.orbs(i) == orbs[i]);
        }
    }

    function testFail_constructor_pool_addr_zero() public {
        new CurveLPOracle(address(0), orbs.length, "123CRV", orbs);
    }

    function testFail_constructor_too_few_orbs() public {
        new CurveLPOracle(address(pool), orbs.length + 1, "123CRV", orbs);
    }

    function testFail_constructor_too_many_orbs() public {
        new CurveLPOracle(address(pool), orbs.length - 1, "123CRV", orbs);
    }

    function testFail_constructor_zero_orb() public {
        orbs[1] = address(0);
        new CurveLPOracle(address(pool), orbs.length, "123CRV", orbs);
    }

    function test_stop() public {
        oracle.kiss(address(this));  // whitelist for reading
 
        // Check that both current and pending values are non-zero and valid
        (bytes32 val, bool has) = oracle.peek();
        assertGt(uint256(val), 0);
        assertTrue(has);
        (val, has) = oracle.peep();
        assertGt(uint256(val), 0);
        assertTrue(has);

        assertGt(uint256(oracle.zph()), 0);
        assertGt(oracle.zzz(), 0);

        assertEq(oracle.stopped(), 0);
        oracle.stop();
        assertEq(oracle.stopped(), 1);

        // Values should be zero and invalid
        (val, has) = oracle.peek();
        assertEq(uint256(val), 0);
        assertTrue(!has);
        (val, has) = oracle.peep();
        assertEq(uint256(val), 0);
        assertTrue(!has);

        assertEq(uint256(oracle.zph()), 0);
        assertEq(oracle.zzz(), 0);
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

    function test_poke_zph_zzz_pass_peep_peek_read() public {
        oracle.kiss(address(this));

        MockOracle(orbs[0]).setPrice(100 * WAD);
        MockOracle(orbs[1]).setPrice(102 * WAD);
        MockOracle(orbs[2]).setPrice( 98 * WAD);
        pool.setVirtualPrice(105_831 * WAD / 10**5);  // 1.05831

        uint256 hop = oracle.hop();

        hevm.warp(oracle.zph());
        assertTrue(oracle.pass());

        oracle.poke();

        assertEq(oracle.zph(), block.timestamp + hop);
        assertEq(oracle.zzz(), block.timestamp);
        assertTrue(!oracle.pass());

        (bytes32 val, bool has) = oracle.peep();
        assertTrue(has);
        uint256 firstPrice = (98 * WAD) * pool.get_virtual_price() / WAD;  // minimum price used to value all assets
        assertEq(uint256(val), firstPrice);

        hevm.warp(oracle.zph() - 1);  // warp to just before the next possible poke
        assertTrue(!oracle.pass());

        hevm.warp(oracle.zph() + hop / 2);  // warp somewhat beyond next possible poke
        assertTrue(oracle.pass());

        // update values
        MockOracle(orbs[0]).setPrice(101 * WAD);
        MockOracle(orbs[1]).setPrice(105 * WAD);
        MockOracle(orbs[2]).setPrice(103 * WAD);
        pool.setVirtualPrice(106_792 * WAD / 10**5);  // 1.06792

        oracle.poke();

        assertEq(oracle.zph(), block.timestamp + hop);
        assertEq(oracle.zzz(), block.timestamp);
        assertTrue(!oracle.pass());

        (val, has) = oracle.peek();
        assertTrue(has);
        assertEq(uint256(val), firstPrice);
        assertEq(oracle.read(), val);

        (val, has) = oracle.peep();
        assertTrue(has);
        uint256 secondPrice = (101 * WAD) * pool.get_virtual_price() / WAD;  // minimum price used to value all assets
        assertEq(uint256(val), secondPrice);
    }

    function testFail_poke_stopped() public {
        hevm.warp(oracle.zph());
        assertTrue(oracle.pass());
        oracle.stop();
        oracle.poke();
    }

    function test_poke_restarted() public {
        hevm.warp(oracle.zph());
        assertTrue(oracle.pass());
        oracle.stop();
        oracle.start();
        oracle.poke();
    }

    function test_kiss_single() public {
        assertTrue(oracle.bud(address(this)) == 0);         // Verify caller is not whitelisted
        oracle.kiss(address(this));                         // Whitelist caller
        assertTrue(oracle.bud(address(this)) == 1);         // Verify caller is whitelisted
        oracle.kiss(address(this));
        assertTrue(oracle.bud(address(this)) == 1);         // Ensure idempotency
    }

    function testFail_kiss_single_not_authed() public {
        oracle.deny(address(this));                         // Remove owner
        oracle.kiss(address(this));                         // Attempt to whitelist caller
    }

    function testFail_kiss_single_zero_address() public {
        oracle.kiss(address(0));                            // Attempt to whitelist 0 address
    }

    function test_diss_single() public {
        oracle.kiss(address(this));                         // Whitelist caller
        assertTrue(oracle.bud(address(this)) == 1);         // Verify caller is whitelisted
        oracle.diss(address(this));                         // Remove caller from whitelist
        assertTrue(oracle.bud(address(this)) == 0);         // Verify caller is not whitelisted
        oracle.diss(address(this));
        assertTrue(oracle.bud(address(this)) == 0);         // Ensure idempotency
    }

    function testFail_diss_single() public {
        oracle.deny(address(this));                         // Remove owner
        oracle.diss(address(this));                         // Attempt to remove caller from whitelist
    }

    function test_whiltelisting() public {
        oracle.kiss(address(this));
        oracle.peek();
        oracle.peep();
        oracle.read();
    }

    function testFail_peek_not_whitelisted() public {
        oracle.diss(address(this));  // Ensure caller not authorized to read prices
        oracle.peek();
    }

    function testFail_peep_not_whitelisted() public {
        oracle.diss(address(this));  // Ensure caller not authorized to read prices
        oracle.peep();
    }

    function testFail_read_not_whitelisted() public {
        oracle.diss(address(this));  // Ensure caller not authorized to read prices
        oracle.peep();
    }

    function test_kiss_and_diss_multiple() public {
        address[] memory guys = new address[](4);
        for (uint256 i = 0; i < guys.length; i++) {
            guys[i] = address(uint160(17 * i + 1));
            assertEq(oracle.bud(guys[i]), 0);
        }
        oracle.kiss(guys);
        for (uint256 i = 0; i < guys.length; i++) {
            assertEq(oracle.bud(guys[i]), 1);
        }
        oracle.kiss(guys);  // Idempotency
        for (uint256 i = 0; i < guys.length; i++) {
            assertEq(oracle.bud(guys[i]), 1);
        }
        oracle.diss(guys);
        for (uint256 i = 0; i < guys.length; i++) {
            assertEq(oracle.bud(guys[i]), 0);
        }
        oracle.diss(guys);  // Idempotency
        for (uint256 i = 0; i < guys.length; i++) {
            assertEq(oracle.bud(guys[i]), 0);
        }
    }

    function testFail_kiss_multiple_not_authed() public {
        oracle.deny(address(this));
        address[] memory guys = new address[](4);
        for (uint256 i = 0; i < guys.length; i++) {
            guys[i] = address(uint160(17 * i + 1));
            assertEq(oracle.bud(guys[i]), 0);
        }
        oracle.kiss(guys);
    }

    function testFail_kiss_multiple_zero_address() public {
        address[] memory guys = new address[](4);
        for (uint256 i = 0; i < guys.length; i++) {
            guys[i] = address(uint160(17 * i + 1));
            assertEq(oracle.bud(guys[i]), 0);
        }
        guys[1] = address(0);
        oracle.kiss(guys);
    }

    function testFail_diss_multiple_not_authed() public {
        oracle.deny(address(this));
        address[] memory guys = new address[](4);
        for (uint256 i = 0; i < guys.length; i++) {
            guys[i] = address(uint160(17 * i + 1));
            assertEq(oracle.bud(guys[i]), 0);
        }
        oracle.diss(guys);
    }
}
