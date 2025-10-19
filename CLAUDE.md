# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目架构

PromptDAO 是一个基于 Next.js 和区块链的 AI NFT 创作平台，包含两个主要子项目：

### 1. 前端项目 (promptdao/)
- **框架**: Next.js 15.5.6 with TypeScript
- **样式**: Tailwind CSS
- **区块链交互**: Wagmi + ethers
- **主要功能**:
  - AI 艺术 NFT 生成和铸造
  - 创作 DAO 治理系统
  - 创作者代币经济
  - Launchpad 众筹平台

### 2. 智能合约项目 (contracts/)
- **框架**: Hardhat
- **Solidity版本**: 0.8.20
- **主要合约**:
  - `CreatorToken.sol`: ERC20创作者代币，用于分红
  - `CreatorNFT.sol`: ERC721 NFT，代表AI生成的艺术品
  - `Treasury.sol`: 财库合约，管理收益分配

## 常用开发命令

### 前端开发 (promptdao/ 目录)
```bash
# 启动开发服务器
npm run dev

# 构建项目
npm run build

# 启动生产服务器
npm start

# 代码检查
npm run lint
```

### 智能合约开发 (contracts/ 目录)
```bash
# 编译合约
npm run compile

# 运行测试
npm run test

# 启动本地Hardhat节点
npm run node

# 部署到本地网络
npm run deploy

# 部署到Hardhat网络
npm run deploy:hardhat
```

## 核心架构概念

### 代币经济模型
- **创作者收益**: 50%直接分配给创作者
- **代币持有者分红**: 50%用于CreatorToken持有者分红
- **CreatorToken**: ERC20代币，仅用于分红，不具备治理功能

### 技术栈集成
- **IPFS存储**: 使用Pinata服务存储NFT元数据和图片
- **AI图片生成**: 当前使用SVG占位符，可扩展为真实AI服务
- **Web3集成**: 通过Wagmi处理钱包连接和合约交互

### 关键配置文件
- `promptdao/hardhat.config.js`: Hardhat配置
- `promptdao/src/lib/contracts.ts`: 合约ABI和地址配置
- `promptdao/.env.local`: 环境变量配置

### 部署流程
1. 启动本地Hardhat节点: `npm run node` (contracts/)
2. 部署合约: `npm run deploy` (contracts/)
3. 更新前端合约地址配置
4. 启动前端开发服务器: `npm run dev` (promptdao/)

## 测试策略
- **单元测试**: 使用Hardhat + Chai测试智能合约
- **前端测试**: Next.js默认测试框架
- **集成测试**: 通过本地Hardhat网络进行端到端测试

## 重要提示
- 合约地址配置在 `src/lib/contracts.ts` 中，部署后需要更新
- 环境变量需要配置Pinata API密钥
- 本地开发需要同时运行合约节点和前端服务器