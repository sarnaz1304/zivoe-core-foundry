// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.16;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Votes.sol";

interface Votes_IZivoeGlobals {
    function stZVE() external view returns (address);
}

abstract contract StakedVoting is ERC20Votes {

    /// @notice Custom virtual function for viewing GBL (ZivoeGlobals).
    function GBL() public view virtual returns (address) { return address(0); }

    /**
     * @dev Move voting power when tokens are transferred.
     *
     * Emits a {IVotes-DelegateVotesChanged} event.
     */
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(ERC20Votes) {
        if (Votes_IZivoeGlobals(GBL()).stZVE() == address(0) || (to != Votes_IZivoeGlobals(GBL()).stZVE() && from != Votes_IZivoeGlobals(GBL()).stZVE())) {
            ERC20Votes._afterTokenTransfer(from, to, amount);
        }
    }
}
