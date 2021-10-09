// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.9;

import "ds-test/test.sol";

import "./CurveLPOracle.sol";

interface Hevm {
    function warp(uint256) external;
}

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
    uint256 private price;
    function read() external view returns (uint256) {
        return price;
    }
    function setPrice(uint256 _price) external {
        price = _price;
    }
}

contract CurveLpOracleTest is DSTest {
    uint256 constant WAD = 10**18;
    uint256 constant DEFAULT_HOP = 3600;  // 1 hour in seconds

    Hevm hevm;
    MockCurvePool pool;
    address[] orbs;
    CurveLPOracle oracle;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        pool = new MockCurvePool();
        pool.addCoin(address(0x1));
        pool.addCoin(address(0x2));
        pool.addCoin(address(0x3));
        orbs.push(address(new MockOracle()));
        orbs.push(address(new MockOracle()));
        orbs.push(address(new MockOracle()));
        oracle = new CurveLPOracle(address(pool), "123CRV", orbs);
        oracle.step(DEFAULT_HOP);
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
}
