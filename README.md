# TournamentDistributor 合约使用指南

## 📋 合约简介

`TournamentDistributor` 是一个基于以太坊的**去中心化比赛奖金分发合约**，支持：

* ✅ **ERC20 代币奖金**（如 USDT、自定义代币）
* ✅ **报名费自动并入奖池**
* ✅ **Merkle 证明验证获奖者身份**
* ✅ **链上按比例自动计算奖金**
* ✅ **防止重复领取和作弊**

### 核心特性

1. **灵活的奖金分配**：支持任意比例分配（如 60%-40%、50%-30%-20% 等）
2. **透明可验证**：所有操作链上记录，完全透明
3. **安全可靠**：使用 OpenZeppelin 安全库，防止重入攻击
4. **赞助支持**：支持赛事方额外注资
5. **余额管理**：管理员可提取剩余资金和尾差

***

## 🏗️ 合约架构

### 关键合约信息

* **合约名称**：`TournamentDistributor`
* **Solidity 版本**：^0.8.20
* **依赖库**：OpenZeppelin Contracts (Ownable, IERC20, SafeERC20)
* **许可证**：MIT

### 测试合约地址（Remix 示例）

```
MTTToken 地址:           0xd9145CCE52D386f254917e481eB44e9943F39138
TournamentDistributor:    (部署后填写)

测试地址 1:               0x5B38Da6a701c568545dCfcB03FcB875f56beddC4
测试地址 2:               0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2
```

***

## 🚀 完整使用流程

### 阶段 1: 部署合约

#### 1.1 部署 TestToken（可选，如已有 ERC20 代币可跳过）

```solidity
// 在 Remix 中编译 testToken.sol
// 部署参数：无
// 结果：获得 MTTToken 合约地址
```

#### 1.2 部署 TournamentDistributor

```solidity
// 编译 match.sol
// 部署参数：
constructor(address initialOwner)

// 示例：
initialOwner: 0x5B38Da6a701c568545dCfcB03FcB875f56beddC4  // 管理员地址
```

***

### 阶段 2: 创建比赛

#### 2.1 Mint 测试代币（测试环境）

在 MTTToken 合约中调用 `mint`：

```javascript
// 为管理员和玩家 mint 代币
mint(0x5B38Da6a701c568545dCfcB03FcB875f56beddC4, 10000000000000000000)  // 10 个代币
mint(0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2, 10000000000000000000)  // 10 个代币
```

#### 2.2 创建比赛

在 TournamentDistributor 合约中调用 `createMatch`（需 Owner 权限）：

```javascript
matchId:           11
token:             0xd9145CCE52D386f254917e481eB44e9943F39138  // MTTToken 地址
entryFee:          1000000000000000000                        // 1 个代币（18 decimals）
registerDeadline:  1762892500                                 // Unix 时间戳（0 表示不限时）
```

**说明**：

* `matchId`：比赛唯一标识，建议递增（11, 12, 13...）
* `entryFee`：报名费，注意代币精度（18 位小数 = 10^18）
* `registerDeadline`：报名截止时间，0 表示永久开放

#### 2.3 赞助奖池（可选）

管理员可以注资增加奖池：

**步骤 1：授权**

```javascript
// 在 MTTToken 合约调用 approve
spender: <TournamentDistributor 合约地址>
value:   2000000000000000000  // 2 个代币
```

**步骤 2：赞助**

```javascript
// 在 TournamentDistributor 合约调用 sponsor
matchId: 11
amount:  2000000000000000000  // 2 个代币
```

***

### 阶段 3: 玩家报名

每个玩家需要完成以下步骤：

#### 3.1 授权代币

切换到玩家地址，在 MTTToken 合约调用 `approve`：

```javascript
spender: <TournamentDistributor 合约地址>
value:   1000000000000000000  // 报名费金额
```

#### 3.2 报名

在 TournamentDistributor 合约调用 `register`：

```javascript
matchId: 11
```

**示例：两个玩家报名**

```
地址 1 (0x5B38...eddC4) → approve → register(11)
地址 2 (0xAb84...5cb2) → approve → register(11)
```

***

### 阶段 4: 比赛结算

#### 4.1 计算 Merkle Root

使用提供的脚本计算 Merkle Root：

```bash
# 编辑 scripts/calculate_merkle.js 中的获奖者信息
const winners = [
    { address: "0x5B38Da6a701c568545dCfcB03FcB875f56beddC4", rank: 1 },  // 第1名
    { address: "0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2", rank: 2 }   // 第2名
];

const shares = [600, 400];  // 第1名60%，第2名40%
const sharesSum = 1000;

# 运行脚本
node scripts/calculate_merkle.js
```

**输出示例**：

```
Merkle Root: 0x1fa758f5992c5cf63c09d743248835b4cf5b5bb0166ec866ec9fcf803b1ed781

地址 1 Proof: ["0x2429fa02b09522ed5374253a2e923f40ac1b0d1c0eb15a2cac394950d4791641"]
地址 2 Proof: ["0x887610ccbf6ff730a639c5ec66d671b53ea0e4b57e1d0365ac1312d4da91ee70"]
```

#### 4.2 最终确定比赛

在 TournamentDistributor 合约调用 `finalize`（需 Owner 权限）：

```javascript
matchId:         11
shares:          [600,400]
sharesSum:       1000
merkleRoot:      0x1fa758f5992c5cf63c09d743248835b4cf5b5bb0166ec866ec9fcf803b1ed781
fixedPoolInput:  0  // 0 表示使用当前全部 poolBalance
```

**注意**：

* `shares` 数组长度 = 获奖名次数
* `sharesSum` 通常是 shares 的总和（如 600+400=1000）
* `fixedPoolInput` 为 0 时自动使用当前奖池余额

***

### 阶段 5: 领取奖金

#### 5.1 第一名领取

切换到第一名地址，调用 `claim`：

```javascript
matchId: 11
rank:    1
proof:   ["0x2429fa02b09522ed5374253a2e923f40ac1b0d1c0eb15a2cac394950d4791641"]
```

#### 5.2 第二名领取

切换到第二名地址，调用 `claim`：

```javascript
matchId: 11
rank:    2
proof:   ["0x887610ccbf6ff730a639c5ec66d671b53ea0e4b57e1d0365ac1312d4da91ee70"]
```

**奖金计算示例**：

```
假设奖池总额 = 2 个代币

第1名（60%）= 2 × 600 / 1000 = 1.2 个代币
第2名（40%）= 2 × 400 / 1000 = 0.8 个代币
```

***

## 🔍 查询函数

### getMatchInfo - 查询比赛信息

```javascript
matchId: 11

// 返回：
// token: 代币地址
// entryFee: 报名费
// registerDeadline: 报名截止时间
// fixedPool: 锁定的奖池总额
// currentPool: 当前剩余奖池
// merkleRoot: Merkle 根
// sharesSum: 份额总和
// finalized: 是否已确定
```

### quotePayoutByRank - 查询名次奖金

```javascript
matchId: 11
rank:    1

// 返回：
// share: 该名次的份额
// amount: 应得金额
```

### status - 查询玩家状态

```javascript
matchId: 11
player:  0x5B38Da6a701c568545dCfcB03FcB875f56beddC4

// 返回：
// isRegistered: 是否已报名
// isClaimed: 是否已领取
```

***

## 🛠️ 管理员功能

### skim - 提取剩余资金

提取奖池中的剩余资金（如尾差、未领取余额）：

```javascript
matchId: 11
to:      0x5B38Da6a701c568545dCfcB03FcB875f56beddC4  // 收款地址
amount:  1000000000000000  // 提取金额
```

**使用场景**：

* 所有获奖者已领取，提取整数除法产生的尾差
* 部分玩家长期未领取，管理员归集资金
* 比赛取消，退还奖池

***

## 📊 事件日志

合约会发出以下事件，可通过日志追踪操作：

```solidity
event MatchCreated(uint256 indexed matchId, address token, uint96 entryFee, uint64 registerDeadline);
event Sponsored(uint256 indexed matchId, address indexed from, uint256 amount);
event Registered(uint256 indexed matchId, address indexed player, uint256 fee);
event Finalized(uint256 indexed matchId, uint256 fixedPool, bytes32 merkleRoot);
event Claimed(uint256 indexed matchId, address indexed player, uint256 rank, uint256 amount);
event Skimmed(uint256 indexed matchId, address indexed to, uint256 amount);
```

***

## ⚠️ 常见问题

### 1. "Insufficient allowance" 错误

**原因**：未授权合约转移代币

**解决**：在 ERC20 代币合约调用 `approve`，授权 TournamentDistributor 合约地址

### 2. "not registered" 错误

**原因**：该地址未报名或报名失败

**解决**：检查是否成功调用 `register` 函数并支付报名费

### 3. "bad proof" 错误

**原因**：Merkle proof 不正确

**解决**：

* 确保使用脚本正确计算的 proof
* 确认地址和 rank 与计算时一致
* 检查 merkleRoot 是否正确

### 4. "already finalized" 错误

**原因**：比赛已经 finalize，不能再报名

**解决**：在比赛 finalize 之前完成报名

### 5. 如何计算代币金额？

不同代币的 decimals 不同：

```javascript
// 18 decimals (如 TEST, DAI, WETH)
1 代币 = 1000000000000000000 (1e18)

// 6 decimals (如 USDT, USDC)
1 代币 = 1000000 (1e6)

// 计算公式
金额 = 数量 × 10^decimals
```

***

## 📁 项目文件结构

```
sol/
├── contracts/
│   ├── match.sol                # TournamentDistributor 主合约
│   ├── testToken.sol            # 测试用 ERC20 代币
│   └── ...                      # 其他合约
├── scripts/
│   ├── calculate_merkle.js      # Merkle Root 计算脚本
│   ├── calculate_merkle.ts      # TypeScript 版本
│   └── ...                      # 其他脚本
├── artifacts/                   # 编译产物
├── package.json                 # 依赖配置
└── README.md                    # 本文档
```

***

## 🧪 完整测试示例

### 测试场景：2 个玩家，60%-40% 分配

```javascript
// ========== 1. 部署合约 ==========
// MTTToken: 0xd9145CCE52D386f254917e481eB44e9943F39138
// TournamentDistributor: <部署后地址>

// ========== 2. 准备代币 ==========
// MTTToken.mint(address1, 10e18)
// MTTToken.mint(address2, 10e18)

// ========== 3. 创建比赛 ==========
createMatch(
    11,                                    // matchId
    0xd9145CCE52D386f254917e481eB44e9943F39138,  // token
    1000000000000000000,                   // 1 TEST
    1762892500                             // deadline
)

// ========== 4. 玩家报名 ==========
// 地址 1:
//   MTTToken.approve(TournamentDistributor, 1e18)
//   TournamentDistributor.register(11)
// 地址 2:
//   MTTToken.approve(TournamentDistributor, 1e18)
//   TournamentDistributor.register(11)

// ========== 5. 计算 Merkle Root ==========
// node scripts/calculate_merkle.js
// Root: 0x1fa758f5992c5cf63c09d743248835b4cf5b5bb0166ec866ec9fcf803b1ed781

// ========== 6. 结算比赛 ==========
finalize(
    11,                    // matchId
    [600, 400],            // shares
    1000,                  // sharesSum
    0x1fa758f5992c5cf63c09d743248835b4cf5b5bb0166ec866ec9fcf803b1ed781,  // root
    0                      // fixedPoolInput
)

// ========== 7. 领取奖金 ==========
// 地址 1 (第1名):
claim(11, 1, ["0x2429fa02b09522ed5374253a2e923f40ac1b0d1c0eb15a2cac394950d4791641"])
// 获得: 1.2 TEST (60%)

// 地址 2 (第2名):
claim(11, 2, ["0x887610ccbf6ff730a639c5ec66d671b53ea0e4b57e1d0365ac1312d4da91ee70"])
// 获得: 0.8 TEST (40%)
```

***

## 🔐 安全建议

1. **生产环境部署前**：
   * 通过专业审计公司审计代码
   * 在测试网充分测试
   * 使用多签钱包作为 Owner

2. **运营建议**：
   * 设置合理的报名截止时间
   * 比赛开始前锁定报名（调用 finalize）
   * 保存所有 proof 数据以便玩家查询
   * 定期提取剩余资金避免长期锁定

3. **玩家保护**：
   * 提供清晰的比赛规则
   * 公开 Merkle Tree 数据供验证
   * 设置合理的领取期限

***

## 📝 开发工具

### 安装依赖

```bash
npm install ethers
```

### 运行 Merkle 计算脚本

```bash
node scripts/calculate_merkle.js
```

### 自定义获奖者

编辑 `scripts/calculate_merkle.js`：

```javascript
const winners = [
    { address: "0x地址1", rank: 1 },
    { address: "0x地址2", rank: 2 },
    { address: "0x地址3", rank: 3 }
];

const shares = [500, 300, 200];  // 50%, 30%, 20%
const sharesSum = 1000;
```

***

## 📞 联系与支持

* **合约代码**：`contracts/match.sol`
* **文档更新**：请查看最新的 README.md
* **问题反馈**：请创建 Issue

***

## 📄 许可证

MIT License - 详见 contracts/match.sol 文件头部声明
