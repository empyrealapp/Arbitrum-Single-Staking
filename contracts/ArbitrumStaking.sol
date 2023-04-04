// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./utils/ContractGuard.sol";
import "./interfaces/IBasisAsset.sol";
import "./interfaces/IManager.sol";
import "hardhat/console.sol";

abstract contract ArbitrumWrapper {
    using SafeERC20 for IERC20;
    uint constant MULTIPLIER = 225;
    uint constant ANNUAL_PERIODS = 365 * 2;

    address public firmament;
    address public arbitrum;
    uint256 private _totalSupply;
    bool public canAbort = true;
    mapping(address => uint256) private _balances;

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function stake(uint256 amount) public virtual {
        _totalSupply += amount;
        _balances[msg.sender] += amount;
        IERC20(arbitrum).safeTransferFrom(msg.sender, address(this), amount);
    }

    function stakeFor(address _receiver, uint256 amount) public virtual {
        _totalSupply += amount;
        _balances[_receiver] += amount;
        IERC20(arbitrum).safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) public virtual {
        uint256 memberShare = _balances[msg.sender];
        require(
            memberShare >= amount,
            "Horizon: withdraw request greater than staked amount"
        );
        _totalSupply -= amount;
        _balances[msg.sender] -= amount;
        IERC20(arbitrum).safeTransfer(msg.sender, amount);
    }
}

contract ArbitrumStaking is ArbitrumWrapper, Ownable2Step, ContractGuard {
    using SafeERC20 for IERC20;
    using Address for address;

    /* ========== DATA STRUCTURES ========== */

    struct PassengerSeat {
        uint256 lastSnapshotIndex;
        uint256 rewardEarned;
        uint256 epochTimerStart;
        uint256 multiplier;
    }

    struct Snapshot {
        uint256 time;
        uint256 rewardReceived;
        uint256 rewardPerShare;
    }

    /* ========== STATE VARIABLES ========== */

    address public manager;

    // flags
    bool public initialized = false;

    mapping(address => PassengerSeat) public members;
    Snapshot[] public history;

    uint256 public withdrawLockupEpochs;
    uint256 public rewardLockupEpochs;
    uint256 public warmupEpochs = 1;

    /* ========== EVENTS ========== */

    event Initialized(address indexed executor, uint256 at);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event EmergencyWithdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardAdded(address indexed user, uint256 reward);
    event ManagerUpdated(address manager);

    /* ========== Modifiers =============== */

    modifier memberExists() {
        require(
            balanceOf(msg.sender) > 0,
            "Horizon: The member does not exist"
        );
        _;
    }

    modifier updateReward(address member) {
        if (member != address(0)) {
            PassengerSeat memory seat = members[member];
            seat.rewardEarned = earned(member);
            seat.multiplier += getMultiplierPoints(member);
            seat.lastSnapshotIndex = latestSnapshotIndex() + warmupEpochs;
            members[member] = seat;
        }
        _;
    }

    modifier notInitialized() {
        require(!initialized, "Horizon: already initialized");
        _;
    }

    /* ========== GOVERNANCE ========== */

    function initialize(
        address _firmament,
        address _arbitrum,
        address _manager
    ) public notInitialized {
        firmament = _firmament;
        arbitrum = _arbitrum;
        manager = _manager;

        Snapshot memory genesisSnapshot = Snapshot({
            time: block.number,
            rewardReceived: 0,
            rewardPerShare: 0
        });
        history.push(genesisSnapshot);

        initialized = true;
        emit Initialized(msg.sender, block.number);
    }

    /* ========== VIEW FUNCTIONS ========== */

    // =========== Snapshot getters

    function latestSnapshotIndex() public view returns (uint256) {
        return history.length - 1;
    }

    function getLatestSnapshot() internal view returns (Snapshot memory) {
        return history[latestSnapshotIndex()];
    }

    function getLastSnapshotIndexOf(
        address member
    ) public view returns (uint256) {
        return members[member].lastSnapshotIndex;
    }

    function getLastSnapshotOf(
        address member
    ) internal view returns (Snapshot memory) {
        return history[getLastSnapshotIndexOf(member)];
    }

    function epoch() public view returns (uint256) {
        return IManager(manager).epoch();
    }

    function nextEpochPoint() external view returns (uint256) {
        return IManager(manager).nextEpochPoint();
    }

    // =========== Member getters

    function rewardPerShare() public view returns (uint256) {
        return getLatestSnapshot().rewardPerShare;
    }

    function getMultiplierPoints(address member) public view returns (uint256) {
        uint256 latestSnapshot = latestSnapshotIndex();
        uint256 storedSnapshot = getLastSnapshotIndexOf(member);
        if (latestSnapshot <= storedSnapshot) {
            return members[member].multiplier;
        }
        return
            members[member].multiplier +
            balanceOf(member) *
            (latestSnapshot - storedSnapshot);
    }

    function earned(address member) public view returns (uint256) {
        if (getLastSnapshotIndexOf(member) >= epoch()) {
            return members[member].rewardEarned;
        }

        uint256 latestRPS = getLatestSnapshot().rewardPerShare;
        uint256 storedRPS = getLastSnapshotOf(member).rewardPerShare;

        return
            (balanceOf(member) * (latestRPS - storedRPS)) /
            1e18 +
            members[member].rewardEarned;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stake(
        uint256 amount
    ) public override onlyOneBlock updateReward(msg.sender) {
        require(amount > 0, "Horizon: Cannot stake 0");
        super.stake(amount);
        members[msg.sender].epochTimerStart = epoch() + warmupEpochs; // reset timer with warmup
        emit Staked(msg.sender, amount);
    }

    function stakeFor(
        address _recipient,
        uint256 amount
    ) public override onlyOneBlock updateReward(msg.sender) {
        require(amount > 0, "Horizon: Cannot stake 0");
        super.stakeFor(_recipient, amount);
        members[_recipient].epochTimerStart = epoch() + warmupEpochs; // reset timer with warmup
        emit Staked(_recipient, amount);
    }

    function stakeForMany(
        address[] calldata _receivers,
        uint256[] calldata _amounts
    ) public onlyOneBlock {
        for (uint i = 0; i < _receivers.length; i++) {
            address member = _receivers[i];
            uint256 _amount = _amounts[i];

            PassengerSeat memory seat = members[member];
            seat.rewardEarned = earned(member);
            seat.lastSnapshotIndex = latestSnapshotIndex() + warmupEpochs;
            members[member] = seat;

            super.stakeFor(member, _amount);
            members[member].epochTimerStart = epoch(); // reset timer
            emit Staked(member, _amount);
        }
    }

    function withdraw(
        uint256 amount
    ) public override onlyOneBlock memberExists updateReward(msg.sender) {
        require(amount > 0, "Horizon: Cannot withdraw 0");
        require(
            members[msg.sender].epochTimerStart + withdrawLockupEpochs <=
                epoch(),
            "Horizon: still in withdraw lockup"
        );
        claimReward();
        super.withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function emergencyWithdraw(
        uint256 amount
    ) public onlyOneBlock memberExists updateReward(msg.sender) {
        // This is to withdraw in case of emergency with rewards
        // Ensuring that no user can have their funds stuck
        require(amount > 0, "Horizon: Cannot withdraw 0");
        members[msg.sender].epochTimerStart = epoch(); // reset timer
        members[msg.sender].rewardEarned = 0;
        super.withdraw(amount);
        emit EmergencyWithdrawn(msg.sender, amount);
    }

    function exit() external {
        withdraw(balanceOf(msg.sender));
    }

    function getMultiplier(address member) public view returns (uint256) {
        uint256 rewardPoints = members[member].multiplier;
        uint256 reward = members[member].rewardEarned;
        uint balance = balanceOf(member);
        uint multiple = 1e18 +
            (MULTIPLIER * (rewardPoints ** 2 * 1e18)) /
            (ANNUAL_PERIODS * balance) ** 2;
        return (multiple * reward) / 1e18;
    }

    function claimReward() public updateReward(msg.sender) {
        if (epoch() - warmupEpochs <= members[msg.sender].epochTimerStart) {
            members[msg.sender].epochTimerStart = epoch() + 1; // reset timer
            members[msg.sender].rewardEarned = 0;
        } else {
            uint256 reward = members[msg.sender].rewardEarned;
            if (reward > 0) {
                require(
                    members[msg.sender].epochTimerStart + rewardLockupEpochs <=
                        epoch(),
                    "Horizon: still in reward lockup"
                );
                uint totalReward = getMultiplier(msg.sender);
                members[msg.sender].epochTimerStart = epoch() + 1; // reset timer
                members[msg.sender].rewardEarned = 0;
                members[msg.sender].multiplier = 0;
                IBasisAsset(firmament).mint(msg.sender, totalReward);
                emit RewardPaid(msg.sender, reward);
            }
        }
    }

    function setManager(address _newManager) external onlyOwner {
        manager = _newManager;
        emit ManagerUpdated(_newManager);
    }

    function allocateGovernanceIncentive(uint256 amount) external onlyOneBlock {
        require(msg.sender == manager, "only manager");

        require(amount > 0, "ArbitrumStaking: Cannot allocate 0");
        require(
            totalSupply() > 0,
            "ArbitrumStaking: Cannot allocate when totalSupply is 0"
        );

        // Create & add new snapshot
        uint256 prevRPS = getLatestSnapshot().rewardPerShare;
        uint256 nextRPS = prevRPS + ((amount * 1e18) / totalSupply());

        Snapshot memory newSnapshot = Snapshot({
            time: block.number,
            rewardReceived: amount,
            rewardPerShare: nextRPS
        });
        history.push(newSnapshot);

        emit RewardAdded(msg.sender, amount);
    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external onlyOwner {
        // do not allow to drain core tokens
        require(address(_token) != firmament, "firmament");
        require(address(_token) != arbitrum, "arbitrum");
        _token.safeTransfer(_to, _amount);
    }
}
