// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title CreatorToken
 * @dev ERC20代币，代表对特定创作者项目的收益分享权
 * 仅用于分红凭证，不具备治理功能
 */
contract CreatorToken is ERC20, Ownable {
    // 记录总供应量
    uint256 public immutable TOTAL_SUPPLY;

    // 记录代币是否可用于分红（防止在众筹期间分红）
    bool public dividendEnabled = false;

    // 事件
    event DividendStatusChanged(bool enabled);

    /**
     * @dev 构造函数
     * @param name_ 代币名称
     * @param symbol_ 代币符号
     * @param totalSupply_ 总供应量
     * @param initialOwner 初始所有者（众筹合约）
     */
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 totalSupply_,
        address initialOwner
    ) ERC20(name_, symbol_) Ownable(initialOwner) {
        require(totalSupply_ > 0, "Total supply must be greater than 0");
        TOTAL_SUPPLY = totalSupply_;
    }

    /**
     * @dev 启用分红功能
     * 只有众筹成功后才能调用
     */
    function enableDividend() external onlyOwner {
        require(!dividendEnabled, "Dividend already enabled");
        dividendEnabled = true;
        emit DividendStatusChanged(true);
    }

    /**
     * @dev 禁用分红功能
     * 紧急情况下使用
     */
    function disableDividend() external onlyOwner {
        require(dividendEnabled, "Dividend already disabled");
        dividendEnabled = false;
        emit DividendStatusChanged(false);
    }

    /**
     * @dev 铸造代币（仅限众筹合约调用）
     * @param to 接收地址
     * @param amount 铸造数量
     */
    function mint(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "Cannot mint to zero address");
        require(amount > 0, "Amount must be greater than 0");
        require(totalSupply() + amount <= TOTAL_SUPPLY, "Exceeds total supply");

        _mint(to, amount);
    }

    /**
     * @dev 销毁代币
     * @param amount 销毁数量
     */
    function burn(uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");

        _burn(msg.sender, amount);
    }

    /**
     * @dev 获取总供应量
     */
    function getMaxSupply() external view returns (uint256) {
        return TOTAL_SUPPLY;
    }

    /**
     * @dev 检查分红是否启用
     */
    function isDividendEnabled() external view returns (bool) {
        return dividendEnabled;
    }
}