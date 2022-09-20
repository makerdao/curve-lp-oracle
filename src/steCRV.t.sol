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
    function store(address, bytes32, bytes32) external;
}

interface ERC20 {
    function balanceOf(address) external returns (uint256);
    function approve(address, uint256) external;
}

interface StethLike {
    function getPooledEthByShares(uint256) external view returns (uint256);
    function getSharesByPooledEth(uint256) external view returns (uint256);
}

// Using a different interface here to avoid polluting the CurvePoolLike
// interface in CurveLPOracle.sol with functions only needed for testing.
interface CurvePoolMutableLike {
    function add_liquidity(uint256[2] calldata, uint256) external payable returns (uint256);
    function remove_liquidity(uint256, uint256[2] calldata) external returns (uint256);
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

contract Evil {
    ERC20 constant STETH = ERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    CurveLPOracle public immutable oracle;
    CurvePoolMutableLike public immutable pool;

    constructor(CurveLPOracle _oracle) payable {
        oracle = _oracle;
        address _pool = _oracle.pool();
        pool = CurvePoolMutableLike(_pool);
        STETH.approve(_pool, type(uint256).max);
    }

    function attack() external {
        // We'll not worry about where we get ETH or stETH for the attack.
        // We just deposit everything we have.
        uint256[2] memory amounts;
        uint256 ethBal = address(this).balance;
        amounts[0] = ethBal;
        amounts[1] = STETH.balanceOf(address(this));
        uint256 lpAmount = pool.add_liquidity{value: ethBal}(amounts, 0);  // accept any slippage
        uint256[2] memory minAmountsOut;  // leave zero to accept any slippage
        pool.remove_liquidity(lpAmount, minAmountsOut);  // this will trigger the fallback function during execution
    }

    receive() external payable {
        oracle.poke();
    }
}

contract ETHstETHPoolTest is DSTest {

    uint256 constant WAD = 10**18;
    address constant ADDRESS_PROVIDER = 0x0000000022D53366457F9d5E68Ec105046FC4383;
    address constant POOL             = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address constant ETH_ORACLE       = 0x64DE91F5A373Cd4c28de3600cB34C7C6cE410C85;
    address constant STECRV           = 0x06325440D014e39736583c165C2963BA99fAf14E;
    address constant STETH            = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    Hevm hevm;
    CurveLPOracleFactory factory;
    address[] orbs;
    CurveLPOracle oracle;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        factory = new CurveLPOracleFactory(ADDRESS_PROVIDER);
        orbs.push(ETH_ORACLE);
        orbs.push(address(new MockOracle()));
        oracle  = CurveLPOracle(payable(factory.build(address(this), POOL, "steCRV", orbs, true)));
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
        assertEq(oracle.src(), STECRV);
        assertTrue(oracle.wat() == "steCRV");
        assertEq(oracle.ncoins(), orbs.length);
        for (uint256 i = 0; i < orbs.length; i++) {
            assertTrue(orbs[i] == oracle.orbs(i)); 
        }
        assertTrue(oracle.nonreentrant());
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

    function testFail_reentrant_poke() public {
        uint256 endowment = oracle.pool().balance;  // we'll double the amount of Ether in the pool
        Evil evil = new Evil{value: endowment}(oracle);

        // Give approximately the same amount of stETH
        uint256 shares = StethLike(STETH).getSharesByPooledEth(endowment);
        hevm.store(
            STETH,
            keccak256(abi.encode(address(evil), uint256(0))),
            bytes32(shares)
        );
        assertEq(ERC20(STETH).balanceOf(address(evil)), StethLike(STETH).getPooledEthByShares(shares));

        uint256 p_ETH = OracleLike(orbs[0]).read();
        MockOracle(orbs[1]).setPrice(p_ETH);  // for simplicity, assume price(stETH) == price(ETH)

        // uncomment to examine numerical effects if using unsafe implementation
//        uint256 p_virt = CurvePoolLike(POOL).get_virtual_price();
//        uint256 expectation = p_virt * p_ETH / WAD;

        evil.attack();

        // uncomment to examine numerical effects if using unsafe implementation
//        (bytes32 val,) = oracle.peep();
//        assertEq(expectation, uint256(val));
    }
}
