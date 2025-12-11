# Sentinel Wallet 架构流程图

## 系统架构图

```
┌─────────────────────────────────────────────────────────────┐
│                    Sentinel Wallet 系统                        │
└─────────────────────────────────────────────────────────────┘
                              │
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
┌──────────────┐      ┌──────────────┐      ┌──────────────┐
│ WalletFactory│      │SentinelWallet│      │    Modules    │
│   (工厂合约)  │      │  (核心钱包)   │      │   (功能模块)   │
└──────────────┘      └──────────────┘      └──────────────┘
        │                     │                     │
        │                     │                     │
        │ 创建钱包              │ 启用/禁用            │
        │                     │                     │
        └─────────────────────┼─────────────────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │  执行交易流程      │
                    └──────────────────┘
```

## 钱包创建流程

```
用户
 │
 │ 1. 调用 WalletFactory.deploy(owner, salt)
 ▼
┌─────────────────┐
│  WalletFactory  │
│                 │
│ getAddress()    │  ← 可选：预先计算地址
│ deploy()        │
└─────────────────┘
 │
 │ 2. CREATE2 部署
 ▼
┌─────────────────┐
│ SentinelWallet  │
│                 │
│ owner = _owner  │
│ nonce = 0       │
│ modules = {}    │
└─────────────────┘
 │
 │ 3. 触发 WalletCreated 事件
 ▼
钱包就绪，可以接收资金和使用
```

## 交易执行流程（三种方式）

### 方式 1: 所有者直接执行

```
钱包所有者
 │
 │ executed(to, value, data)
 ▼
┌─────────────────┐
│ SentinelWallet  │
│                 │
│ 1. 验证 onlyOwner│
│ 2. nonce += 1   │
│ 3. call(to, ...)│
│ 4. emit Executed│
└─────────────────┘
 │
 ▼
目标合约执行
```

### 方式 2: 签名执行（离线签名）

```
用户（离线）
 │
 │ 1. 构建哈希: keccak256(wallet, to, value, data, nonce, chainId)
 │ 2. 使用私钥签名
 ▼
第三方中继者
 │
 │ executeWithSignature(to, value, data, signature)
 ▼
┌─────────────────┐
│ SentinelWallet  │
│                 │
│ 1. 构建哈希      │
│ 2. ECDSA.recover│
│ 3. 验证 signer  │
│    == owner     │
│ 4. nonce += 1   │
│ 5. call(to, ...)│
│ 6. emit Executed│
└─────────────────┘
 │
 ▼
目标合约执行
```

### 方式 3: 模块执行

```
用户/模块
 │
 │ execFromModule(to, value, data)
 ▼
┌─────────────────┐
│ SentinelWallet  │
│                 │
│ 1. 验证 onlyModule│
│ 2. nonce += 1   │
│ 3. call(to, ...)│
│ 4. emit Executed│
└─────────────────┘
 │
 ▼
目标合约执行
```

## 每日限额模块流程

```
用户
 │
 │ exec(wallet, to, value, data)
 ▼
┌──────────────────────┐
│  DailyLimitModule    │
│                      │
│ 1. 获取限额:         │
│    limit = walletLimit│
│    [wallet] || default│
│                      │
│ 2. 计算已支出:       │
│    spent = spent     │
│    [wallet][dayIndex]│
│                      │
│ 3. 验证:             │
│    spent + value     │
│    <= limit          │
│                      │
│ 4. 更新状态:         │
│    spent += value    │
│    (先写后执行)      │
└──────────────────────┘
 │
 │ execFromModule(to, value, data)
 ▼
┌─────────────────┐
│ SentinelWallet  │
│                 │
│ 执行交易         │
└─────────────────┘
```

## 守护者恢复流程

### 设置阶段

```
模块所有者
 │
 │ setGuardian(wallet, guardian)
 ▼
┌──────────────────────┐
│GuardianRecoverModule │
│                      │
│ guardianOf[wallet]   │
│ = guardian           │
└──────────────────────┘
```

### 恢复阶段

```
[用户丢失私钥]
 │
 ▼
守护者
 │
 │ proposeRecovery(wallet, newOwner)
 ▼
┌──────────────────────┐
│GuardianRecoverModule │
│                      │
│ 1. 验证守护者身份    │
│ 2. 创建提案:         │
│    proposals[wallet] │
│    = {newOwner, now} │
│ 3. emit RecoveryProposed│
└──────────────────────┘
 │
 │ 等待 delay 时间
 ▼
任何人
 │
 │ finalizeRecovery(wallet)
 ▼
┌──────────────────────┐
│GuardianRecoverModule │
│                      │
│ 1. 验证延迟已过      │
│ 2. 删除提案          │
│ 3. 调用钱包变更所有者│
└──────────────────────┘
 │
 │ changeOwnerByModule(newOwner)
 ▼
┌─────────────────┐
│ SentinelWallet  │
│                 │
│ owner = newOwner│
│ emit OwnerChanged│
└─────────────────┘
```

## 模块启用流程

```
钱包所有者
 │
 │ enableModule(moduleAddress)
 ▼
┌─────────────────┐
│ SentinelWallet  │
│                 │
│ 1. 验证 onlyOwner│
│ 2. 验证 module  │
│    != address(0)│
│ 3. modules      │
│    [module] = true│
│ 4. emit ModuleEnabled│
└─────────────────┘
 │
 ▼
模块已启用，可以调用 execFromModule
```

## 完整使用场景流程

### 场景：用户创建钱包并设置限额

```
步骤1: 创建钱包
用户 → WalletFactory.deploy(owner, salt) → SentinelWallet 部署

步骤2: 充值
用户 → 向钱包地址转账 ETH

步骤3: 部署限额模块
模块所有者 → 部署 DailyLimitModule(owner, defaultLimit)

步骤4: 启用模块
钱包所有者 → wallet.enableModule(dailyLimitModule)

步骤5: 设置限额（可选）
模块所有者 → dailyLimitModule.setWalletLimit(wallet, customLimit)

步骤6: 使用钱包
用户 → dailyLimitModule.exec(wallet, to, value, data)
     → 限额检查
     → wallet.execFromModule(...)
     → 执行交易
```

### 场景：紧急恢复钱包

```
步骤1: 设置守护者（提前）
模块所有者 → guardianModule.setGuardian(wallet, guardian)

步骤2: 用户丢失私钥
[私钥丢失]

步骤3: 守护者发起恢复
守护者 → guardianModule.proposeRecovery(wallet, newOwner)
      → 创建提案，记录时间戳

步骤4: 等待延迟
[等待 delay 时间，例如 7 天]

步骤5: 执行恢复
任何人 → guardianModule.finalizeRecovery(wallet)
      → 验证延迟已过
      → wallet.changeOwnerByModule(newOwner)
      → 所有者变更成功
```

## 状态转换图

### 钱包状态

```
[未部署]
  │
  │ WalletFactory.deploy()
  ▼
[已部署，无模块]
  │
  │ enableModule()
  ▼
[已部署，有模块]
  │
  │ exec*() 方法
  ▼
[执行交易]
```

### 恢复提案状态

```
[无提案]
  │
  │ proposeRecovery()
  ▼
[提案中，等待延迟]
  │
  │ 等待 delay 时间
  ▼
[可执行]
  │
  │ finalizeRecovery()
  ▼
[已执行，无提案]
```

### 每日限额状态

```
[新的一天开始]
  │
  │ dayIndex = block.timestamp / 1 days
  ▼
[当天限额可用]
  │
  │ exec() 交易
  ▼
[更新 spent[dayIndex]]
  │
  │ 如果 spent >= limit
  ▼
[当日限额已用完]
  │
  │ 等待下一天
  ▼
[新的一天，限额重置]
```

## 数据流图

```
用户输入
  │
  ├─→ WalletFactory → CREATE2 → SentinelWallet
  │
  ├─→ SentinelWallet.executed() → 直接执行
  │
  ├─→ SentinelWallet.executeWithSignature() → 签名验证 → 执行
  │
  └─→ Module.exec() → 模块逻辑 → SentinelWallet.execFromModule() → 执行
```

## 安全机制流程图

### 防重放攻击

```
交易请求
  │
  ├─→ 包含 nonce
  ├─→ 包含 chainId
  └─→ 包含钱包地址
  │
  ▼
构建哈希
  │
  ▼
签名验证
  │
  ▼
nonce += 1 (状态更新)
  │
  ▼
执行交易
```

### 限额保护

```
交易请求
  │
  ├─→ 获取限额
  ├─→ 获取已支出
  └─→ 计算 dayIndex
  │
  ▼
验证: spent + value <= limit
  │
  ▼
更新 spent[dayIndex] += value (先写)
  │
  ▼
执行交易
```

### 恢复延迟保护

```
恢复提案
  │
  ├─→ 记录时间戳
  └─→ 设置延迟时间
  │
  ▼
等待 delay 时间
  │
  ▼
验证: now >= proposal.at + delay
  │
  ▼
执行恢复
```

---

## 总结

以上流程图展示了 Sentinel Wallet 系统的完整架构和业务流程。系统通过模块化设计实现了：

1. **灵活的钱包创建** - 使用 CREATE2 确定性地址
2. **多种执行方式** - 直接、签名、模块三种方式
3. **安全保护机制** - 限额、延迟、防重放
4. **可扩展架构** - 模块化设计，易于添加新功能
