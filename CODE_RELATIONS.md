# Sentinel Wallet 代码关系图

## 合约依赖关系

```
┌─────────────────────────────────────────────────────────────┐
│                     外部依赖库                                │
│                                                              │
│  OpenZeppelin Contracts                                     │
│  ├─ ECDSA.sol                                               │
│  └─ MessageHashUtils.sol                                    │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ import
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Sentinel Wallet 项目                       │
│                                                              │
│  ┌──────────────────┐         ┌──────────────────┐          │
│  │  WalletFactory   │         │ SentinelWallet   │          │
│  │                  │         │                  │          │
│  │ - getAddress()   │────────▶│ - owner          │          │
│  │ - deploy()       │ creates │ - nonce          │          │
│  └──────────────────┘         │ - modules        │          │
│                               │                  │          │
│                               │ - executed()     │          │
│                               │ - executeWithSig │          │
│                               │ - execFromModule │◀─────────┼─┐
│                               │ - enableModule() │          │ │
│                               │ - changeOwner()  │          │ │
│                               └──────────────────┘          │ │
│                                        │                    │ │
│                                        │ implements         │ │
│                                        │                    │ │
│  ┌──────────────────┐         ┌───────┴────────┐           │ │
│  │ DailyLimitModule │         │ ISentinelWallet│           │ │
│  │                  │         │                │           │ │
│  │ - exec()         │────────▶│ - execFromModule│           │ │
│  │                  │ calls   └────────────────┘           │ │
│  └──────────────────┘                                       │ │
│                                        │                    │ │
│  ┌──────────────────┐         ┌───────┴────────┐           │ │
│  │GuardianRecover   │         │ ISentinelWallet│           │ │
│  │     Module       │         │                │           │ │
│  │                  │         │ - changeOwner  │           │ │
│  │ - finalizeRecovery│───────▶│   ByModule()   │           │ │
│  │                  │ calls   └────────────────┘           │ │
│  └──────────────────┘                                       │ │
│                                                              │ │
│  ┌──────────────────┐                                       │ │
│  │   Signature.sol  │                                       │ │
│  │   (待实现)        │                                       │ │
│  └──────────────────┘                                       │ │
│                                                              │ │
│  ┌──────────────────┐                                       │ │
│  │  WalletLogic.sol │                                       │ │
│  │   (待实现)        │                                       │ │
│  └──────────────────┘                                       │ │
│                                                              │ │
│  ┌──────────────────┐                                       │ │
│  │ ModuleManager.sol│                                       │ │
│  │   (待实现)        │                                       │ │
│  └──────────────────┘                                       │ │
└─────────────────────────────────────────────────────────────┘
```

## 接口定义

### ISentinelWallet 接口

```solidity
// 在 DailyLimitModule.sol 中定义
interface ISentinelWallet {
    function execFromModule(
        address to,
        uint256 value,
        bytes calldata data
    ) external returns(bytes memory);
}

// 在 GuardianRecoverModule.sol 中定义
interface ISentinelWallet {
    function changeOwnerByModule(address newOwner) external;
}
```

## 调用关系详解

### 1. WalletFactory → SentinelWallet

```
WalletFactory
  │
  │ new SentinelWallet{salt: salt}(owner)
  │
  ▼
SentinelWallet
  │
  └─ constructor(address _owner)
     └─ owner = _owner
```

**调用时机**: 创建新钱包时

### 2. SentinelWallet ← DailyLimitModule

```
DailyLimitModule
  │
  │ exec(wallet, to, value, data)
  │
  │ 1. 检查限额
  │ 2. 更新 spent
  │
  │ ISentinelWallet(wallet).execFromModule(to, value, data)
  │
  ▼
SentinelWallet
  │
  │ execFromModule(to, value, data)
  │
  │ 1. 验证 onlyModule
  │ 2. nonce += 1
  │ 3. call(to, value, data)
  │
  ▼
目标合约
```

**调用时机**: 通过限额模块执行交易时

### 3. SentinelWallet ← GuardianRecoverModule

```
GuardianRecoverModule
  │
  │ finalizeRecovery(wallet)
  │
  │ 1. 验证延迟
  │ 2. 删除提案
  │
  │ ISentinelWallet(wallet).changeOwnerByModule(proposed)
  │
  ▼
SentinelWallet
  │
  │ changeOwnerByModule(newOwner)
  │
  │ 1. 验证 onlyModule
  │ 2. owner = newOwner
  │ 3. emit OwnerChanged
  │
  ▼
所有者变更完成
```

**调用时机**: 执行钱包恢复时

## 数据流向

### 钱包创建数据流

```
用户输入 (owner, salt)
  │
  ▼
WalletFactory.getAddress(owner, salt)
  │
  ├─→ 计算 bytecode
  ├─→ 计算 hash
  └─→ 返回预测地址
  │
  ▼
WalletFactory.deploy(owner, salt)
  │
  ├─→ CREATE2 部署
  └─→ 触发 WalletCreated 事件
  │
  ▼
SentinelWallet 实例
  │
  └─→ owner = _owner
     nonce = 0
     modules = {}
```

### 交易执行数据流

#### 直接执行

```
用户输入 (to, value, data)
  │
  ▼
SentinelWallet.executed(to, value, data)
  │
  ├─→ 验证 onlyOwner
  ├─→ nonce += 1
  ├─→ call(to, value, data)
  └─→ emit Executed
  │
  ▼
目标合约执行
```

#### 签名执行

```
用户离线签名
  │
  ├─→ 构建哈希: keccak256(wallet, to, value, dataHash, nonce, chainId)
  └─→ ECDSA 签名
  │
  ▼
第三方中继
  │
  ▼
SentinelWallet.executeWithSignature(to, value, data, signature)
  │
  ├─→ 构建哈希
  ├─→ ECDSA.recover(signature)
  ├─→ 验证 signer == owner
  ├─→ nonce += 1
  ├─→ call(to, value, data)
  └─→ emit Executed
  │
  ▼
目标合约执行
```

#### 模块执行

```
用户输入 (wallet, to, value, data)
  │
  ▼
DailyLimitModule.exec(wallet, to, value, data)
  │
  ├─→ 获取限额
  ├─→ 检查限额
  ├─→ spent[wallet][dayIndex] += value
  │
  │ ISentinelWallet(wallet).execFromModule(to, value, data)
  │
  ▼
SentinelWallet.execFromModule(to, value, data)
  │
  ├─→ 验证 onlyModule
  ├─→ nonce += 1
  ├─→ call(to, value, data)
  └─→ emit Executed
  │
  ▼
目标合约执行
```

## 状态变量访问关系

### SentinelWallet 状态变量

```solidity
address public owner;              // 可被外部读取
uint256 public nonce;              // 可被外部读取
mapping(address => bool) public modules;  // 可被外部读取
```

**访问权限**:

- `owner`: 可被所有合约读取，只能通过 `changeOwner()` 或 `changeOwnerByModule()` 修改
- `nonce`: 可被所有合约读取，只能通过执行方法递增
- `modules`: 可被所有合约读取，只能通过 `enableModule()` / `disableModule()` 修改

### DailyLimitModule 状态变量

```solidity
address public owner;              // 模块所有者
uint256 public deafultDailyLimit;  // 默认限额
mapping(address => mapping(uint256 => uint256)) public spent;  // 已支出
mapping(address => uint256) public walletLimit;  // 钱包限额
```

**访问权限**:

- `owner`: 可被所有合约读取，构造函数设置
- `deafultDailyLimit`: 可被所有合约读取，构造函数设置
- `spent`: 可被所有合约读取，只能通过 `exec()` 修改
- `walletLimit`: 可被所有合约读取，只能通过 `setWalletLimit()` 修改

### GuardianRecoverModule 状态变量

```solidity
address owner;                     // 模块所有者
uint256 delay;                     // 恢复延迟
mapping(address => address) public guardianOf;  // 守护者映射
mapping(address => Proposal) public proposals;  // 恢复提案
```

**访问权限**:

- `owner`: 私有，只能通过构造函数设置
- `delay`: 私有，只能通过构造函数设置
- `guardianOf`: 可被所有合约读取，只能通过 `setGuardian()` 修改
- `proposals`: 可被所有合约读取，通过 `proposeRecovery()` 创建，通过 `finalizeRecovery()` 删除

## 事件流

### 钱包创建事件

```
WalletFactory.deploy()
  │
  └─→ emit WalletCreated(wallet, owner, salt)
      │
      └─→ 链上事件日志
```

### 模块管理事件

```
SentinelWallet.enableModule(module)
  │
  └─→ emit ModuleEnabled(module)

SentinelWallet.disableModule(module)
  │
  └─→ emit ModuleDisabled(module)
```

### 交易执行事件

```
SentinelWallet.executed() / executeWithSignature() / execFromModule()
  │
  └─→ emit Executed(to, value, data, signer)
```

### 所有者变更事件

```
SentinelWallet.changeOwner() / changeOwnerByModule()
  │
  └─→ emit OwnerChanged(oldOwner, newOwner)
```

### 限额模块事件

```
DailyLimitModule.setWalletLimit()
  │
  └─→ emit SetWalletLimit(wallet, limit)

DailyLimitModule.exec()
  │
  └─→ emit Exec(wallet, to, value, dayIndex)
```

### 恢复模块事件

```
GuardianRecoverModule.setGuardian()
  │
  └─→ emit GuardianSet(wallet, guardian)

GuardianRecoverModule.proposeRecovery()
  │
  └─→ emit RecoveryProposed(wallet, guardian, proposed, at)

GuardianRecoverModule.finalizeRecovery()
  │
  └─→ emit RecoveryFinalized(wallet, newOwner)
```

## 权限矩阵

| 操作               | WalletFactory | SentinelWallet          | DailyLimitModule      | GuardianRecoverModule |
| ------------------ | ------------- | ----------------------- | --------------------- | --------------------- |
| 创建钱包           | ✅ 任何人     | -                       | -                     | -                     |
| 直接执行交易       | -             | ✅ 所有者               | -                     | -                     |
| 签名执行交易       | -             | ✅ 任何人（需有效签名） | -                     | -                     |
| 启用模块           | -             | ✅ 所有者               | -                     | -                     |
| 禁用模块           | -             | ✅ 所有者               | -                     | -                     |
| 模块执行交易       | -             | ✅ 已启用模块           | ✅ 任何人（调用模块） | -                     |
| 设置限额           | -             | -                       | ✅ 模块所有者         | -                     |
| 设置守护者         | -             | -                       | -                     | ✅ 模块所有者         |
| 发起恢复提案       | -             | -                       | -                     | ✅ 守护者             |
| 执行恢复           | -             | -                       | -                     | ✅ 任何人（延迟后）   |
| 变更所有者（直接） | -             | ✅ 所有者               | -                     | -                     |
| 变更所有者（模块） | -             | ✅ 已启用模块           | -                     | ✅ 模块调用           |

## 合约交互序列图

### 场景：通过限额模块执行交易

```
用户          DailyLimitModule    SentinelWallet    目标合约
 │                  │                    │              │
 │ exec(...)        │                    │              │
 ├─────────────────>│                    │              │
 │                  │                    │              │
 │                  │ 检查限额           │              │
 │                  │ 更新 spent         │              │
 │                  │                    │              │
 │                  │ execFromModule(...)│              │
 │                  ├───────────────────>│              │
 │                  │                    │              │
 │                  │                    │ 验证模块     │
 │                  │                    │ nonce += 1   │
 │                  │                    │              │
 │                  │                    │ call(...)    │
 │                  │                    ├─────────────>│
 │                  │                    │              │
 │                  │                    │              │ 执行
 │                  │                    │<─────────────┤
 │                  │                    │              │
 │                  │<───────────────────┤              │
 │                  │ 返回结果           │              │
 │<─────────────────┤                    │              │
 │ 返回结果          │                    │              │
```

### 场景：守护者恢复钱包

```
守护者    GuardianRecoverModule    SentinelWallet
 │                  │                    │
 │ proposeRecovery()│                    │
 ├─────────────────>│                    │
 │                  │                    │
 │                  │ 验证守护者         │
 │                  │ 创建提案           │
 │                  │                    │
 │                  │ [等待 delay]       │
 │                  │                    │
 │                  │                    │
 │ finalizeRecovery()│                    │
 ├─────────────────>│                    │
 │                  │                    │
 │                  │ 验证延迟           │
 │                  │ 删除提案           │
 │                  │                    │
 │                  │ changeOwnerByModule│
 │                  ├───────────────────>│
 │                  │                    │
 │                  │                    │ 验证模块
 │                  │                    │ owner = newOwner
 │                  │                    │
 │                  │<───────────────────┤
 │                  │                    │
 │<─────────────────┤                    │
 │ 恢复完成          │                    │
```

---

## 总结

以上代码关系图展示了：

1. **合约依赖关系** - 各合约如何相互依赖和调用
2. **接口定义** - 模块与钱包之间的接口约定
3. **数据流向** - 数据在合约间的流转过程
4. **状态访问** - 各状态变量的访问权限
5. **事件流** - 事件如何被触发和记录
6. **权限矩阵** - 各操作的权限控制
7. **交互序列** - 典型场景下的合约交互流程

这些关系图有助于理解整个系统的架构设计和各组件之间的协作方式。
