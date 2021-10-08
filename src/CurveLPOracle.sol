// SPDX-License-Identifier: GPL-3.0-or-later

/// CurveLPOracle.sol

// Copyright (C) 2017-2020 Maker Ecosystem Growth Holdings, INC.

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

interface CurvePool {
    function coins(uint256) external view returns (address);
    function get_virtual_price() external view returns (uint256);
}

interface OracleLike {
    function read() external view returns (uint256);
}

contract CurveLPOracle {

    // --- Auth ---
    mapping (address => uint256) public wards;                                       // Addresses with admin authority
    function rely(address _usr) external auth { wards[_usr] = 1; emit Rely(_usr); }  // Add admin
    function deny(address _usr) external auth { wards[_usr] = 0; emit Deny(_usr); }  // Remove admin
    modifier auth {
        require(wards[msg.sender] == 1, "UNIV2LPOracle/not-authorized");
        _;
    }

    // stopped, hop, and zph are packed into single slot to reduce SLOADs;
    // this outweighs the added bitmasking overhead.
    uint8   public stopped;         // Stop/start ability to update
    uint16  public hop = 1 hours;   // Minimum time in between price updates
    uint232 public zph;             // Time of last price update plus hop

    // --- Whitelisting ---
    mapping (address => uint256) public bud;
    modifier toll { require(bud[msg.sender] == 1, "CurveLPOracle/not-whitelisted"); _; }

    struct Feed {
        uint128 val;  // Price
        uint128 has;  // Is price valid
    }

    Feed internal cur;  // Current price (mem slot 0x3)
    Feed internal nxt;  // Queued price  (mem slot 0x4)

    address[] public orbs;  // array of price feeds for pool assets, same order as in the pool

    address public immutable pool;    // Address of underlying Curve pool
    bytes32 public immutable wat;     // Label of token whose price is being tracked
    uint256 public immutable ncoins;  // Number of tokens in underlying Curve pool

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Stop();
    event Start();
    event Step(uint256 hop);
    event Link(uint256 id, address orb);
//    event Value(uint128 curVal, uint128 nxtVal);
//    event Kiss(address a);
//    event Diss(address a);

    // --- Init ---
    constructor(address _pool, bytes32 _wat, address[] memory _orbs) {
        require(_pool != address(0), "CurveLPOracle/invalid-pool");

        wards[msg.sender] = 1;
        emit Rely(msg.sender);

        pool = _pool;
        wat  = _wat;

        uint256 n;
        unchecked {  // avoid SafeMath overhead on ++
            for (;; n++) {
                (bool ok,) = _pool.call(abi.encodeWithSignature("coins(uint256)", n));
                if (!ok) break;
                require(_orbs[n] != address(0), "CurveLPOracle/invalid-orb");
                orbs.push(_orbs[n]);
            }
        }
        ncoins = n;
    }

    function stop() external auth {
        stopped = 1;
        delete cur;
        delete nxt;
        zph = 0;
        emit Stop();
    }

    function start() external auth {
        stopped = 0;
        emit Start();
    }

    function step(uint256 _hop) external auth {
        require(_hop <= type(uint16).max, "CurveLPOracle/invalid-hop");
        hop = uint16(_hop);
        emit Step(_hop);
    }

    function link(uint256 _id, address _orb) external auth {
        require(_orb != address(0), "CurveLPOracle/invalid-orb");
        require(_id < ncoins, "CurveLPOracle/invalid-orb-index");
        orbs[_id] = _orb;
        emit Link(_id, _orb);
    }
}
