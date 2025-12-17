// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "../utils/Errors.sol";
import "./modules/ModuleManager.sol";

contract SentinelWallet {
    using ECDSA for bytes32;
    using ModuleManager for ModuleManager.ModuleStorage;

    // 模块存储槽位置（使用 keccak256 确保唯一性）
    bytes32 private constant MODULE_STORAGE_POSITION = keccak256("sentinel.wallet.modules");

    address public owner;
    uint256 public nonce;

    event ExecFromModule(address module, address to, uint256 value, bytes data);
    event Executed(address indexed to, uint256 value, bytes data, address indexed signer);
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);

    constructor(address _owner){
        if (_owner == address(0)) {
            revert Errors.OwnerCannotBeZero();
        }
        owner = _owner;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert Errors.NotOwner();
        }
        _;
    }

    /**
     * @notice 获取模块存储
     * @return 模块存储结构
     */
    function _moduleStorage() private pure returns (ModuleManager.ModuleStorage storage) {
        return ModuleManager.moduleStorage(MODULE_STORAGE_POSITION);
    }

    /// 限制仅模块可调用
    modifier onlyModule(){
        if (!_moduleStorage().isModuleEnabled(msg.sender)) {
            revert Errors.NotEnabledModule();
        }
        _;
    }

    /// 模块是否启用
    function isModuleEnabled(address module) external view returns (bool) {
        return _moduleStorage().isModuleEnabled(module);
    } 

    /// 返回模块列表
    function getModules() external view returns(address[] memory) {
        return _moduleStorage().getModules();
    }

    /// 获取模块索引（公开接口，保持向后兼容）
    function modulesIndexPlusOne(address module) external view returns (uint256) {
        return _moduleStorage().getModuleIndex(module);
    }

    /// 启用模块
    function enableModule(address module) external onlyOwner {
        _moduleStorage().enableModule(module);
    }

    /// 禁用模块
    function disableModule(address module) external onlyOwner {
        _moduleStorage().disableModule(module);
    }

    /// 1、所有者调用executed → 校验权限 → 递增 nonce → 调用目标地址
    function executed(address to, uint256 value, bytes calldata data) external onlyOwner returns(bytes memory result){
        return _executeWithNonce(to, value, data);
    }


    // 2、第三方签名调用 → 验证签名 → 递增 nonce → 调用目标地址
    function executeWithSignature(
        address to, uint256 value, bytes calldata data, bytes calldata signature
    ) external returns (bytes memory){
        bytes32 hash = _buildHash(to,value,data,nonce, block.chainid);
        address signer = MessageHashUtils.toEthSignedMessageHash(hash).recover(signature);
        if (signer != owner) {
            revert Errors.InvalidSignature();
        }

        nonce+=1;

        bytes memory res = _callTarget(to,value,data);

        emit Executed(to,value,data,signer);
        return res;
    }

    /// 3、模块调用，模块必须先被owner启用
    function execFromModule(address to, uint256 value, bytes calldata data) external onlyModule returns(bytes memory){
        nonce += 1;
        bytes memory res = _callTarget(to,value,data);
        emit ExecFromModule(msg.sender, to, value, data);
        return res;
    }

    // owner直接修改owner
    function changeOwner(address newOwner) external onlyOwner{
        if (newOwner == address(0)) {
            revert Errors.OwnerCannotBeZero();
        }
        emit OwnerChanged(owner, newOwner);
        owner = newOwner;
    }

    // 模块修改owner
    function changeOwnerByModule(address newOwner) external onlyModule{
        if (newOwner == address(0)) {
            revert Errors.OwnerCannotBeZero();
        }
        emit OwnerChanged(owner, newOwner);
        owner = newOwner;
    }

    function _executeWithNonce(address to, uint256 value, bytes calldata data) internal returns(bytes memory){
        nonce += 1;
        bytes memory res = _callTarget(to,value,data);
        emit Executed(to, value, data, msg.sender);
        return res;
    }

    function _callTarget(address to, uint256 value, bytes calldata data) internal returns (bytes memory){
        (bool ok, bytes memory ret) = to.call{value: value}(data);
        if (!ok) {
            revert Errors.CallFailed();
        }
        return ret;
    }

    function _buildHash(address to,  uint256 value, bytes calldata data, uint256 _nonce, uint256 _chainId) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(address(this), to, value, keccak256(data), _nonce, _chainId));
    }

    receive() external payable {}
    fallback() external payable {}
}