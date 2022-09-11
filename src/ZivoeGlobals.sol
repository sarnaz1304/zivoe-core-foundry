// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

import "./OpenZeppelin/Ownable.sol";

/// @dev    This contract handles the global variables for the Zivoe protocol.
contract ZivoeGlobals is Ownable {

    // ---------------------
    //    State Variables
    // ---------------------

    address public DAO;       /// @dev The ZivoeDAO.sol contract.
    address public ITO;       /// @dev The ZivoeITO.sol contract.
    address public RET;       /// @dev The ZivoeRET.sol contract.
    address public stJTT;     /// @dev The ZivoeRewards.sol ($zJTT) contract.
    address public stSTT;     /// @dev The ZivoeRewards.sol ($zSTT) contract.
    address public stZVE;     /// @dev The ZivoeRewards.sol ($ZVE) contract.
    address public vestZVE;   /// @dev The ZivoeRewardsVesting.sol ($ZVE) vesting contract.
    address public YDL;       /// @dev The ZivoeYDL.sol contract.
    address public zJTT;      /// @dev The ZivoeTranches.sol ($zJTT) contract.
    address public zSTT;      /// @dev The ZivoeTranches.sol ($zSTT) contract.
    address public ZVE;       /// @dev The ZivoeToken.sol contract.
    address public ZVL;       /// @dev The one and only ZivoeLabs.
    address public GOV;       /// @dev The Governor contract.
    address public TLC;       /// @dev The Timelock contract.

    /// @dev This ratio represents the maximum size allowed for junior tranche, relative to senior tranche.
    ///      A value of 3,000 represent 30%, thus junior tranche at maximum can be 20% the size of senior tranche.
    uint256 public maxTrancheRatioBPS = 3000;

    /// @dev These two values control the min/max $ZVE minted per stablecoin deposited to ZivoeTranches.sol.
    uint256 public minZVEPerJTTMint = 0;
    uint256 public maxZVEPerJTTMint = 0.01 * 10**18;

    /// @dev These values represent basis points ratio between zJTT.totalSupply():zSTT.totalSupply() for maximum rewards (affects above slope).
    uint256 public lowerRatioIncentive = 1000;
    uint256 public upperRatioIncentive = 2500;

    mapping(address => bool) public isKeeper;    /// @dev Whitelist for keepers, responsible for pre-initiating actions.

    // -----------
    // Constructor
    // -----------

    /// @notice Initializes the ZivoeGlobals.sol contract.
    constructor() { }



    // ------------
    //    Events
    // ------------

    /// @notice This event is emitted when updateKeeper() is called.
    /// @param  account The address whose status as a keeper is being modified.
    /// @param  status The new status of "account".
    event UpdatedKeeperStatus(address account, bool status);

    /// @notice This event is emitted when updateMaxTrancheRatio() is called.
    /// @param  oldValue The old value of maxTrancheRatioBPS.
    /// @param  newValue The new value of maxTrancheRatioBPS.
    event UpdatedMaxTrancheRatioBPS(uint256 oldValue, uint256 newValue);

    /// @notice This event is emitted when updateMinZVEPerJTTMint() is called.
    /// @param  oldValue The old value of minZVEPerJTTMint.
    /// @param  newValue The new value of minZVEPerJTTMint.
    event UpdatedMinZVEPerJTTMint(uint256 oldValue, uint256 newValue);

    /// @notice This event is emitted when updateMaxZVEPerJTTMint() is called.
    /// @param  oldValue The old value of maxZVEPerJTTMint.
    /// @param  newValue The new value of maxZVEPerJTTMint.
    event UpdatedMaxZVEPerJTTMint(uint256 oldValue, uint256 newValue);

    /// @notice This event is emitted when updateLowerRatioIncentive() is called.
    /// @param  oldValue The old value of lowerRatioJTT.
    /// @param  newValue The new value of lowerRatioJTT.
    event UpdatedLowerRatioIncentive(uint256 oldValue, uint256 newValue);

    /// @notice This event is emitted when updateUpperRatioIncentive() is called.
    /// @param  oldValue The old value of upperRatioJTT.
    /// @param  newValue The new value of upperRatioJTT.
    event UpdatedUpperRatioIncentive(uint256 oldValue, uint256 newValue);


    // ---------------
    //    Modifiers
    // ---------------

    modifier onlyZVL() {
        require(_msgSender() == ZVL, "ZivoeGlobals::onlyZVL() _msgSender() != ZVL");
        _;
    }

    // ---------------
    //    Functions
    // ---------------

    // TODO: Consider automating DAO transferOwnership() in this function.

    /// @notice Initialze the variables within this contract (after all contracts have been deployed).
    /// @dev    This function should only be called once.
    /// @param  globals Array of addresses representing all core system contracts.
    function initializeGlobals(address[] calldata globals) external onlyOwner {

        require(DAO == address(0), "ZivoeGlobals::initializeGlobals() DAO != address(0)");

        DAO     = globals[0];
        ITO     = globals[1];
        RET     = globals[2];
        stJTT   = globals[3];
        stSTT   = globals[4];
        stZVE   = globals[5];
        vestZVE = globals[6];
        YDL     = globals[7];
        zJTT    = globals[8];
        zSTT    = globals[9];
        ZVE     = globals[10];
        ZVL     = globals[11];
        GOV     = globals[12];
        TLC     = globals[13];
        
    }

    /// @notice Updates thitelist for keepers, responsible for pre-initiating actions.
    /// @dev    Only callable by ZVL.
    /// @param  keeper The address of the keeper.
    /// @param  status The status to assign to the "keeper" (true = allowed, false = restricted).
    function updateKeeper(address keeper, bool status) external onlyZVL {
        emit UpdatedKeeperStatus(keeper, status);
        isKeeper[keeper] = status;
    }

    // TODO: Discuss upper-bound on maxTrancheRatioBPS.

    /// @notice Updates the maximum size of junior tranche, relative to senior tranche.
    /// @dev    A value of 2,000 represent 20% (basis points), meaning the junior tranche 
    ///         at maximum can be 20% the size of senior tranche.
    /// @param  ratio The new ratio value.
    function updateMaxTrancheRatio(uint256 ratio) external onlyOwner {
        require(ratio <= 5000, "ZivoeGlobals::updateMaxTrancheRatio() ratio > 5000");
        emit UpdatedMaxTrancheRatioBPS(maxTrancheRatioBPS, ratio);
        maxTrancheRatioBPS = ratio;
    }

    /// @notice Updates the min $ZVE minted per stablecoin deposited to ZivoeTranches.sol.
    /// @param  min Minimum $ZVE minted per stablecoin.
    function updateMinZVEPerJTTMint(uint256 min) external onlyOwner {
        require(min < maxZVEPerJTTMint, "ZivoeGlobals::updateMinZVEPerJTTMint() min >= maxZVEPerJTTMint");
        emit UpdatedMinZVEPerJTTMint(minZVEPerJTTMint, min);
        minZVEPerJTTMint = min;
    }

    /// @notice Updates the max $ZVE minted per stablecoin deposited to ZivoeTranches.sol.
    /// @param  max Maximum $ZVE minted per stablecoin.
    function updateMaxZVEPerJTTMint(uint256 max) external onlyOwner {
        require(max < 0.1 * 10**18, "ZivoeGlobals::updateMaxZVEPerJTTMint() max >= 0.1 * 10**18");
        emit UpdatedMaxZVEPerJTTMint(maxZVEPerJTTMint, max);
        maxZVEPerJTTMint = max; 
    }

    /// @notice Updates the lower ratio between tranches for minting incentivization model.
    /// @param  lowerRatio The lower ratio to handle incentivize thresholds.
    function updateLowerRatioIncentive(uint256 lowerRatio) external onlyOwner {
        require(lowerRatio < upperRatioIncentive, "ZivoeGlobals::updateLowerRatioIncentive() lowerRatio >= upperRatioIncentive");
        emit UpdatedLowerRatioIncentive(lowerRatioIncentive, lowerRatio);
        lowerRatioIncentive = lowerRatio; 
    }

    // TODO: Discuss upper-bound on upperRatioIncentive.

    /// @notice Updates the upper ratio between tranches for minting incentivization model.
    /// @param  upperRatio The upper ratio to handle incentivize thresholds.
    function updateUpperRatioIncentives(uint256 upperRatio) external onlyOwner {
        require(upperRatio <= 5000, "ZivoeGlobals::updateUpperRatioIncentive() upperRatio > 5000");
        emit UpdatedUpperRatioIncentive(upperRatioIncentive, upperRatio);
        upperRatioIncentive = upperRatio; 
    }

}