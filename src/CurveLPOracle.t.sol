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

interface Hevm {
    function warp(uint256) external;
    function load(address, bytes32 slot) external returns (bytes32);
}

contract MockCurvePool {
    uint256 public get_virtual_price;
    address public lp_token;
    bool public locked;
    function setVirtualPrice(uint256 _vp) external {
        get_virtual_price = _vp;
    }
    function lock() external {
        locked = true;
    }
    function remove_liquidity(uint256 _amount, uint256[2] calldata _min_amounts) external view {
        _amount; _min_amounts;  // silence warnings
        require(!locked);
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
    uint16  constant DEFAULT_HOP = 3600;  // 1 hour in seconds

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
        oracle = new CurveLPOracle(address(this), address(pool), "123CRV", orbs, false);
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
        oracle = new CurveLPOracle(address(0x123), address(pool), "123CRV", orbs, false);
        assertEq(oracle.wards(address(0x123)), 1);
        assertTrue(oracle.pool() == address(pool));
        assertTrue(oracle.wat() == "123CRV");
        assertEq(oracle.ncoins(), orbs.length);
        assertTrue(!oracle.nonreentrant());
        for (uint256 i = 0; i < orbs.length; i++) {
            assertTrue(oracle.orbs(i) == orbs[i]);
        }
    }

    function testFail_constructor_ward_zero() public {
        new CurveLPOracle(address(0), address(pool), "123CRV", orbs, false);
    }

    function testFail_constructor_pool_addr_zero() public {
        new CurveLPOracle(address(0x123), address(0), "123CRV", orbs, false);
    }

    function testFail_constructor_zero_orb() public {
        orbs[1] = address(0);
        new CurveLPOracle(address(0x123), address(pool), "123CRV", orbs, false);
    }

    function test_step() public {
        uint16  oldHop =  oracle.hop();
        uint16  newHop =  oldHop + 1800;  // newHop > oldHop
        uint232 zph    =  oracle.zph();
        uint256 zzz    =  oracle.zzz();
        assertTrue(zph >= oldHop);  // we'll test the < case later

        // increase hop
        oracle.step(newHop);

        assertEq(oracle.hop(), newHop);
        assertEq(oracle.zph(), zph - oldHop + newHop);
        assertEq(oracle.zzz(), zzz);

        // decrease hop
        oracle.step(oldHop);

        assertEq(oracle.hop(), oldHop);
        assertEq(oracle.zph(), zph);  // back to original value
        assertEq(oracle.zzz(), zzz);

        oracle.stop();  // sets zph to zero

        // Because block.timestamp is monotone and zph is always set to block.timestamp + hop in poke(),
        // zph == 0 is the only possible situation in which zph < oldHop can obtain.
        assertTrue(oracle.zph() < oldHop);
        assertEq(oracle.zph(), 0);
        assertEq(oracle.zzz(), 0);

        oracle.step(newHop);

        assertEq(oracle.hop(), newHop);
        assertEq(oracle.zph(), 0);  // unset, so no change
        assertEq(oracle.zzz(), 0);

        oracle.step(0);
        assertEq(oracle.hop(), 0);
        assertEq(oracle.zph(), 0);  // unset, so no change
        assertEq(oracle.zzz(), 0);

        oracle.step(1);  // 1 != 0
        assertEq(oracle.hop(), 1);
        assertEq(oracle.zph(), 0);  // unset, so no change
        assertEq(oracle.zzz(), 0);
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
        oracle.read();
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


    // This test will fail if the value of `val` at peek does not match memory slot 0x3
    function testCurSlot0x3() public {
        //oracle.poke();                                     // Poke oracle (done in setUp())
        hevm.warp(oracle.zzz() + oracle.hop() + 1);          // Time travel into the future
        oracle.poke();                                       // Poke oracle again
        oracle.kiss(address(this));                          // Whitelist caller
        (bytes32 val, bool has) = oracle.peek();             // Peek oracle price without caller being whitelisted
        assertTrue(has);                                     // Verify oracle has value
        assertTrue(val != bytes32(0));                       // Verify peep returned valid value

        // Load memory slot 0x3
        // Keeps `cur` slot parity with OSMs
        bytes32 curPacked = hevm.load(address(oracle), bytes32(uint256(3)));

        bytes16 memhas;
        bytes16 memcur;
        assembly {
            memhas := curPacked
            memcur := shl(128, curPacked)
        }

        assertTrue(uint256(uint128(memcur)) > 0);          // Assert nxt has value
        assertEq(uint256(val), uint256(uint128(memcur)));  // Assert slot value == cur
        assertEq(uint256(uint128(memhas)), 1);             // Assert slot has == 1
    }

    // This test will fail if the value of `val` at peep does not match memory slot 0x4
    function testNxtSlot0x4() public {
        //oracle.poke();                                   // Poke oracle (done in setUp())
        hevm.warp(oracle.zzz() + oracle.hop() + 1);        // Time travel into the future
        oracle.poke();                                     // Poke oracle again
        oracle.kiss(address(this));                        // Whitelist caller
        (bytes32 val, bool has) = oracle.peep();           // Peep oracle price without caller being whitelisted
        assertTrue(has);                                   // Verify oracle has value
        assertTrue(val != bytes32(0));                     // Verify peep returned valid value

        // Load memory slot 0x4
        // Keeps `nxt` slot parity with OSMs
        bytes32 nxtPacked = hevm.load(address(oracle), bytes32(uint256(4)));

        bytes16 memhas;
        bytes16 memnxt;
        assembly {
            memhas := nxtPacked
            memnxt := shl(128, nxtPacked)
        }

        assertTrue(uint256(uint128(memnxt)) > 0);          // Assert nxt has value
        assertEq(uint256(val), uint256(uint128(memnxt)));  // Assert slot value == nxt
        assertEq(uint256(uint128(memhas)), 1);             // Assert slot has == 1
    }

    function test_constructor_nonreentrant() public {
        oracle = new CurveLPOracle(address(0x123), address(pool), "123CRV", orbs, true);
        assertTrue(oracle.nonreentrant());
    }

    function doReentrantPokeOnFreshOracle(CurveLPOracle _oracle) internal {
        _oracle.step(DEFAULT_HOP);
        _oracle.kiss(address(this));

        hevm.warp(_oracle.zph());

        pool.lock();
        assertTrue(_oracle.pass());
        _oracle.poke();
    }

    function test_not_nonreentrant() public {
        oracle = new CurveLPOracle(address(this), address(pool), "123CRV", orbs, false);
        doReentrantPokeOnFreshOracle(oracle);
    }

    function testFail_nonreentrant() public {
        oracle = new CurveLPOracle(address(this), address(pool), "123CRV", orbs, true);
        doReentrantPokeOnFreshOracle(oracle);
    }
}
