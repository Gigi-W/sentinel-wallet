// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "../../utils/Errors.sol";

/**
 * @title ModuleManager
 * @notice 模块管理库，提供模块启用、禁用、查询等功能
 * @dev 使用库来封装模块管理逻辑，状态变量存储在调用合约中
 */
library ModuleManager {
    /// @notice 模块管理数据结构
    struct ModuleStorage {
        // 标记模块是否启用
        mapping(address => bool) modulesEnabled;
        // 存储所有已启用模块的模块地址
        address[] modulesList;
        // 记录「模块地址」在modulesList中的「索引+1」，为了和索引0（不存在）做区分
        mapping(address => uint256) modulesIndexPlusOne;
    }

    /// @notice 模块启用事件
    event ModuleEnabled(address indexed module);
    
    /// @notice 模块禁用事件
    event ModuleDisabled(address indexed module);

    /**
     * @notice 获取模块存储位置
     * @param position 存储槽位置
     * @return storagePtr 模块存储结构
     */
    function moduleStorage(bytes32 position) internal pure returns (ModuleStorage storage storagePtr) {
        assembly {
            storagePtr.slot := position
        }
    }

    /**
     * @notice 检查模块是否已启用
     * @param storagePtr 模块存储指针
     * @param module 模块地址
     * @return 是否已启用
     */
    function isModuleEnabled(ModuleStorage storage storagePtr, address module) internal view returns (bool) {
        return storagePtr.modulesEnabled[module];
    }

    /**
     * @notice 获取所有已启用的模块列表
     * @param storagePtr 模块存储指针
     * @return 模块地址数组
     */
    function getModules(ModuleStorage storage storagePtr) internal view returns (address[] memory) {
        return storagePtr.modulesList;
    }

    /**
     * @notice 获取模块在列表中的索引（从1开始，0表示不存在）
     * @param storagePtr 模块存储指针
     * @param module 模块地址
     * @return 索引+1，0表示不存在
     */
    function getModuleIndex(ModuleStorage storage storagePtr, address module) internal view returns (uint256) {
        return storagePtr.modulesIndexPlusOne[module];
    }

    /**
     * @notice 启用模块
     * @param storagePtr 模块存储指针
     * @param module 模块地址
     */
    function enableModule(ModuleStorage storage storagePtr, address module) internal {
        if (module == address(0)) {
            revert Errors.ModuleCannotBeZero();
        }
        
        if (storagePtr.modulesEnabled[module]) {
            return; // 幂等性：已启用则直接返回
        }
        
        storagePtr.modulesEnabled[module] = true;
        storagePtr.modulesList.push(module);
        storagePtr.modulesIndexPlusOne[module] = storagePtr.modulesList.length;
        
        emit ModuleEnabled(module);
    }

    /**
     * @notice 禁用模块
     * @param storagePtr 模块存储指针
     * @param module 模块地址
     */
    function disableModule(ModuleStorage storage storagePtr, address module) internal {
        if (module == address(0)) {
            revert Errors.ModuleCannotBeZero();
        }
        
        if (!storagePtr.modulesEnabled[module]) {
            return; // 幂等性：未启用则直接返回
        }
        
        storagePtr.modulesEnabled[module] = false;
        
        // 从模块列表中删除
        uint256 idxPlusOne = storagePtr.modulesIndexPlusOne[module];
        if (idxPlusOne != 0) {
            uint256 idx = idxPlusOne - 1;
            uint256 lastIdx = storagePtr.modulesList.length - 1;
            
            if (idx != lastIdx) {
                // 将最后一个元素移到当前位置
                address last = storagePtr.modulesList[lastIdx];
                storagePtr.modulesList[idx] = last;
                storagePtr.modulesIndexPlusOne[last] = idx + 1;
            }
            
            storagePtr.modulesList.pop();
            // 标记不在列表中
            storagePtr.modulesIndexPlusOne[module] = 0;
            
            emit ModuleDisabled(module);
        }
    }
}

