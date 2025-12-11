# Sentinel Wallet 业务逻辑整合文档

## 项目概述

Sentinel Wallet 是一个模块化的智能钱包系统，支持多种执行方式、模块化扩展和资产恢复功能。

## 核心架构

### 1. 钱包创建流程 (WalletFactory)

**文件**: `src/factory/WalletFactory.sol`

**功能**:

- 使用 CREATE2 确定性地址部署钱包
- 支持通过 `salt` 参数预测钱包地址
- 在部署前可预先计算钱包地址

**关键方法**:

- `getAddress(address owner, bytes32 salt)`: 计算钱包的确定性地址
- `deploy(address owner, bytes32 salt)`: 部署新钱包实例

**业务流程**:

```
用户调用 deploy(owner, salt)
  ↓
工厂合约使用 CREATE2 部署 SentinelWallet
  ↓
钱包地址 = f(工厂地址, salt, 钱包字节码)
  ↓
触发 WalletCreated 事件
```

---

### 2. 核心钱包合约 (SentinelWallet)

**文件**: `src/wallet/SentinelWallet.sol`

**核心功能**:

- 钱包所有者管理
- 模块化扩展支持
- 多种交易执行方式
- 防重放攻击（nonce 机制）

#### 2.1 所有者管理

**状态变量**:

- `owner`: 钱包所有者地址
- `nonce`: 交易计数器，防止重放攻击
- `modules`: 已启用的模块映射

**权限控制**:

- `onlyOwner`: 仅所有者可调用
- `onlyModule`: 仅已启用的模块可调用

#### 2.2 模块管理

**方法**:

- `enableModule(address module)`: 启用模块（仅所有者）
- `disableModule(address module)`: 禁用模块（仅所有者）

**业务流程**:

```
所有者调用 enableModule(moduleAddress)
  ↓
验证 moduleAddress != address(0)
  ↓
设置 modules[moduleAddress] = true
  ↓
触发 ModuleEnabled 事件
```

#### 2.3 交易执行方式

钱包支持三种执行方式：

##### 方式 1: 所有者直接执行

```solidity
executed(address to, uint256 value, bytes calldata data)
```

- **调用者**: 钱包所有者
- **流程**: 验证权限 → 递增 nonce → 执行调用 → 触发事件

##### 方式 2: 签名执行（离线签名）

```solidity
executeWithSignature(address to, uint256 value, bytes calldata data, bytes calldata signature)
```

- **调用者**: 任何人（第三方中继）
- **流程**:
  ```
  构建哈希 = keccak256(钱包地址, to, value, data哈希, nonce, chainId)
    ↓
  使用 ECDSA 恢复签名者地址
    ↓
  验证签名者 == owner
    ↓
  递增 nonce
    ↓
  执行调用
    ↓
  触发 Executed 事件
  ```
- **优势**: 支持离线签名，无需直接连接区块链

##### 方式 3: 模块执行

```solidity
execFromModule(address to, uint256 value, bytes calldata data)
```

- **调用者**: 已启用的模块
- **流程**: 验证模块权限 → 递增 nonce → 执行调用 → 触发事件

#### 2.4 所有者变更

**方法**:

- `changeOwner(address newOwner)`: 所有者直接变更（仅所有者）
- `changeOwnerByModule(address newOwner)`: 模块变更所有者（仅模块）

---

### 3. 每日限额模块 (DailyLimitModule)

**文件**: `src/wallet/modules/DailyLimitModule.sol`

**功能**: 为每个钱包设置每日转账限额，防止大额资产被盗

**核心状态**:

- `deafultDailyLimit`: 默认每日限额
- `walletLimit`: 每个钱包的自定义限额
- `spent[wallet][dayIndex]`: 某钱包在某天的已支出金额

**业务流程**:

#### 3.1 设置钱包限额

```
模块所有者调用 setWalletLimit(wallet, limit)
  ↓
验证 limit > 0
  ↓
设置 walletLimit[wallet] = limit
  ↓
触发 SetWalletLimit 事件
```

#### 3.2 执行交易（带限额检查）

```
用户调用 exec(wallet, to, value, data)
  ↓
获取钱包限额: limit = walletLimit[wallet] || defaultDailyLimit
  ↓
计算当天已支出: dailySpent = spent[wallet][dayIndex]
  ↓
验证: dailySpent + value <= limit
  ↓
更新已支出: spent[wallet][dayIndex] += value (先写后执行，防止重放)
  ↓
调用钱包的 execFromModule(to, value, data)
  ↓
触发 Exec 事件
```

**安全特性**:

- 先更新状态再执行，防止重放攻击
- 按天重置限额（使用 `block.timestamp / 1 days` 作为 dayIndex）
- 支持为不同钱包设置不同限额

---

### 4. 守护者恢复模块 (GuardianRecoverModule)

**文件**: `src/wallet/modules/GuardianRecoverModule.sol`

**功能**: 当用户丢失私钥时，通过可信守护者恢复钱包所有权

**核心状态**:

- `delay`: 恢复延迟时间（安全机制）
- `guardianOf[wallet]`: 每个钱包的守护者地址
- `proposals[wallet]`: 待执行的恢复提案

**业务流程**:

#### 4.1 设置守护者

```
模块所有者调用 setGuardian(wallet, guardian)
  ↓
验证 guardian != address(0)
  ↓
设置 guardianOf[wallet] = guardian
  ↓
触发 GuardianSet 事件
```

#### 4.2 发起恢复提案

```
守护者调用 proposeRecovery(wallet, proposed)
  ↓
验证 proposed != address(0)
  ↓
验证 msg.sender == guardianOf[wallet]
  ↓
创建提案: proposals[wallet] = {proposed, block.timestamp}
  ↓
触发 RecoveryProposed 事件
```

#### 4.3 执行恢复

```
任何人调用 finalizeRecovery(wallet)
  ↓
获取提案: proposal = proposals[wallet]
  ↓
验证: block.timestamp >= proposal.at + delay (延迟已过)
  ↓
删除提案
  ↓
调用钱包的 changeOwnerByModule(proposed)
  ↓
触发 RecoveryFinalized 事件
```

**安全特性**:

- **延迟机制**: 提案创建后需等待 `delay` 时间才能执行，给用户时间发现并取消恶意提案
- **守护者验证**: 只有预设的守护者可以发起恢复提案
- **公开执行**: 任何人都可以执行已过期的提案，确保去中心化

---

## 完整业务流程串联

### 场景 1: 用户创建钱包并使用

```
1. 用户调用 WalletFactory.deploy(owner, salt)
   ↓
2. 工厂部署 SentinelWallet(owner)
   ↓
3. 用户获得钱包地址（可通过 getAddress 预先计算）
   ↓
4. 用户向钱包充值 ETH
   ↓
5. 用户直接调用 wallet.executed(to, value, data) 执行交易
   或
   用户离线签名，第三方调用 wallet.executeWithSignature(...)
```

### 场景 2: 启用每日限额模块

```
1. 部署 DailyLimitModule(moduleOwner, defaultLimit)
   ↓
2. 钱包所有者调用 wallet.enableModule(dailyLimitModule)
   ↓
3. 模块所有者调用 dailyLimitModule.setWalletLimit(wallet, customLimit)
   ↓
4. 用户调用 dailyLimitModule.exec(wallet, to, value, data)
   ↓
5. 模块检查限额 → 更新已支出 → 调用 wallet.execFromModule(...)
   ↓
6. 钱包执行交易
```

### 场景 3: 设置守护者并恢复钱包

```
1. 部署 GuardianRecoverModule(moduleOwner, delay)
   ↓
2. 钱包所有者调用 wallet.enableModule(guardianModule)
   ↓
3. 模块所有者调用 guardianModule.setGuardian(wallet, guardian)
   ↓
4. [用户丢失私钥]
   ↓
5. 守护者调用 guardianModule.proposeRecovery(wallet, newOwner)
   ↓
6. 等待 delay 时间
   ↓
7. 任何人调用 guardianModule.finalizeRecovery(wallet)
   ↓
8. 模块调用 wallet.changeOwnerByModule(newOwner)
   ↓
9. 钱包所有者变更为 newOwner
```

### 场景 4: 组合使用（限额 + 守护者）

```
1. 钱包同时启用 DailyLimitModule 和 GuardianRecoverModule
   ↓
2. 日常使用: 通过 DailyLimitModule 执行交易（受限额保护）
   ↓
3. 紧急情况: 通过 GuardianRecoverModule 恢复所有权
   ↓
4. 新所有者可以继续使用钱包，限额设置保持不变
```

---

## 安全机制总结

### 1. 防重放攻击

- **nonce 机制**: 每次执行交易后 nonce 递增
- **签名验证**: 签名包含 nonce 和 chainId，防止跨链重放

### 2. 权限控制

- **所有者权限**: 直接执行、启用/禁用模块、变更所有者
- **模块权限**: 通过模块执行交易、变更所有者（需钱包启用）

### 3. 限额保护

- **每日限额**: 防止大额资产一次性被盗
- **状态先写**: 先更新已支出金额，再执行交易，防止重放

### 4. 恢复机制

- **延迟执行**: 恢复提案需等待延迟时间，给用户反应时间
- **守护者验证**: 只有预设守护者可发起恢复

---

## 模块化设计优势

1. **可扩展性**: 可以轻松添加新模块（如多签模块、时间锁模块等）
2. **灵活性**: 钱包可以选择性启用需要的模块
3. **安全性**: 模块需被钱包所有者显式启用
4. **可组合性**: 多个模块可以同时工作，互不干扰

---

## 待完善功能

根据代码分析，以下文件目前为空或未实现：

1. **WalletLogic.sol**: 钱包逻辑（可能用于可升级钱包）
2. **ModuleManager.sol**: 模块管理器（可能用于统一管理模块）
3. **Signature.sol**: 签名工具（注释显示后续实现 ECDSA 恢复逻辑）

---

## 技术栈

- **Solidity**: ^0.8.21
- **OpenZeppelin**: ECDSA, MessageHashUtils
- **Foundry**: 开发框架
- **CREATE2**: 确定性地址部署

---

## 总结

Sentinel Wallet 是一个功能完整、安全可靠的智能钱包系统，通过模块化设计实现了：

- ✅ 多种交易执行方式（直接、签名、模块）
- ✅ 每日限额保护
- ✅ 守护者恢复机制
- ✅ 防重放攻击
- ✅ 灵活的权限管理

整个系统设计清晰，各组件职责明确，具有良好的安全性和可扩展性。
