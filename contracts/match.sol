// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// 引入 OpenZeppelin 的 Ownable 合约，提供 onlyOwner 权限控制
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
// 引入 ERC20 标准接口
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// 引入安全的 ERC20 操作库，处理某些非标准代币的返回值问题（如 USDT）
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// 比赛分发合约：支持 ERC20 奖金（例如 USDT），报名费并入奖池，Merkle 证明胜者与名次，链上按比例计算发放
contract TournamentDistributor is Ownable {
    using SafeERC20 for IERC20; // 为 IERC20 增加 safeTransfer/safeTransferFrom 等安全方法

    // 每场比赛的基本信息
    struct MatchInfo {
        address token;            // 比赛使用的代币（报名费与奖池同一个代币，例：USDT）
        uint256 fixedPool;        // 最终锁定用于分配的基准总额（finalize 时确定，之后不随余额变化）
        bytes32 merkleRoot;       // (player, rank) 的 Merkle 根，证明某地址对应的名次
        uint32 sharesSum;         // 份额总和（例如 1000；每个名次有相应 share，金额= fixedPool*share/sharesSum）
        uint96 entryFee;          // 报名费（代币最小单位计价；USDT 通常是 6 位小数，1 USDT=1_000_000）
        uint64 registerDeadline;  // 报名截止时间（Unix 时间戳；0 表示不限时）
        bool finalized;           // 是否已最终确定（锁定参数与 fixedPool；finalize 后不可报名或改参数）
    }

    // matchId => MatchInfo，存储每场比赛的配置
    mapping(uint256 => MatchInfo) public matches;

    // matchId => rank(从1开始) => 该名次对应的份额 share
    mapping(uint256 => mapping(uint256 => uint32)) public rankShare;

    // matchId => 当前池子余额（报名费 + 赛事赞助 - 已领取 - 已提取）
    // 这是逻辑余额；实际代币都在合约地址上，按 matchId 逻辑划分账本
    mapping(uint256 => uint256) public poolBalance;

    // matchId => 地址 => 是否已报名（报名费已支付）
    mapping(uint256 => mapping(address => bool)) public registered;

    // matchId => 地址 => 是否已领取（防重复领取）
    mapping(uint256 => mapping(address => bool)) public claimed;

    // 各类事件，便于前端与审计追踪
    event MatchCreated(uint256 indexed matchId, address token, uint96 entryFee, uint64 registerDeadline);
    event Sponsored(uint256 indexed matchId, address indexed from, uint256 amount);
    event Registered(uint256 indexed matchId, address indexed player, uint256 fee);
    event Finalized(uint256 indexed matchId, uint256 fixedPool, bytes32 merkleRoot);
    event Claimed(uint256 indexed matchId, address indexed player, uint256 rank, uint256 amount);
    event Skimmed(uint256 indexed matchId, address indexed to, uint256 amount);

    // 构造函数：指定初始 owner（拥有 onlyOwner 权限）
    constructor(address initialOwner) Ownable(initialOwner) {}

    // 创建/配置一场新的比赛（设置代币、报名费、报名截止时间）
    function createMatch(
        uint256 matchId,           // 比赛唯一标识
        address token,             // 奖金/报名费代币地址（如 USDT 合约地址）
        uint96 entryFee,           // 报名费（代币最小单位）
        uint64 registerDeadline    // 报名截止时间（Unix 时间戳）
    ) external onlyOwner {
        require(token != address(0), "token=0");         // 代币地址不得为 0
        MatchInfo storage m = matches[matchId];
        require(m.token == address(0), "exists");        // 防止重复创建同一 matchId
        m.token = token;                                 // 记录代币
        m.entryFee = entryFee;                           // 记录报名费
        m.registerDeadline = registerDeadline;           // 记录报名截止
        emit MatchCreated(matchId, token, entryFee, registerDeadline);
    }

    // 赛事方注资（赞助）：将 ERC20 代币从 owner 转入合约，增加该场比赛的池子余额
    function sponsor(uint256 matchId, uint256 amount) external onlyOwner {
        require(amount > 0, "amount=0");                 // 金额必须大于0
        MatchInfo storage m = matches[matchId];
        require(m.token != address(0), "match not set"); // 比赛需已创建
        IERC20(m.token).safeTransferFrom(msg.sender, address(this), amount); // 从 owner 拉取代币
        poolBalance[matchId] += amount;                  // 增加该场比赛的逻辑余额
        emit Sponsored(matchId, msg.sender, amount);
    }

    // 玩家报名：支付报名费到合约，并将报名费并入该场比赛的奖池
    function register(uint256 matchId) external {
        MatchInfo storage m = matches[matchId];
        require(m.token != address(0), "match not set"); // 比赛需已创建
        require(!m.finalized, "finalized");              // 已 finalize 的比赛不允许再报名
        if (m.registerDeadline != 0) {                   // 若设置了截止时间
            require(block.timestamp <= m.registerDeadline, "registration closed"); // 需在截止前
        }
        require(!registered[matchId][msg.sender], "already registered"); // 防止重复报名
        uint256 fee = uint256(m.entryFee);               // 取报名费金额
        require(fee > 0, "entry fee=0");                 // 报名费需大于0

        IERC20(m.token).safeTransferFrom(msg.sender, address(this), fee); // 从玩家拉取报名费
        registered[matchId][msg.sender] = true;          // 标记已报名
        poolBalance[matchId] += fee;                     // 报名费加入奖池逻辑余额

        emit Registered(matchId, msg.sender, fee);
    }

    // 最终确定比赛：设置各名次份额、Merkle 根，并锁定 fixedPool（用于之后按比例计算发放）
    // shares 示例：[500, 300, 200]；sharesSum=1000；rank 从1开始对应 shares[0]
    // fixedPoolInput=0 时，用当前 poolBalance 作为 fixedPool；否则使用传入值（需 <= 当前余额）
    function finalize(
        uint256 matchId,            // 比赛ID
        uint32[] calldata shares,   // 各名次份额数组（长度=发奖名次数）
        uint32 sharesSum,           // 份额总和（通常为 shares 的和，也可指定其它基准）
        bytes32 merkleRoot,         // (player, rank) 的 Merkle 根
        uint256 fixedPoolInput      // 锁定用于分配的基准总额（0 表示自动使用当前 poolBalance）
    ) external onlyOwner {
        MatchInfo storage m = matches[matchId];
        require(!m.finalized, "already finalized");      // 防止重复 finalize
        require(m.token != address(0), "match not set"); // 比赛需已创建
        require(merkleRoot != bytes32(0), "root=0");     // Merkle 根不得为 0
        require(shares.length > 0 && sharesSum > 0, "bad shares"); // 份额配置需有效

        // 写入每个名次的份额（rank 从1开始）
        for (uint256 i = 0; i < shares.length; i++) {
            require(shares[i] > 0, "zero share");        // 每个名次份额需大于0
            rankShare[matchId][i + 1] = shares[i];
        }
        m.sharesSum = sharesSum;                         // 记录份额总和
        m.merkleRoot = merkleRoot;                       // 记录 merkle 根

        // 锁定用于分配的固定池：之后发放都基于 fixedPool 计算，不受后续余额变化影响
        uint256 poolNow = poolBalance[matchId];          // 当前逻辑余额
        uint256 fixedPool = fixedPoolInput == 0 ? poolNow : fixedPoolInput; // 选择锁定值
        require(fixedPool <= poolNow, "fixedPool > poolBalance"); // 不能超过当前余额，避免超发
        m.fixedPool = fixedPool;                         // 记录固定池

        m.finalized = true;                              // 标记 finalize 完成
        emit Finalized(matchId, fixedPool, merkleRoot);
    }

    // 选手领取奖金：要求已经报名、未领取、Merkle 证明有效
    function claim(uint256 matchId, uint256 rank, bytes32[] calldata proof) external {
        MatchInfo memory m = matches[matchId];
        require(m.finalized, "not finalized");           // 必须 finalize 之后才能领取
        require(registered[matchId][msg.sender], "not registered"); // 仅报名地址可领
        require(!claimed[matchId][msg.sender], "claimed");          // 防重复领取

        // 计算叶子：与链下叶子保持一致 (player, rank)
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, rank));
        // 验证排序配对的 Merkle 证明（与 OpenZeppelin StandardMerkleTree 默认兼容）
        require(_verifySortedMerkleProof(proof, m.merkleRoot, leaf), "bad proof");

        // 根据 rank 的份额按比例计算金额（整数除法会产生尾差）
        uint32 share = rankShare[matchId][rank];
        require(share > 0, "invalid rank");             // rank 必须在份额表中
        uint256 amount = (m.fixedPool * share) / m.sharesSum;
        require(amount > 0, "zero payout");             // 份额太小或 fixedPool=0 时可能为 0
        require(poolBalance[matchId] >= amount, "pool shortage"); // 余额须充足（通常应充足）

        // 更新状态并发放代币
        claimed[matchId][msg.sender] = true;            // 标记已领取
        poolBalance[matchId] -= amount;                 // 从逻辑余额中扣减
        IERC20(m.token).safeTransfer(msg.sender, amount); // 转账给领取者

        emit Claimed(matchId, msg.sender, rank, amount);
    }

    // 管理员提取剩余资金（尾差、未领取余额等），用于赛后结算或归集
    function skim(uint256 matchId, address to, uint256 amount) external onlyOwner {
        require(to != address(0), "to=0");              // 收款地址不能为 0
        require(poolBalance[matchId] >= amount, "insufficient"); // 需有足够逻辑余额
        poolBalance[matchId] -= amount;                 // 扣减逻辑余额
        IERC20(matches[matchId].token).safeTransfer(to, amount); // 实际转账
        emit Skimmed(matchId, to, amount);
    }

    // 视图函数：一次性返回该场比赛的关键公开信息（便于前端拉取显示）
    function getMatchInfo(uint256 matchId)
        external
        view
        returns (
            address token,           // 代币地址
            uint96 entryFee,         // 报名费
            uint64 registerDeadline, // 报名截止
            uint256 fixedPool,       // 锁定分配基数
            uint256 currentPool,     // 当前逻辑余额
            bytes32 merkleRoot,      // Merkle 根
            uint32 sharesSum,        // 份额总和
            bool finalized           // 是否已 finalize
        )
    {
        MatchInfo memory m = matches[matchId];
        return (
            m.token,
            m.entryFee,
            m.registerDeadline,
            m.fixedPool,
            poolBalance[matchId],
            m.merkleRoot,
            m.sharesSum,
            m.finalized
        );
    }

    // 视图函数：查询某个名次的份额与按比例计算出来的应得金额
    function quotePayoutByRank(uint256 matchId, uint256 rank) external view returns (uint32 share, uint256 amount) {
        MatchInfo memory m = matches[matchId];
        share = rankShare[matchId][rank];               // 获取该 rank 的份额
        if (share == 0 || m.sharesSum == 0) return (share, 0); // 若份额或总和为 0，直接返回 0
        amount = (m.fixedPool * share) / m.sharesSum;   // 按比例计算金额
    }

    // 视图函数：查询某玩家的报名与领取状态
    function status(uint256 matchId, address player) external view returns (bool isRegistered, bool isClaimed) {
        isRegistered = registered[matchId][player];     // 是否已报名
        isClaimed = claimed[matchId][player];           // 是否已领取
    }

    // 内部函数：排序配对的 Merkle 证明验证（与 OZ StandardMerkleTree 默认排序行为一致）
    // 验证逻辑：每层都将 (computed, sibling) 按字典序小的在前拼接，再 keccak256
    function _verifySortedMerkleProof(bytes32[] calldata proof, bytes32 root, bytes32 leaf) internal pure returns (bool) {
        bytes32 computed = leaf;                        // 初始为叶子
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 sibling = proof[i];                // 同层兄弟节点
            // 按大小排序后拼接，确保与构建树时的排序规则一致
            computed = computed <= sibling
                ? keccak256(abi.encodePacked(computed, sibling))
                : keccak256(abi.encodePacked(sibling, computed));
        }
        return computed == root;                       // 计算结果需等于根
    }
}