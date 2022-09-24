// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.16;

import "./libraries/OpenZeppelin/Ownable.sol";

/// @dev    This contract handles the global variables for the Zivoe protocol.
contract ZivoeGlobals is Ownable {

    // ---------------------
    //    State Variables
    // ---------------------

    address public DAO;       /// @dev The ZivoeDAO.sol contract.
    address public ITO;       /// @dev The ZivoeITO.sol contract.
    address public stJTT;     /// @dev The ZivoeRewards.sol ($zJTT) contract.
    address public stSTT;     /// @dev The ZivoeRewards.sol ($zSTT) contract.
    address public stZVE;     /// @dev The ZivoeRewards.sol ($ZVE) contract.
    address public vestZVE;   /// @dev The ZivoeRewardsVesting.sol ($ZVE) vesting contract.
    address public YDL;       /// @dev The ZivoeYDL.sol contract.
    address public zJTT;      /// @dev The ZivoeTrancheToken.sol ($zJTT) contract.
    address public zSTT;      /// @dev The ZivoeTrancheToken.sol ($zSTT) contract.
    address public ZVE;       /// @dev The ZivoeToken.sol contract.
    address public ZVL;       /// @dev The Zivoe Laboratory.
    address public ZVT;       /// @dev The ZivoeTranches.sol contract.
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

    /// @dev Tracks net defaults in system.
    uint256 public defaults;

    mapping(address => bool) public isKeeper;               /// @dev Whitelist for keepers, responsible for pre-initiating actions.
    mapping(address => bool) public isLocker;               /// @dev Whitelist for lockers, for DAO interactions and accounting accessibility.
    mapping(address => bool) public stablecoinWhitelist;    /// @dev Whitelist for acceptable stablecoins throughout system (ZVE, YDL).



    // -----------
    // Constructor
    // -----------

    /// @notice Initializes the ZivoeGlobals.sol contract.
    constructor() { }



    // ------------
    //    Events
    // ------------

    /// @notice This event is emitted when decreaseNetDefaults() is called.
    /// @param amount Amount of defaults decreased.
    /// @param updatedDefaults Total defaults funds after event.
    event DefaultsDecreased(uint256 amount, uint256 updatedDefaults);

    /// @notice This event is emitted when increaseNetDefaults() is called.
    /// @param amount Amount of defaults increased.
    /// @param updatedDefaults Total defaults after event.
    event DefaultsIncreased(uint256 amount, uint256 updatedDefaults);

    /// @notice Emitted during updateIsLocker().
    /// @param  locker  The locker whose status as a locker is being modified.
    /// @param  allowed The boolean value to assign.
    event UpdatedLockerStatus(address locker, bool allowed);

    /// @notice This event is emitted when updateIsKeeper() is called.
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

    /// @notice This event is emitted when updateStablecoinWhitelist() is called.
    /// @param  asset The stablecoin to update.
    /// @param  allowed The boolean value to assign.
    event UpdatedStablecoinWhitelist(address asset, bool allowed);



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

    /// @notice Call when a default is resolved, decreases net defaults system-wide.
    function decreaseDefaults(uint256 amount) external {
        require(isLocker[_msgSender()], "ZivoeGlobals::decreaseDefaults() !isLocker[_msgSender()]");
        defaults -= amount;
        emit DefaultsDecreased(amount, defaults);
    }

    /// @notice Call when a default occurs, increases net defaults system-wide.
    function increaseDefaults(uint256 amount) external {
        require(isLocker[_msgSender()], "ZivoeGlobals::increaseDefaults() !isLocker[_msgSender()]");
        defaults += amount;
        emit DefaultsIncreased(amount, defaults);
    }

    /// @notice Initialze the variables within this contract (after all contracts have been deployed).
    /// @dev    This function should only be called once.
    /// @param  globals Array of addresses representing all core system contracts.
    function initializeGlobals(address[] calldata globals) external onlyOwner {

        require(DAO == address(0), "ZivoeGlobals::initializeGlobals() DAO != address(0)");

        DAO     = globals[0];
        ITO     = globals[1];
        stJTT   = globals[2];
        stSTT   = globals[3];
        stZVE   = globals[4];
        vestZVE = globals[5];
        YDL     = globals[6];
        zJTT    = globals[7];
        zSTT    = globals[8];
        ZVE     = globals[9];
        ZVL     = globals[10];
        GOV     = globals[11];
        TLC     = globals[12];
        ZVT     = globals[13];

        stablecoinWhitelist[0x6B175474E89094C44Da98b954EedeAC495271d0F] = true; // DAI
        stablecoinWhitelist[0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48] = true; // USDC
        stablecoinWhitelist[0x853d955aCEf822Db058eb8505911ED77F175b99e] = true; // FRAX
        stablecoinWhitelist[0xdAC17F958D2ee523a2206206994597C13D831ec7] = true; // USDT


        // TODO: Consider automating DAO transferOwnership() in this function.
        
    }

    /// @notice Updates the keeper whitelist.
    /// @param  keeper The address of the keeper.
    /// @param  status The status to assign to the "keeper" (true = allowed, false = restricted).
    function updateIsKeeper(address keeper, bool status) external onlyZVL {
        emit UpdatedKeeperStatus(keeper, status);
        isKeeper[keeper] = status;
    }

    /// @notice Modifies the locker whitelist.
    /// @param  locker  The locker to update.
    /// @param  allowed The value to assign (true = permitted, false = prohibited).
    function updateIsLocker(address locker, bool allowed) external onlyZVL {
        emit UpdatedLockerStatus(locker, allowed);
        isLocker[locker] = allowed;
    }

    /// @notice Modifies the stablecoin whitelist.
    /// @param  stablecoin The stablecoin to update.
    /// @param  allowed The value to assign (true = permitted, false = prohibited).
    function updateStablecoinWhitelist(address stablecoin, bool allowed) external onlyZVL {
        emit UpdatedStablecoinWhitelist(stablecoin, allowed);
        stablecoinWhitelist[stablecoin] = allowed;
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
