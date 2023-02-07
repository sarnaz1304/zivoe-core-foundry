// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.16;

import "./ZivoeLocker.sol";

import "../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

interface ZivoeTranches_IZivoeGlobals {
    /// @notice Returns the address of the ZivoeToken.sol contract.
    function ZVE() external view returns (address);

    /// @notice Returns the address of the ZivoeITO.sol contract.
    function ITO() external view returns (address);

    /// @notice Returns the address of the ZivoeDAO.sol contract.
    function DAO() external view returns (address);

    /// @notice Returns the address of the Zivoe Laboratory.
    function ZVL() external view returns (address);

    /// @notice Returns the address of the ZivoeTrancheToken.sol ($zSTT) contract.
    function zSTT() external view returns (address);

    /// @notice Returns the address of the ZivoeTrancheToken.sol ($zJTT) contract.
    function zJTT() external view returns (address);

    /// @notice Handles WEI standardization of a given asset amount (i.e. 6 decimal precision => 18 decimal precision).
    /// @param amount The amount of a given "asset".
    /// @param asset The asset (ERC-20) from which to standardize the amount to WEI.
    /// @return standardizedAmount The above amount standardized to 18 decimals.
    function standardize(uint256 amount, address asset) external view returns (uint256 standardizedAmount);

    /// @notice Returns total circulating supply of zSTT and zJTT, accounting for defaults via markdowns.
    /// @return zSTTSupply zSTT.totalSupply() adjusted for defaults.
    /// @return zJTTSupply zJTT.totalSupply() adjusted for defaults.
    function adjustedSupplies() external view returns (uint256 zSTTSupply, uint256 zJTTSupply);

    /// @notice Returns the "maxTrancheRatioBIPS" variable.
    /// @dev This ratio represents the maximum size allowed for junior tranche, relative to senior tranche.
    ///      A value of 2,000 represent 20%, thus junior tranche at maximum can be 20% the size of senior tranche.
    function maxTrancheRatioBIPS() external view returns (uint256);

    /// @notice This function will verify if a given stablecoin has been whitelisted for use throughout system (ZVE, YDL).
    /// @param stablecoin address of the stablecoin to verify acceptance for.
    /// @return whitelisted Will equal "true" if stabeloin is acceptable, and "false" if not.
    function stablecoinWhitelist(address stablecoin) external view returns (bool whitelisted);

    /// @notice Returns the "lowerRatioIncentive" variable.
    /// @return lowerRatioIncentive This value represents basis points ratio between 
    /// zJTT.totalSupply():zSTT.totalSupply() for maximum rewards.
    function lowerRatioIncentive() external view returns (uint256 lowerRatioIncentive);

    /// @notice Returns the "upperRatioIncentive" variable.
    /// @return upperRatioIncentive This value represents basis points ratio between
    /// zJTT.totalSupply():zSTT.totalSupply() for maximum rewards.
    function upperRatioIncentive() external view returns (uint256 upperRatioIncentive);

    /// @notice Returns the "minZVEPerJTTMint" variable.
    /// @return minZVEPerJTTMint This value controls the min $ZVE minted per stablecoin deposited to ZivoeTranches.sol.
    function minZVEPerJTTMint() external view returns (uint256 minZVEPerJTTMint);

    /// @notice Returns the "maxZVEPerJTTMint" variable.
    /// @return maxZVEPerJTTMint This value controls the max $ZVE minted per stablecoin deposited to ZivoeTranches.sol.
    function maxZVEPerJTTMint() external view returns (uint256 maxZVEPerJTTMint);
}

interface ZivoeTranches_IERC20Mintable {
    /// @notice Creates ERC20 tokens and assigns them to an address, increasing the total supply.
    /// @param account The address to send the newly created tokens to.
    /// @param amount The amount of tokens to create and send.
    function mint(address account, uint256 amount) external;
}

/// @notice  This contract will facilitate ongoing liquidity provision to Zivoe tranches - Junior, Senior.
///          This contract will be permissioned by $zJTT and $zSTT to call mint().
///          This contract will support a whitelist for stablecoins to provide as liquidity.
contract ZivoeTranches is ZivoeLocker, ReentrancyGuard {

    using SafeERC20 for IERC20;

    // ---------------------
    //    State Variables
    // ---------------------

    address public immutable GBL;   /// @dev The ZivoeGlobals contract.

    bool public tranchesUnlocked;   /// @dev Prevents contract from supporting functionality until unlocked.
    bool public paused;             /// @dev Temporary mechanism for pausing deposits.

    uint256 private constant BIPS = 10000;



    // -----------------
    //    Constructor
    // -----------------

    /// @notice Initializes the ZivoeTranches.sol contract.
    /// @param _GBL The ZivoeGlobals contract.
    constructor(address _GBL) {
        GBL = _GBL;
    }



    // ------------
    //    Events
    // ------------

    /// @notice Emitted during depositJunior().
    /// @param  account The account depositing stablecoins to junior tranche.
    /// @param  asset The stablecoin deposited.
    /// @param  amount The amount of stablecoins deposited.
    /// @param  incentives The amount of incentives ($ZVE) distributed.
    event JuniorDeposit(address indexed account, address indexed asset, uint256 amount, uint256 incentives);

    /// @notice Emitted during depositSenior().
    /// @param  account The account depositing stablecoins to senior tranche.
    /// @param  asset The stablecoin deposited.
    /// @param  amount The amount of stablecoins deposited.
    /// @param  incentives The amount of incentives ($ZVE) distributed.
    event SeniorDeposit(address indexed account, address indexed asset, uint256 amount, uint256 incentives);



    // ---------------
    //    Functions
    // ---------------

    modifier notPaused() {
        require(!paused, "ZivoeTranches::whenPaused() notPaused");
        _;
    }


    // ---------------
    //    Functions
    // ---------------

    /// @notice Permission for owner to call pushToLocker().
    function canPush() public override pure returns (bool) {
        return true;
    }

    /// @notice Permission for owner to call pullFromLocker().
    function canPull() public override pure returns (bool) {
        return true;
    }

    /// @notice Permission for owner to call pullFromLockerPartial().
    function canPullPartial() public override pure returns (bool) {
        return true;
    }

    /// @notice This pulls capital from the DAO, does any necessary pre-conversions, and escrows ZVE for incentives.
    /// @param asset The asset to pull from the DAO.
    /// @param amount The amount of asset to pull from the DAO.
    /// @param  data Accompanying transaction data.
    function pushToLocker(address asset, uint256 amount, bytes calldata data) external override onlyOwner {
        require(asset == ZivoeTranches_IZivoeGlobals(GBL).ZVE(), "ZivoeTranches::pushToLocker() asset != ZivoeTranches_IZivoeGlobals(GBL).ZVE()");

        IERC20(asset).safeTransferFrom(owner(), address(this), amount);
    }

    /// @notice Checks if stablecoins deposits into the Junior Tranche are open.
    /// @param  amount The amount to deposit.
    /// @param  asset The asset (stablecoin) to deposit.
    /// @return open Will return "true" if the deposits into the Junior Tranche are open.
    function isJuniorOpen(uint256 amount, address asset) public view returns (bool open) {
        uint256 convertedAmount = ZivoeTranches_IZivoeGlobals(GBL).standardize(amount, asset);
        (uint256 seniorSupp, uint256 juniorSupp) = ZivoeTranches_IZivoeGlobals(GBL).adjustedSupplies();
        return convertedAmount + juniorSupp < seniorSupp * ZivoeTranches_IZivoeGlobals(GBL).maxTrancheRatioBIPS() / BIPS;
    }

    /// @notice Pauses or unpauses the contract, enabling or disabling depositJunior() and depositSenior().
    function switchPause() external {
        require(
            _msgSender() == ZivoeTranches_IZivoeGlobals(GBL).ZVL(), 
            "ZivoeTranches::switchPause() _msgSender() != ZivoeTranches_IZivoeGlobals(GBL).ZVL()"
        );
        paused = !paused;
    }

    /// @notice Deposit stablecoins into the junior tranche.
    /// @dev    Mints Zivoe Junior Tranche ($zJTT) tokens in 1:1 ratio.
    /// @param  amount The amount to deposit.
    /// @param  asset The asset (stablecoin) to deposit.
    function depositJunior(uint256 amount, address asset) external notPaused nonReentrant {
        require(ZivoeTranches_IZivoeGlobals(GBL).stablecoinWhitelist(asset), "ZivoeTranches::depositJunior() !ZivoeTranches_IZivoeGlobals(GBL).stablecoinWhitelist(asset)");
        require(tranchesUnlocked, "ZivoeTranches::depositJunior() !tranchesUnlocked");

        address depositor = _msgSender();

        IERC20(asset).safeTransferFrom(depositor, ZivoeTranches_IZivoeGlobals(GBL).DAO(), amount);
        
        uint256 convertedAmount = ZivoeTranches_IZivoeGlobals(GBL).standardize(amount, asset);

        require(isJuniorOpen(amount, asset),"ZivoeTranches::depositJunior() !isJuniorOpen(amount, asset)");

        uint256 incentives = rewardZVEJuniorDeposit(convertedAmount);
        emit JuniorDeposit(depositor, asset, amount, incentives);

        // NOTE: Ordering important, transfer ZVE rewards prior to minting zJTT() due to totalSupply() changes.
        IERC20(ZivoeTranches_IZivoeGlobals(GBL).ZVE()).safeTransfer(depositor, incentives);
        ZivoeTranches_IERC20Mintable(ZivoeTranches_IZivoeGlobals(GBL).zJTT()).mint(depositor, convertedAmount);
    }

    /// @notice Deposit stablecoins into the senior tranche.
    /// @dev    Mints Zivoe Senior Tranche ($zSTT) tokens in 1:1 ratio.
    /// @param  amount The amount to deposit.
    /// @param  asset The asset (stablecoin) to deposit.
    function depositSenior(uint256 amount, address asset) external notPaused nonReentrant {
        require(ZivoeTranches_IZivoeGlobals(GBL).stablecoinWhitelist(asset), "ZivoeTranches::depositSenior() !ZivoeTranches_IZivoeGlobals(GBL).stablecoinWhitelist(asset)");
        require(tranchesUnlocked, "ZivoeTranches::depositSenior() !tranchesUnlocked");

        address depositor = _msgSender();

        IERC20(asset).safeTransferFrom(depositor, ZivoeTranches_IZivoeGlobals(GBL).DAO(), amount);
        
        uint256 convertedAmount = ZivoeTranches_IZivoeGlobals(GBL).standardize(amount, asset);

        uint256 incentives = rewardZVESeniorDeposit(convertedAmount);

        emit SeniorDeposit(depositor, asset, amount, incentives);

        // NOTE: Ordering important, transfer ZVE rewards prior to minting zJTT() due to totalSupply() changes.
        IERC20(ZivoeTranches_IZivoeGlobals(GBL).ZVE()).safeTransfer(depositor, incentives);
        ZivoeTranches_IERC20Mintable(ZivoeTranches_IZivoeGlobals(GBL).zSTT()).mint(depositor, convertedAmount);
    }

    /// @notice Returns the total rewards in $ZVE for a certain junior tranche deposit amount.
    /// @dev Input amount MUST be in WEI (use GBL.standardize(amount, asset)).
    /// @dev Output amount MUST be in WEI.
    /// @param deposit The amount supplied to the junior tranche.
    /// @return reward The rewards in $ZVE to be received.
    function rewardZVEJuniorDeposit(uint256 deposit) public view returns(uint256 reward) {

        (uint256 seniorSupp, uint256 juniorSupp) = ZivoeTranches_IZivoeGlobals(GBL).adjustedSupplies();

        uint256 avgRate;    // The avg ZVE per stablecoin deposit reward, used for reward calculation.

        uint256 diffRate = ZivoeTranches_IZivoeGlobals(GBL).maxZVEPerJTTMint() - ZivoeTranches_IZivoeGlobals(GBL).minZVEPerJTTMint();

        uint256 startRatio = juniorSupp * BIPS / seniorSupp;
        uint256 finalRatio = (juniorSupp + deposit) * BIPS / seniorSupp;
        uint256 avgRatio = (startRatio + finalRatio) / 2;

        if (avgRatio <= ZivoeTranches_IZivoeGlobals(GBL).lowerRatioIncentive()) {
            // Handle max case (Junior:Senior is 10% or less).
            avgRate = ZivoeTranches_IZivoeGlobals(GBL).maxZVEPerJTTMint();
        } else if (avgRatio >= ZivoeTranches_IZivoeGlobals(GBL).upperRatioIncentive()) {
            // Handle min case (Junior:Senior is 25% or more).
            avgRate = ZivoeTranches_IZivoeGlobals(GBL).minZVEPerJTTMint();
        } else {
            // Handle in-between case, avgRatio domain = (1000, 2500).
            avgRate = ZivoeTranches_IZivoeGlobals(GBL).maxZVEPerJTTMint() - diffRate * (avgRatio - 1000) / (1500);
        }

        reward = avgRate * deposit / 1 ether;

        // Reduce if ZVE balance < reward.
        if (IERC20(ZivoeTranches_IZivoeGlobals(GBL).ZVE()).balanceOf(address(this)) < reward) {
            reward = IERC20(ZivoeTranches_IZivoeGlobals(GBL).ZVE()).balanceOf(address(this));
        }
    }

    /// @notice Returns the total rewards in $ZVE for a certain senior tranche deposit amount.
    /// @dev Input amount MUST be in WEI (use GBL.standardize(amount, asset)).
    /// @dev Output amount MUST be in WEI.
    /// @param deposit The amount supplied to the senior tranche.
    /// @return reward The rewards in $ZVE to be received.
    function rewardZVESeniorDeposit(uint256 deposit) public view returns(uint256 reward) {

        (uint256 seniorSupp, uint256 juniorSupp) = ZivoeTranches_IZivoeGlobals(GBL).adjustedSupplies();

        uint256 avgRate;    // The avg ZVE per stablecoin deposit reward, used for reward calculation.

        uint256 diffRate = ZivoeTranches_IZivoeGlobals(GBL).maxZVEPerJTTMint() - ZivoeTranches_IZivoeGlobals(GBL).minZVEPerJTTMint();

        uint256 startRatio = juniorSupp * BIPS / seniorSupp;
        uint256 finalRatio = juniorSupp * BIPS / (seniorSupp + deposit);
        uint256 avgRatio = (startRatio + finalRatio) / 2;

        if (avgRatio <= ZivoeTranches_IZivoeGlobals(GBL).lowerRatioIncentive()) {
            // Handle max case (Junior:Senior is 10% or less).
            avgRate = ZivoeTranches_IZivoeGlobals(GBL).minZVEPerJTTMint();
        } else if (avgRatio >= ZivoeTranches_IZivoeGlobals(GBL).upperRatioIncentive()) {
            // Handle min case (Junior:Senior is 25% or more).
            avgRate = ZivoeTranches_IZivoeGlobals(GBL).maxZVEPerJTTMint();
        } else {
            // Handle in-between case, avgRatio domain = (1000, 2500).
            avgRate = ZivoeTranches_IZivoeGlobals(GBL).minZVEPerJTTMint() + diffRate * (avgRatio - 1000) / (1500);
        }

        reward = avgRate * deposit / 1 ether;

        // Reduce if ZVE balance < reward.
        if (IERC20(ZivoeTranches_IZivoeGlobals(GBL).ZVE()).balanceOf(address(this)) < reward) {
            reward = IERC20(ZivoeTranches_IZivoeGlobals(GBL).ZVE()).balanceOf(address(this));
        }
    }

    /// @notice Unlocks this contract for distributions, sets some initial variables.
    function unlock() external {
        require(_msgSender() == ZivoeTranches_IZivoeGlobals(GBL).ITO(), "ZivoeTranches::unlock() _msgSender() != ZivoeTranches_IZivoeGlobals(GBL).ITO()");
        
        tranchesUnlocked = true;
    }

}