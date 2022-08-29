// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

import "../TESTS_Basic/Utility.sol";

import "../calc/YieldMachete.sol";

contract calc_MacheteTest is Utility {
    //function setUp() public view {
    //}
    uint256 targetRatio = uint256(1 ether)/uint256(3);
    uint256 juniorSupply = 10000 ether;
    uint256 seniorSupply = 30000 ether;
    function test_sanity_1() public view {
        assert(YieldMachete.dLil(targetRatio,juniorSupply,seniorSupply)>(1 ether));
    }
    function test_sanity_2() public view {
        assert(YieldMachete.dLil(targetRatio,juniorSupply,seniorSupply)<(3 ether));
    }




   
}
