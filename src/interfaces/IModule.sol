// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/**
 * @title IModule
 * @notice 模块基础接口
 * @dev 所有 SentinelWallet 模块应实现此接口
 */
interface IModule {
    /**
     * @notice 模块类型枚举
     */
    enum ModuleType {
        Executor,    // 执行器模块
        Validator,   // 验证器模块
        Hook,        // 钩子模块
        Recovery     // 恢复模块
    }

    /**
     * @notice 获取模块类型
     * @return 模块类型
     */
    function moduleType() external view returns (ModuleType);

    /**
     * @notice 获取模块名称
     * @return 模块名称
     */
    function moduleName() external view returns (string memory);

    /**
     * @notice 获取模块版本
     * @return 版本号
     */
    function moduleVersion() external view returns (string memory);
}
