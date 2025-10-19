// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./CreatorToken.sol";
import "./TreasuryContract.sol";

/**
 * @title CrowdsaleContract
 * @dev 众筹合约，处理项目资金募集和代币分发
 * 采用拉取模式，投资者主动领取代币或退款
 */
contract CrowdsaleContract is ReentrancyGuard, Ownable {

    // 项目状态枚举
    enum ProjectState { PENDING, ACTIVE, SUCCESS, FAILED, COMPLETED }

    // 项目配置
    struct ProjectConfig {
        uint256 fundingGoal;          // 众筹目标 (ETH)
        uint256 fundingPeriod;        // 众筹时长 (秒)
        uint256 totalSupply;          // 代币总供应量
        uint8 crowdsaleAllocation;   // 众筹分配比例 (总供应量的百分比)
        address creator;              // 创作者地址
        string tokenName;             // 代币名称
        string tokenSymbol;           // 代币符号
    }

    // 投资记录
    struct Investment {
        uint256 amount;       // 投资金额 (wei)
        bool tokensClaimed;   // 是否已领取代币
        bool refunded;        // 是否已退款
    }

    // 状态变量
    ProjectConfig public config;
    ProjectState public state;
    uint256 public startTime;
    uint256 public endTime;
    uint256 public totalRaised;
    uint256 public totalInvestors;

    // 合约实例
    CreatorToken public creatorToken;
    TreasuryContract public treasuryContract;

    // 映射
    mapping(address => Investment) public investments;
    mapping(address => bool) public hasInvested;

    // 事件
    event CrowdsaleStarted(uint256 startTime, uint256 endTime);
    event InvestmentMade(address indexed investor, uint256 amount);
    event CrowdsaleSuccess(uint256 totalRaised);
    event CrowdsaleFailed(uint256 totalRaised);
    event TokensClaimed(address indexed investor, uint256 amount);
    event RefundClaimed(address indexed investor, uint256 amount);
    event TreasuryDeployed(address indexed treasury);

    /**
     * @dev 构造函数
     * @param _config 项目配置
     */
    constructor(ProjectConfig memory _config) Ownable(_config.creator) {
        require(_config.fundingGoal > 0, "Funding goal must be greater than 0");
        require(_config.fundingPeriod > 0, "Funding period must be greater than 0");
        require(_config.totalSupply > 0, "Total supply must be greater than 0");
        require(_config.crowdsaleAllocation > 0 && _config.crowdsaleAllocation <= 100, "Invalid allocation percentage");
        require(_config.creator != address(0), "Invalid creator address");

        config = _config;
        state = ProjectState.PENDING;
    }

    /**
     * @dev 启动众筹
     */
    function startCrowdsale() external onlyOwner {
        require(state == ProjectState.PENDING, "Crowdsale already started or completed");

        state = ProjectState.ACTIVE;
        startTime = block.timestamp;
        endTime = startTime + config.fundingPeriod;

        // 部署CreatorToken合约
        creatorToken = new CreatorToken(
            config.tokenName,
            config.tokenSymbol,
            config.totalSupply,
            address(this)
        );

        emit CrowdsaleStarted(startTime, endTime);
    }

    /**
     * @dev 投资函数
     */
    function invest() external payable nonReentrant {
        require(state == ProjectState.ACTIVE, "Crowdsale is not active");
        require(block.timestamp < endTime, "Crowdsale has ended");
        require(msg.value > 0, "Investment must be greater than 0");

        // 记录投资
        if (!hasInvested[msg.sender]) {
            hasInvested[msg.sender] = true;
            totalInvestors++;
        }

        investments[msg.sender].amount += msg.value;
        totalRaised += msg.value;

        emit InvestmentMade(msg.sender, msg.value);

        // 检查是否达到众筹目标
        if (totalRaised >= config.fundingGoal) {
            _handleCrowdsaleSuccess();
        }
    }

    /**
     * @dev 结束众筹（时间到期后调用）
     */
    function endCrowdsale() external {
        require(state == ProjectState.ACTIVE, "Crowdsale is not active");
        require(block.timestamp >= endTime, "Crowdsale has not ended yet");

        if (totalRaised >= config.fundingGoal) {
            _handleCrowdsaleSuccess();
        } else {
            _handleCrowdsaleFailure();
        }
    }

    /**
     * @dev 投资者领取代币
     */
    function claimTokens() external nonReentrant {
        require(state == ProjectState.SUCCESS, "Crowdsale was not successful");
        require(hasInvested[msg.sender], "No investment found");
        require(!investments[msg.sender].tokensClaimed, "Tokens already claimed");

        uint256 investmentAmount = investments[msg.sender].amount;
        uint256 tokensToClaim = _calculateTokens(investmentAmount);

        investments[msg.sender].tokensClaimed = true;

        // 转移代币
        creatorToken.transfer(msg.sender, tokensToClaim);

        emit TokensClaimed(msg.sender, tokensToClaim);
    }

    /**
     * @dev 投资者退款
     */
    function claimRefund() external nonReentrant {
        require(state == ProjectState.FAILED, "Crowdsale was not failed");
        require(hasInvested[msg.sender], "No investment found");
        require(!investments[msg.sender].refunded, "Refund already claimed");

        uint256 refundAmount = investments[msg.sender].amount;
        investments[msg.sender].refunded = true;

        payable(msg.sender).transfer(refundAmount);

        emit RefundClaimed(msg.sender, refundAmount);
    }

    /**
     * @dev 创作者提取资金（众筹成功后）
     */
    function withdrawFunds() external onlyOwner nonReentrant {
        require(state == ProjectState.SUCCESS, "Crowdsale was not successful");
        require(address(this).balance > 0, "No funds to withdraw");

        uint256 amount = address(this).balance;
        payable(config.creator).transfer(amount);
    }

    /**
     * @dev 部署金库合约
     */
    function deployTreasury() external onlyOwner {
        require(state == ProjectState.SUCCESS, "Crowdsale was not successful");
        require(address(treasuryContract) == address(0), "Treasury already deployed");

        // 部署TreasuryContract
        treasuryContract = new TreasuryContract(
            address(creatorToken),
            config.creator,
            40, // 40% 给代币持有者 (可根据需求调整)
            60  // 60% 给创作者
        );

        // 启用代币分红功能
        creatorToken.enableDividend();

        // 将剩余代币转移给创作者
        uint256 remainingTokens = config.totalSupply -
            (config.totalSupply * config.crowdsaleAllocation) / 100;
        creatorToken.transfer(config.creator, remainingTokens);

        // 转移所有权给创作者
        creatorToken.transferOwnership(config.creator);
        treasuryContract.transferOwnership(config.creator);

        state = ProjectState.COMPLETED;

        emit TreasuryDeployed(address(treasuryContract));
    }

    /**
     * @dev 计算应得代币数量
     */
    function _calculateTokens(uint256 investmentAmount) internal view returns (uint256) {
        uint256 tokensForCrowdsale = (config.totalSupply * config.crowdsaleAllocation) / 100;
        return tokensForCrowdsale * investmentAmount / config.fundingGoal;
    }

    /**
     * @dev 处理众筹成功
     */
    function _handleCrowdsaleSuccess() internal {
        state = ProjectState.SUCCESS;
        emit CrowdsaleSuccess(totalRaised);
    }

    /**
     * @dev 处理众筹失败
     */
    function _handleCrowdsaleFailure() internal {
        state = ProjectState.FAILED;
        emit CrowdsaleFailed(totalRaised);
    }

    /**
     * @dev 获取投资者可领取的代币数量
     */
    function getClaimableTokens(address investor) external view returns (uint256) {
        if (state != ProjectState.SUCCESS || !hasInvested[investor] || investments[investor].tokensClaimed) {
            return 0;
        }
        return _calculateTokens(investments[investor].amount);
    }

    /**
     * @dev 获取投资者可退款的金额
     */
    function getRefundableAmount(address investor) external view returns (uint256) {
        if (state != ProjectState.FAILED || !hasInvested[investor] || investments[investor].refunded) {
            return 0;
        }
        return investments[investor].amount;
    }

    /**
     * @dev 获取剩余时间
     */
    function getTimeRemaining() external view returns (uint256) {
        if (state != ProjectState.ACTIVE) {
            return 0;
        }
        uint256 remaining = endTime > block.timestamp ? endTime - block.timestamp : 0;
        return remaining;
    }

    /**
     * @dev 检查众筹是否成功
     */
    function isSuccessful() external view returns (bool) {
        return state == ProjectState.SUCCESS;
    }

    /**
     * @dev 检查众筹是否失败
     */
    function isFailed() external view returns (bool) {
        return state == ProjectState.FAILED;
    }
}