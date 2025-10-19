// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title TreasuryContract
 * @dev 金库合约，管理创作者项目收入和自动分红执行
 * 采用Pull模式进行分红，优化Gas消耗
 */
contract TreasuryContract is ReentrancyGuard, Ownable {

    // 分红配置
    struct DividendConfig {
        uint256 threshold;        // 分红阈值 (ETH)
        uint8 holderPercentage;   // 代币持有者分红比例 (百分比)
        uint8 creatorPercentage;  // 创作者分红比例 (百分比)
    }

    // 分红记录
    struct DividendRecord {
        uint256 totalAmount;      // 本次分红总额
        uint256 holderAmount;     // 代币持有者分红总额
        uint256 creatorAmount;    // 创作者分红总额
        uint256 timestamp;        // 分红时间
    }

    // 可领取分红记录
    struct ClaimableDividend {
        uint256 amount;           // 可领取金额
        uint256 dividendRound;    // 分红轮次
        bool claimed;             // 是否已领取
    }

    // 状态变量
    IERC20 public immutable creatorToken;
    address public immutable creatorAddress;
    DividendConfig public dividendConfig;

    uint256 public totalRevenue;        // 总收入
    uint256 public distributedRevenue;  // 已分配收入
    uint256 public currentDividendRound; // 当前分红轮次
    uint256 public lastDistributionAmount; // 上次分配金额

    bool public paused = false;         // 暂停状态

    // 映射
    mapping(address => ClaimableDividend) public claimableDividends;
    mapping(uint256 => DividendRecord) public dividendHistory;
    mapping(address => uint256) public lastClaimedRound;

    // 事件
    event RevenueReceived(uint256 amount, uint256 timestamp);
    event DividendDistributed(uint256 round, uint256 totalAmount, uint256 holderAmount, uint256 creatorAmount);
    event DividendClaimed(address indexed holder, uint256 amount, uint256 round);
    event CreatorPaid(uint256 amount, uint256 round);
    event DividendConfigUpdated(uint256 threshold, uint8 holderPercentage, uint8 creatorPercentage);
    event Paused(address account);
    event Unpaused(address account);

    // 修饰符
    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    modifier whenPaused() {
        require(paused, "Contract is not paused");
        _;
    }

    /**
     * @dev 构造函数
     * @param _creatorToken 创作者代币地址
     * @param _creatorAddress 创作者地址
     * @param _holderPercentage 代币持有者分红比例 (1-100)
     * @param _creatorPercentage 创作者分红比例 (1-100)
     */
    constructor(
        address _creatorToken,
        address _creatorAddress,
        uint8 _holderPercentage,
        uint8 _creatorPercentage
    ) Ownable(_creatorAddress) {
        require(_creatorToken != address(0), "Invalid token address");
        require(_creatorAddress != address(0), "Invalid creator address");
        require(_holderPercentage + _creatorPercentage == 100, "Percentages must sum to 100");
        require(_holderPercentage > 0 && _creatorPercentage > 0, "Percentages must be greater than 0");

        creatorToken = IERC20(_creatorToken);
        creatorAddress = _creatorAddress;
        dividendConfig.holderPercentage = _holderPercentage;
        dividendConfig.creatorPercentage = _creatorPercentage;
        dividendConfig.threshold = 2 ether; // 默认2 ETH

        currentDividendRound = 1;
    }

    /**
     * @dev 接收ETH收入
     */
    receive() external payable nonReentrant whenNotPaused {
        require(msg.value > 0, "Amount must be greater than 0");

        totalRevenue += msg.value;

        emit RevenueReceived(msg.value, block.timestamp);

        // 自动检查是否达到分红阈值
        _checkAndTriggerDividend();
    }

    /**
     * @dev 设置分红阈值
     * @param _threshold 新的分红阈值 (wei)
     */
    function setDividendThreshold(uint256 _threshold) external onlyOwner {
        require(_threshold > 0, "Threshold must be greater than 0");
        dividendConfig.threshold = _threshold;
    }

    /**
     * @dev 更新分红比例
     * @param _holderPercentage 代币持有者比例
     * @param _creatorPercentage 创作者比例
     */
    function updateDividendPercentages(uint8 _holderPercentage, uint8 _creatorPercentage) external onlyOwner {
        require(_holderPercentage + _creatorPercentage == 100, "Percentages must sum to 100");
        require(_holderPercentage > 0 && _creatorPercentage > 0, "Percentages must be greater than 0");

        dividendConfig.holderPercentage = _holderPercentage;
        dividendConfig.creatorPercentage = _creatorPercentage;

        emit DividendConfigUpdated(dividendConfig.threshold, _holderPercentage, _creatorPercentage);
    }

    /**
     * @dev 手动触发分红（任何人都可以调用）
     */
    function triggerDividendDistribution() external nonReentrant {
        require(_canTriggerDividend(), "Dividend threshold not reached");
        _distributeDividends();
    }

    /**
     * @dev 代币持有者领取分红
     */
    function claimDividend() external nonReentrant whenNotPaused {
        uint256 dividendRound = currentDividendRound - 1; // 最新已完成的分红轮次
        require(dividendRound > 0, "No dividend rounds available");
        require(lastClaimedRound[msg.sender] < dividendRound, "Already claimed latest dividend");

        // 获取分红记录
        DividendRecord memory record = dividendHistory[dividendRound];
        require(record.holderAmount > 0, "No holder dividend in this round");

        // 实时计算用户应得分红
        uint256 userBalance = creatorToken.balanceOf(msg.sender);
        require(userBalance > 0, "No tokens held");

        uint256 totalSupply = creatorToken.totalSupply();
        uint256 userDividend = (record.holderAmount * userBalance) / totalSupply;

        require(userDividend > 0, "Dividend amount too small");
        require(address(this).balance >= userDividend, "Insufficient contract balance");

        // 更新领取记录
        lastClaimedRound[msg.sender] = dividendRound;

        // 转账
        payable(msg.sender).transfer(userDividend);

        emit DividendClaimed(msg.sender, userDividend, dividendRound);
    }

    /**
     * @dev 获取用户可领取的分红
     */
    function getClaimableDividend(address holder) external view returns (uint256) {
        uint256 dividendRound = currentDividendRound - 1;
        if (dividendRound == 0 || lastClaimedRound[holder] >= dividendRound) {
            return 0;
        }

        // 获取分红记录
        DividendRecord memory record = dividendHistory[dividendRound];
        if (record.holderAmount == 0) {
            return 0;
        }

        // 计算用户应得分红
        uint256 userBalance = creatorToken.balanceOf(holder);
        if (userBalance == 0) {
            return 0;
        }

        uint256 totalSupply = creatorToken.totalSupply();
        return (record.holderAmount * userBalance) / totalSupply;
    }

    /**
     * @dev 计算用户在指定轮次的应得分红
     */
    function calculateDividendForHolder(address holder, uint256 _dividendRound) external view returns (uint256) {
        if (_dividendRound > currentDividendRound || _dividendRound == 0) {
            return 0;
        }

        DividendRecord memory record = dividendHistory[_dividendRound];
        if (record.holderAmount == 0) {
            return 0;
        }

        uint256 holderBalance = creatorToken.balanceOf(holder);
        uint256 totalSupply = creatorToken.totalSupply();

        if (totalSupply == 0) {
            return 0;
        }

        return (record.holderAmount * holderBalance) / totalSupply;
    }

    /**
     * @dev 获取下一轮分红所需金额
     */
    function getAmountNeededForNextDividend() external view returns (uint256) {
        uint256 nextThreshold = lastDistributionAmount + dividendConfig.threshold;
        if (totalRevenue >= nextThreshold) {
            return 0;
        }
        return nextThreshold - totalRevenue;
    }

    /**
     * @dev 获取分红历史记录
     */
    function getDividendRecord(uint256 _round) external view returns (DividendRecord memory) {
        return dividendHistory[_round];
    }

    /**
     * @dev 检查是否可以触发分红
     */
    function _canTriggerDividend() internal view returns (bool) {
        uint256 nextThreshold = lastDistributionAmount + dividendConfig.threshold;
        return totalRevenue >= nextThreshold;
    }

    /**
     * @dev 检查并自动触发分红
     */
    function _checkAndTriggerDividend() internal {
        if (_canTriggerDividend()) {
            _distributeDividends();
        }
    }

    /**
     * @dev 执行分红分配
     */
    function _distributeDividends() internal {
        uint256 nextThreshold = lastDistributionAmount + dividendConfig.threshold;
        require(totalRevenue >= nextThreshold, "Insufficient revenue for dividend");

        uint256 distributionAmount = dividendConfig.threshold;
        uint256 holderAmount = (distributionAmount * dividendConfig.holderPercentage) / 100;
        uint256 creatorAmount = (distributionAmount * dividendConfig.creatorPercentage) / 100;

        // 更新状态
        distributedRevenue += distributionAmount;
        lastDistributionAmount = nextThreshold;

        // 创建分红记录
        DividendRecord memory record = DividendRecord({
            totalAmount: distributionAmount,
            holderAmount: holderAmount,
            creatorAmount: creatorAmount,
            timestamp: block.timestamp
        });

        dividendHistory[currentDividendRound] = record;

        // 预计算所有代币持有者的可领取分红
        // 注意：由于gas限制，我们采用Pull模式，持有人主动领取时计算
        // 这里不做预计算，在claimDividend时实时计算
        uint256 totalSupply = creatorToken.totalSupply();
        if (totalSupply > 0 && holderAmount > 0) {
            // 记录本轮次的分红池金额，供后续领取使用
            // 实际分红金额将在用户领取时根据其代币持有比例计算
        }

        // 支付给创作者
        if (creatorAmount > 0) {
            payable(creatorAddress).transfer(creatorAmount);
            emit CreatorPaid(creatorAmount, currentDividendRound);
        }

        emit DividendDistributed(currentDividendRound, distributionAmount, holderAmount, creatorAmount);

        currentDividendRound++;
    }

    /**
     * @dev 为代币持有者设置可领取分红
     * @param holder 持有者地址
     * @param amount 分红金额
     */
    function _setClaimableDividend(address holder, uint256 amount) internal {
        if (amount > 0) {
            claimableDividends[holder] = ClaimableDividend({
                amount: amount,
                dividendRound: currentDividendRound,
                claimed: false
            });
        }
    }

    /**
     * @dev 紧急提取函数（仅在特殊情况下使用）
     */
    function emergencyWithdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    /**
     * @dev 获取合约余额
     */
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @dev 获取金库统计信息
     */
    function getTreasuryStats() external view returns (
        uint256,
        uint256,
        uint256,
        uint256
    ) {
        return (
            totalRevenue,
            distributedRevenue,
            totalRevenue - distributedRevenue,
            address(this).balance
        );
    }

    /**
     * @dev 暂停合约（仅所有者）
     */
    function pause() external onlyOwner {
        require(!paused, "Contract is already paused");
        paused = true;
        emit Paused(msg.sender);
    }

    /**
     * @dev 恢复合约（仅所有者）
     */
    function unpause() external onlyOwner {
        require(paused, "Contract is not paused");
        paused = false;
        emit Unpaused(msg.sender);
    }
}