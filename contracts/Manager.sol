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
import "./interfaces/ICamelotRouter.sol";
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
    IVault public vault;
    IBasisAsset public arbitrum;
    IBasisAsset public USDC;
    IGovernanceIncentiveCalculator governanceIncentiveCalculator;
    ICamelotRouter public router;

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

    /* ========== GOVERNANCE ========== */

    constructor(IAuthority _authority) AccessControlled(_authority) {}

    function initialize(
        IVault _vault,
        IGovernanceIncentiveCalculator _governanceIncentiveCalculator,
        IBasisAsset _usdc,
        IBasisAsset _arbitrum,
        ICamelotRouter _router,
        uint256 _startTime
    ) public onlyController notInitialized {
        governanceIncentiveCalculator = _governanceIncentiveCalculator;
        arbitrum = _arbitrum;
        USDC = _usdc;
        vault = _vault;
        startTime = _startTime;
        router = _router;

        initialized = true;
        emit Initialized(msg.sender, block.number);
    }

    function setRouter(ICamelotRouter _router) external onlyController {
        router = _router;
    }

    function setGovernanceIncentiveCalculator(
        IGovernanceIncentiveCalculator newCalc
    ) external onlyController {
        governanceIncentiveCalculator = newCalc;
        emit UpdateCalculator(newCalc);
    }

    /* ========== MUTABLE FUNCTIONS ========== */

    function getEmpyrealCirculatingSupply() public view returns (uint256) {
        IERC20 empyrealErc20 = IERC20(empyreal());
        return empyrealErc20.totalSupply();
    }

    function _sendToVault(uint256 _amount) internal {
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
        address[] memory route = new address[](3);
        route[0] = address(arbitrum);
        route[1] = address(USDC);
        route[2] = address(firmament());
        uint firmamentPriceInArb = router.getAmountsOut(1 ether, route)[2];
        _sendToVault(
            governanceIncentiveCalculator.calculateGrowth(
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
