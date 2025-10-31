/**
 * 计算比赛获奖者的 Merkle Root 和每个地址的 Proof
 * 用于 TournamentDistributor 合约的 finalize 和 claim 函数
 *
 * 纯 JavaScript 版本，可直接用 node 运行
 */

const { ethers } = require("ethers");

/**
 * 计算单个叶子节点的哈希
 * 对应合约中的: keccak256(abi.encodePacked(player, rank))
 */
function calculateLeaf(address, rank) {
  return ethers.solidityPackedKeccak256(
    ["address", "uint256"],
    [address, rank]
  );
}

/**
 * 计算两个节点的父节点（排序配对）
 * 对应合约中的排序 Merkle 验证逻辑
 */
function hashPair(left, right) {
  // 按字典序排序后拼接
  if (left <= right) {
    return ethers.keccak256(ethers.concat([left, right]));
  } else {
    return ethers.keccak256(ethers.concat([right, left]));
  }
}

/**
 * 构建 Merkle Tree 并返回 root 和每个叶子的 proof
 */
function buildMerkleTree(winners) {
  // 计算所有叶子节点
  const leafNodes = winners.map((w) => ({
    address: w.address,
    rank: w.rank,
    hash: calculateLeaf(w.address, w.rank),
  }));

  // 按哈希值排序（字典序）
  leafNodes.sort((a, b) => {
    if (a.hash < b.hash) return -1;
    if (a.hash > b.hash) return 1;
    return 0;
  });

  console.log("\n=== 叶子节点（已排序）===");
  leafNodes.forEach((node, index) => {
    console.log(`[${index}] Address: ${node.address}, Rank: ${node.rank}`);
    console.log(`    Hash: ${node.hash}`);
  });

  // 存储每个地址对应的叶子哈希
  const leaves = new Map();
  leafNodes.forEach((node) => {
    leaves.set(node.address, node.hash);
  });

  // 如果只有一个叶子，直接返回
  if (leafNodes.length === 1) {
    const proofs = new Map();
    proofs.set(leafNodes[0].address, []);
    return {
      root: leafNodes[0].hash,
      proofs,
      leaves,
    };
  }

  // 构建 Merkle Tree（简化版本，适用于小规模数据）
  let currentLevel = leafNodes.map((n) => n.hash);
  const tree = [currentLevel];

  // 逐层向上构建
  while (currentLevel.length > 1) {
    const nextLevel = [];
    for (let i = 0; i < currentLevel.length; i += 2) {
      if (i + 1 < currentLevel.length) {
        // 配对哈希
        const parent = hashPair(currentLevel[i], currentLevel[i + 1]);
        nextLevel.push(parent);
      } else {
        // 奇数个节点，最后一个直接提升
        nextLevel.push(currentLevel[i]);
      }
    }
    tree.push(nextLevel);
    currentLevel = nextLevel;
  }

  const root = currentLevel[0];

  // 为每个叶子生成 proof
  const proofs = new Map();

  leafNodes.forEach((node, leafIndex) => {
    const proof = [];
    let index = leafIndex;

    for (let level = 0; level < tree.length - 1; level++) {
      const levelNodes = tree[level];
      const isRightNode = index % 2 === 1;
      const siblingIndex = isRightNode ? index - 1 : index + 1;

      if (siblingIndex < levelNodes.length) {
        proof.push(levelNodes[siblingIndex]);
      }

      index = Math.floor(index / 2);
    }

    proofs.set(node.address, proof);
  });

  return { root, proofs, leaves };
}

/**
 * 格式化 proof 数组为 Remix 可用的格式
 */
function formatProofForRemix(proof) {
  if (proof.length === 0) {
    return "[]";
  }
  return '["' + proof.join('","') + '"]';
}

/**
 * 主函数：计算并打印结果
 */
function main() {
  // ===== 配置区域：修改这里的数据 =====
  const winners = [
    { address: "0x5B38Da6a701c568545dCfcB03FcB875f56beddC4", rank: 1 }, // 第1名
    { address: "0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2", rank: 2 }, // 第2名
  ];

  const matchId = 11;
  const shares = [600, 400]; // 第1名60%，第2名40%
  const sharesSum = 1000;
  // ===== 配置区域结束 =====

  console.log("==========================================");
  console.log("    Merkle Root 计算工具");
  console.log("==========================================");
  console.log(`\n比赛 ID: ${matchId}`);
  console.log(`份额分配: ${shares.join(", ")}`);
  console.log(`份额总和: ${sharesSum}`);
  console.log(`\n获奖者数量: ${winners.length}`);

  // 构建 Merkle Tree
  const { root, proofs, leaves } = buildMerkleTree(winners);

  console.log("\n\n=== Merkle Root ===");
  console.log(root);

  console.log("\n\n=== Remix finalize 函数调用参数 ===");
  console.log(`matchId: ${matchId}`);
  console.log(`shares: [${shares.join(",")}]`);
  console.log(`sharesSum: ${sharesSum}`);
  console.log(`merkleRoot: ${root}`);
  console.log(`fixedPoolInput: 0`);

  console.log("\n\n=== 每个地址的 Claim 信息 ===");
  winners.forEach((winner) => {
    const proof = proofs.get(winner.address) || [];
    console.log(`\n地址: ${winner.address}`);
    console.log(`排名: ${winner.rank}`);
    console.log(`叶子哈希: ${leaves.get(winner.address)}`);
    console.log(`Proof: ${JSON.stringify(proof, null, 2)}`);
    console.log(`\nRemix claim 调用参数:`);
    console.log(`  matchId: ${matchId}`);
    console.log(`  rank: ${winner.rank}`);
    console.log(`  proof: ${formatProofForRemix(proof)}`);
  });

  console.log("\n\n==========================================");
  console.log("提示：");
  console.log("1. 复制 merkleRoot 到 finalize 函数");
  console.log("2. 保存每个地址的 proof 用于后续 claim");
  console.log("3. 如需修改获奖者，请编辑脚本顶部的 winners 数组");
  console.log("==========================================\n");
}

// 运行主函数
main();

/**
 * 使用方法：
 *
 * 1. 确保已安装 ethers.js:
 *    npm install ethers
 *
 * 2. 在终端运行:
 *    node scripts/calculate_merkle.js
 *
 * 3. 修改配置：
 *    - 编辑 winners 数组添加/修改获奖者地址和名次
 *    - 修改 shares 数组设置奖金比例
 *    - 修改 matchId 为实际的比赛ID
 */
