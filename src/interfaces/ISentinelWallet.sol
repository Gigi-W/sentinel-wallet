// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/**
 * @title ISentinelWallet
 * @notice 统一的 SentinelWallet 接口定义
 * @dev 所有模块应使用此接口与钱包交互
 */
interface ISentinelWallet {
    /**
     * @notice 模块执行交易
     * @param to 目标地址
     * @param value 发送的以太币数量
     * @param data 调用数据
     * @return result 执行结果
     */
    function execFromModule(
        address to,
        uint256 value,
        bytes calldata data
    ) external returns (bytes memory result);

    /**
     * @notice 模块修改所有者
     * @param newOwner 新所有者地址
     */
    function changeOwnerByModule(address newOwner) external;

    /**
     * @notice 获取当前 nonce
     * @return 当前 nonce 值
     */
    function nonce() external view returns (uint256);

    /**
     * @notice 获取钱包所有者
     * @return 所有者地址
     */
    function owner() external view returns (address);

    /**
     * @notice 检查模块是否已启用
     * @param module 模块地址
     * @return 是否已启用
     */
    function isModuleEnabled(address module) external view returns (bool);

    /**
     * @notice 获取所有已启用的模块列表
     * @return 模块地址数组
     */
    function getModules() external view returns (address[] memory);
}
