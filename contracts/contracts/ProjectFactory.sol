// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./CrowdsaleContract.sol";

/**
 * @title ProjectFactory
 * @dev 工厂合约，用于创建和管理创作者项目
 * 为每个项目部署独立的众筹合约
 */
contract ProjectFactory is Ownable, ReentrancyGuard {
    // 项目信息结构
    struct ProjectInfo {
        uint256 projectId;
        address creator;
        string projectName;
        string description;
        string imageUrl;
        uint256 createdAt;
        address crowdsaleContract;
        bool active;
    }

    // 创建项目参数结构
    struct CreateProjectParams {
        string projectName;        // 项目名称
        string description;       // 项目描述
        string imageUrl;          // 项目图片URL
        uint256 fundingGoal;      // 众筹目标 (ETH)
        uint256 fundingPeriod;    // 众筹时长 (秒)
        uint256 totalSupply;      // 代币总供应量
        uint8 crowdsaleAllocation; // 众筹分配比例 (1-100)
        string tokenName;         // 代币名称
        string tokenSymbol;       // 代币符号
        uint8 holderPercentage;   // 代币持有者分红比例 (1-100)
        uint8 creatorPercentage;  // 创作者分红比例 (1-100)
        uint256 dividendThreshold; // 分红阈值 (ETH)
    }

    // 状态变量
    uint256 public nextProjectId;
    mapping(uint256 => ProjectInfo) public projects;
    mapping(address => uint256[]) public creatorProjects;
    mapping(uint256 => bool) public projectExists;

    // 数组存储所有项目ID
    uint256[] public allProjects;

    // 事件
    event ProjectCreated(
        uint256 indexed projectId,
        address indexed creator,
        string projectName,
        address crowdsaleContract
    );
    event ProjectUpdated(
        uint256 indexed projectId,
        string projectName,
        string description
    );
    event ProjectDeactivated(uint256 indexed projectId);

    /**
     * @dev 构造函数
     */
    constructor() Ownable(msg.sender) {
        nextProjectId = 1;
    }

    /**
     * @dev 创建新项目
     * @param params 项目创建参数
     */
    function createProject(CreateProjectParams memory params) external nonReentrant {
        require(bytes(params.projectName).length > 0, "Project name is required");
        require(bytes(params.description).length > 0, "Description is required");
        require(params.fundingGoal > 0, "Funding goal must be greater than 0");
        require(params.fundingPeriod > 0, "Funding period must be greater than 0");
        require(params.totalSupply > 0, "Total supply must be greater than 0");
        require(params.crowdsaleAllocation > 0 && params.crowdsaleAllocation <= 100, "Invalid crowdsale allocation");
        require(bytes(params.tokenName).length > 0, "Token name is required");
        require(bytes(params.tokenSymbol).length > 0, "Token symbol is required");
        require(params.holderPercentage + params.creatorPercentage == 100, "Dividend percentages must sum to 100");
        require(params.holderPercentage > 0 && params.creatorPercentage > 0, "Dividend percentages must be greater than 0");
        require(params.dividendThreshold > 0, "Dividend threshold must be greater than 0");

        // 创建众筹合约配置
        CrowdsaleContract.ProjectConfig memory config = CrowdsaleContract.ProjectConfig({
            fundingGoal: params.fundingGoal,
            fundingPeriod: params.fundingPeriod,
            totalSupply: params.totalSupply,
            crowdsaleAllocation: params.crowdsaleAllocation,
            creator: msg.sender,
            tokenName: params.tokenName,
            tokenSymbol: params.tokenSymbol,
            holderPercentage: params.holderPercentage,
            creatorPercentage: params.creatorPercentage
        });

        // 部署众筹合约
        CrowdsaleContract crowdsale = new CrowdsaleContract(config);

        // 创建项目信息
        ProjectInfo storage project = projects[nextProjectId];
        project.projectId = nextProjectId;
        project.creator = msg.sender;
        project.projectName = params.projectName;
        project.description = params.description;
        project.imageUrl = params.imageUrl;
        project.createdAt = block.timestamp;
        project.crowdsaleContract = address(crowdsale);
        project.active = true;

        // 记录项目存在
        projectExists[nextProjectId] = true;

        // 添加到创作者项目列表
        creatorProjects[msg.sender].push(nextProjectId);

        // 添加到所有项目列表
        allProjects.push(nextProjectId);

        emit ProjectCreated(nextProjectId, msg.sender, params.projectName, address(crowdsale));

        nextProjectId++;
    }

    /**
     * @dev 更新项目信息
     * @param projectId 项目ID
     * @param projectName 新项目名称
     * @param description 新项目描述
     */
    function updateProject(
        uint256 projectId,
        string memory projectName,
        string memory description
    ) external {
        require(projectExists[projectId], "Project does not exist");
        require(projects[projectId].creator == msg.sender, "Only creator can update project");

        projects[projectId].projectName = projectName;
        projects[projectId].description = description;

        emit ProjectUpdated(projectId, projectName, description);
    }

    /**
     * @dev 停用项目
     * @param projectId 项目ID
     */
    function deactivateProject(uint256 projectId) external {
        require(projectExists[projectId], "Project does not exist");
        require(projects[projectId].creator == msg.sender, "Only creator can deactivate project");

        projects[projectId].active = false;
        emit ProjectDeactivated(projectId);
    }

    /**
     * @dev 获取项目信息
     * @param projectId 项目ID
     */
    function getProject(uint256 projectId) external view returns (ProjectInfo memory) {
        require(projectExists[projectId], "Project does not exist");
        return projects[projectId];
    }

    /**
     * @dev 获取创作者的所有项目
     * @param creator 创作者地址
     */
    function getCreatorProjects(address creator) external view returns (uint256[] memory) {
        return creatorProjects[creator];
    }

    /**
     * @dev 获取所有项目ID
     */
    function getAllProjects() external view returns (uint256[] memory) {
        return allProjects;
    }

    /**
     * @dev 获取活跃项目数量
     */
    function getActiveProjectsCount() external view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < allProjects.length; i++) {
            if (projects[allProjects[i]].active) {
                count++;
            }
        }
        return count;
    }

    /**
     * @dev 获取分页的项目列表
     * @param offset 偏移量
     * @param limit 限制数量
     */
    function getProjectsPaginated(uint256 offset, uint256 limit) external view returns (ProjectInfo[] memory) {
        uint256 end = offset + limit;
        if (end > allProjects.length) {
            end = allProjects.length;
        }

        ProjectInfo[] memory result = new ProjectInfo[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            result[i - offset] = projects[allProjects[i]];
        }

        return result;
    }

    /**
     * @dev 搜索项目（按名称）
     * @param searchTerm 搜索词
     */
    function searchProjects(string memory searchTerm) external view returns (uint256[] memory) {
        uint256[] memory tempResults = new uint256[](allProjects.length);
        uint256 count = 0;

        for (uint256 i = 0; i < allProjects.length; i++) {
            if (_contains(projects[allProjects[i]].projectName, searchTerm)) {
                tempResults[count] = allProjects[i];
                count++;
            }
        }

        uint256[] memory results = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            results[i] = tempResults[i];
        }

        return results;
    }

    /**
     * @dev 检查字符串是否包含子字符串（简单实现）
     * @param str 主字符串
     * @param substr 子字符串
     */
    function _contains(string memory str, string memory substr) internal pure returns (bool) {
        bytes memory strBytes = bytes(str);
        bytes memory substrBytes = bytes(substr);

        if (substrBytes.length > strBytes.length) {
            return false;
        }

        for (uint256 i = 0; i <= strBytes.length - substrBytes.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < substrBytes.length; j++) {
                if (strBytes[i + j] != substrBytes[j]) {
                    found = false;
                    break;
                }
            }
            if (found) {
                return true;
            }
        }

        return false;
    }

    /**
     * @dev 获取项目统计信息
     */
    function getFactoryStats() external view returns (
        uint256 totalProjects,
        uint256 activeProjects,
        uint256 totalCreators
    ) {
        uint256 active = 0;
        for (uint256 i = 0; i < allProjects.length; i++) {
            if (projects[allProjects[i]].active) {
                active++;
            }
        }

        return (allProjects.length, active, _getUniqueCreatorCount());
    }

    /**
     * @dev 获取唯一创作者数量
     */
    function _getUniqueCreatorCount() internal view returns (uint256) {
        // 简化实现，实际应用中可能需要更复杂的逻辑
        address[] memory creators = new address[](allProjects.length);
        uint256 count = 0;

        for (uint256 i = 0; i < allProjects.length; i++) {
            address creator = projects[allProjects[i]].creator;
            bool isUnique = true;

            for (uint256 j = 0; j < count; j++) {
                if (creators[j] == creator) {
                    isUnique = false;
                    break;
                }
            }

            if (isUnique) {
                creators[count] = creator;
                count++;
            }
        }

        return count;
    }

    /**
     * @dev 紧急暂停功能（仅在特殊情况下使用）
     */
    function emergencyPause() external onlyOwner {
        // 实现紧急暂停逻辑
        // 例如：阻止新项目创建等
    }

    /**
     * @dev 检查地址是否为合约
     */
    function isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    /**
     * @dev 获取下一个项目ID
     */
    function getNextProjectId() external view returns (uint256) {
        return nextProjectId;
    }
}