// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/**
 * @title Errors
 * @notice 统一的自定义错误定义
 * @dev 使用自定义错误可以节省 Gas，比字符串错误更高效
 */
library Errors {
    // ============ SentinelWallet 错误 ============
    
    /// @notice 调用者不是所有者
    error NotOwner();
    
    /// @notice 调用者不是已启用的模块
    error NotEnabledModule();
    
    /// @notice 地址不能为零地址
    error ZeroAddress();
    
    /// @notice 模块地址不能为零地址
    error ModuleCannotBeZero();
    
    /// @notice 调用失败
    error CallFailed();
    
    /// @notice 签名无效
    error InvalidSignature();
    
    /// @notice 所有者不能为零地址
    error OwnerCannotBeZero();

    // ============ DailyLimitModule 错误 ============
    
    /// @notice 超出每日限额
    error ExceedingDailyLimit();
    
    /// @notice 默认限额必须大于0
    error DefaultLimitMustBeGreaterThanZero();
    
    /// @notice 限额必须大于0
    error LimitMustBeGreaterThanZero();

    // ============ GuardianRecoverModule 错误 ============
    
    /// @notice 守护者不能为零地址
    error GuardianCannotBeZero();
    
    /// @notice 提议的新所有者不能为零地址
    error ProposedCannotBeZero();
    
    /// @notice 调用者不是守护者
    error NotGuardian();
    
    /// @notice 延迟时间未到
    error DelayNotPassed();

    // ============ WalletFactory 错误 ============
    
    /// @notice 部署失败
    error DeploymentFailed();
}
