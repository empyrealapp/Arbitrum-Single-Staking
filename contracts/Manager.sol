// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./utils/ContractGuard.sol";
import "./interfaces/IBasisAsset.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IGovernanceIncentiveCalculator.sol";
import "./types/AccessControlled.sol";

contract Manager is AccessControlled, ContractGuard {
    using SafeERC20 for IERC20;
    using Address for address;

    /* ========= CONSTANT VARIABLES ======== */

    uint256 public constant PERIOD = 12 hours;

    /* ========== STATE VARIABLES ========== */

    // flags
    bool public initialized = false;

    // epoch
    uint256 public startTime;
    uint256 public epoch = 0;

    // core components
    IOracle public empyrealOracle;
    IOracle public firmamentOracle;
    IVault public vault;
    IBasisAsset public arbitrum;
    IGovernanceIncentiveCalculator governanceIncentiveCalculator;

    // price
    uint256 public empyrealPriceOne;
    uint256 public empyrealPriceCeiling;

    /* =================== Added variables =================== */
    uint256 public previousEpochEmpyrealPrice;
    uint256 public previousEpochFirmamentPrice;

    address public enrichmentFund;
    uint256 public enrichmentFundPercent;

    /* =================== Events =================== */

    event Initialized(address indexed executor, uint256 at);
    event TreasuryFunded(uint256 timestamp, uint256 growth);
    event EnrichmentFundFunded(uint256 timestamp, uint256 growth);
    event ArbitrumVaultFunded(uint256 timestamp, uint256 _amount);
    event UpdateCalculator(IGovernanceIncentiveCalculator newCalculator);

    /* =================== Modifier =================== */

    modifier checkCondition() {
        require(block.timestamp >= startTime, "Treasury: not started yet");

        _;
    }

    modifier checkEpoch() {
        require(
            block.timestamp >= nextEpochPoint(),
            "Treasury: not opened yet"
        );

        _;

        epoch += 1;
    }

    modifier notInitialized() {
        require(!initialized, "Treasury: already initialized");

        _;
    }

    /* ========== VIEW FUNCTIONS ========== */

    function isInitialized() public view returns (bool) {
        return initialized;
    }

    // epoch
    function nextEpochPoint() public view returns (uint256) {
        return startTime + (epoch * PERIOD);
    }

    // oracle
    function getEmpyrealPrice() public view returns (uint256 empyrealPrice) {
        try IOracle(empyrealOracle).consult(empyreal(), 1e18) returns (
            uint144 price
        ) {
            return uint256(price);
        } catch {
            revert(
                "Treasury: failed to consult EMPYREAL price from the oracle"
            );
        }
    }

    function getFirmamentPrice() public view returns (uint256 firmamentPrice) {
        try IOracle(firmamentOracle).consult(firmament(), 1e18) returns (
            uint144 price
        ) {
            return uint256(price);
        } catch {
            revert(
                "Treasury: failed to consult FIRMAMENT price from the oracle"
            );
        }
    }

    function getEmpyrealUpdatedPrice()
        public
        view
        returns (uint256 _empyrealPrice)
    {
        try IOracle(empyrealOracle).twap(empyreal(), 1e18) returns (
            uint144 price
        ) {
            return uint256(price);
        } catch {
            revert(
                "Treasury: failed to consult EMPYREAL price from the oracle"
            );
        }
    }

    function getFirmamentUpdatedPrice()
        public
        view
        returns (uint256 _firmamentPrice)
    {
        try IOracle(firmamentOracle).twap(firmament(), 1e18) returns (
            uint144 price
        ) {
            return uint256(price);
        } catch {
            revert(
                "Treasury: failed to consult FIRMAMENT price from the oracle"
            );
        }
    }

    /* ========== GOVERNANCE ========== */

    constructor(IAuthority _authority) AccessControlled(_authority) {}

    function initialize(
        IOracle _empyrealOracle,
        IOracle _firmamentOracle,
        IVault _vault,
        IGovernanceIncentiveCalculator _governanceIncentiveCalculator,
        IBasisAsset _arbitrum,
        uint256 _startTime
    ) public onlyController notInitialized {
        empyrealOracle = _empyrealOracle;
        firmamentOracle = _firmamentOracle;
        governanceIncentiveCalculator = _governanceIncentiveCalculator;
        arbitrum = _arbitrum;
        vault = _vault;
        startTime = _startTime;

        initialized = true;
        emit Initialized(msg.sender, block.number);
    }

    function setOracles(
        IOracle _empyrealOracle,
        IOracle _firmamentOracle
    ) external onlyController {
        empyrealOracle = _empyrealOracle;
        firmamentOracle = _firmamentOracle;
    }

    function setGovernanceIncentiveCalculator(
        IGovernanceIncentiveCalculator newCalc
    ) external onlyController {
        governanceIncentiveCalculator = newCalc;
        emit UpdateCalculator(newCalc);
    }

    /* ========== MUTABLE FUNCTIONS ========== */

    function _updatePrices() internal {
        try IOracle(empyrealOracle).update() {} catch {}
        try IOracle(firmamentOracle).update() {} catch {}
    }

    function getEmpyrealCirculatingSupply() public view returns (uint256) {
        IERC20 empyrealErc20 = IERC20(empyreal());
        return empyrealErc20.totalSupply();
    }

    function _sendToVault(uint256 _amount) internal {
        // address _firmament = firmament();
        // IBasisAsset(_firmament).mint(address(this), _amount);

        // IERC20(_firmament).safeApprove(address(vault), 0);
        // IERC20(_firmament).safeApprove(address(vault), _amount);
        vault.allocateGovernanceIncentive(_amount);

        emit ArbitrumVaultFunded(block.timestamp, _amount);
    }

    function allocateGovernanceIncentive()
        external
        onlyOneBlock
        checkCondition
        checkEpoch
    {
        // _updatePrices();
        uint arbitrumPrice = 1 ether;
        uint firmamentPriceInArb = 175 ether;
        _sendToVault(
            governanceIncentiveCalculator.calculateGrowth(
                arbitrumPrice,
                firmamentPriceInArb,
                address(vault),
                arbitrum
            )
        );
    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external onlyController {
        // do not allow to drain core tokens
        require(address(_token) != address(empyreal()), "empyreal");
        require(address(_token) != address(firmament()), "firmament");
        _token.safeTransfer(_to, _amount);
    }
}
