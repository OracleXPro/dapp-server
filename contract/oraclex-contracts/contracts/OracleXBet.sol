// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// 引入控制台库（用于调试）
// import "hardhat/console.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import {LibDiamond} from "./diamond-2/contracts/libraries/LibDiamond.sol";
import "@fhenixprotocol/contracts/FHE.sol";

// 定义 OracleXBet 合约，继承自 Context
contract OracleXBet is Context {
    using SafeERC20 for IERC20;

    address public owner;

    constructor() {
        owner = msg.sender;
    }

    // Fhenix
    euint32 private counter;
    // Fhenix 加密
    function EncryptedValue(uint32 plaintextValue) public {
        counter = FHE.asEuint32(plaintextValue);
    }
    // Fhenix 解密
    function getCounter() public view returns (uint256) {
        return FHE.decrypt(counter);
    }

    // 定义存储位置的哈希常量，用于标识合约的存储位置
    bytes32 private constant STORAGE_POSITION =
        keccak256("OracleX.bet.storage");

    // 定义 OracleXStorage 结构体，包含多个映射和存储数据
    struct OracleXStorage {
        IERC20 quote; // 引用的 ERC20 代币
        uint256 groupPos; // 当前组的位置
        mapping(uint256 => uint256) groupUnitPos; // 每个组的单元位置映射
        mapping(uint256 => mapping(uint256 => uint256)) groupUnitActionPos; // 每个组的单元动作位置映射
        mapping(uint256 => OracleXGroup) groups; // 每个组的映射
        mapping(uint256 => mapping(uint256 => OracleXUnit)) groupUnits; // 每个组的单元映射
        mapping(uint256 => mapping(uint256 => mapping(uint256 => OracleXAction))) groupUnitActions; // 每个单元的动作映射
    }

    // 定义 OracleXGroup 结构体，表示一个组的属性
    struct OracleXGroup {
        string title; // 组的标题
        uint256 startAt; // 组的开始时间
        uint256 endAt; // 组的结束时间
    }

    // 定义 OracleXUnit 结构体，表示一个单元的属性
    struct OracleXUnit {
        string title; // 单元的标题
        uint256 yesAmount; // 投注 "Yes" 的金额总和
        uint256 noAmount; // 投注 "No" 的金额总和
    }

    // 定义 OracleXAction 结构体，表示一个动作的属性
    struct OracleXAction {
        uint64 group; // 所属的组
        uint64 unit; // 所属的单元
        uint128 amount; // 投注金额
        address user; // 用户地址
        bool yesOrNo; // 是否投注 "Yes"
        bool isFinished; // 动作是否已完成
    }

    // 定义 BuyAction 结构体，用于表示购买操作的参数
    struct BuyAction {
        bool yesOrNo; // 是否投注 "Yes"
        uint256 amount; // 投注金额
        uint256 group; // 所属的组
        uint256 unit; // 所属的单元
    }

    // 定义 SellAction 结构体，用于表示出售操作的参数
    struct SellAction {
        uint256 amount; // 出售金额
        uint256 group; // 所属的组
        uint256 unit; // 所属的单元
        uint256 action; // 动作编号
    }

    // 定义修饰符，限制仅合约拥有者可以调用的函数
    modifier onlyOwner() {
        // if (LibDiamond.contractOwner() != _msgSender()) {
        if (owner != _msgSender()) {
            revert OwnableUnauthorizedAccount(_msgSender()); // 如果不是拥有者，抛出错误
        }
        _;
    }

    // 获取合约拥有者的地址
    function getOwnerAddress() public view virtual returns (address) {
        return owner;
    }

    // 获取 OracleXStorage 结构体的存储位置
    function Storage() internal pure returns (OracleXStorage storage s) {
        bytes32 position = STORAGE_POSITION;
        assembly {
            s.slot := position // 使用汇编指令设置存储位置
        }
        return s;
    }

    // 购买操作
    function buy(BuyAction calldata b) external {
        OracleXStorage storage $ = Storage();
        OracleXGroup memory group = $.groups[b.group];
        require(
            group.startAt <= block.timestamp && block.timestamp < group.endAt,
            "OracleX: bet is not active"
        ); // 检查是否在允许的投注时间范围内

        OracleXUnit storage unit = $.groupUnits[b.group][b.unit];
        if (b.yesOrNo) {
            unit.yesAmount += b.amount; // 如果选择 "Yes"，增加对应的金额
        } else {
            unit.noAmount += b.amount; // 如果选择 "No"，增加对应的金额
        }

        OracleXAction memory newAction = OracleXAction({
            user: _msgSender(),
            yesOrNo: b.yesOrNo,
            isFinished: false,
            amount: uint128(b.amount),
            group: uint64(b.group),
            unit: uint64(b.unit)
        });

        uint256 actionPos = $.groupUnitActionPos[b.group][b.unit];
        $.groupUnitActions[b.group][b.unit][actionPos] = newAction; // 存储新创建的动作
        $.groupUnitActionPos[b.group][b.unit]++;

        $.quote.safeTransferFrom(_msgSender(), address(this), b.amount); // 从用户账户中安全转移资金

        emit Buy(_msgSender(), b.group, b.unit, actionPos, b.amount, b.yesOrNo); // 触发购买事件
    }

    // 出售操作
    function sell(SellAction calldata s) external {
        OracleXStorage storage $ = Storage();
        OracleXGroup memory group = $.groups[s.group];
        require(
            group.startAt <= block.timestamp && block.timestamp < group.endAt,
            "OracleX: bet is not active"
        ); // 检查是否在允许的出售时间范围内

        OracleXAction storage action = $.groupUnitActions[s.group][s.unit][
            s.action
        ];
        require(action.user == _msgSender(), "OracleX: not your action"); // 确保操作是由动作的拥有者进行的
        require(!action.isFinished, "OracleX: bet is already finished"); // 确保动作未完成
        require(action.amount > s.amount, "OracleX: not enough amount to sell"); // 确保有足够的金额可以出售

        unchecked {
            action.amount -= uint128(s.amount); // 减少动作中的金额
        }

        OracleXUnit storage unit = $.groupUnits[s.group][s.unit];
        if (action.yesOrNo) {
            unchecked {
                unit.yesAmount -= s.amount; // 如果是 "Yes"，减少对应金额
            }
        } else {
            unchecked {
                unit.noAmount -= s.amount; // 如果是 "No"，减少对应金额
            }
        }

        $.quote.safeTransfer(_msgSender(), action.amount); // 安全转移剩余金额给用户

        emit Sell(_msgSender(), s.group, s.unit, s.action, s.amount); // 触发出售事件
    }

    // 创建一个新的组
    function createGroup(
        string calldata title,
        uint256 startAt,
        uint256 endAt
    ) public onlyOwner {
        OracleXStorage storage $ = Storage();
        OracleXGroup memory newGroup = OracleXGroup({
            title: title,
            startAt: startAt,
            endAt: endAt
        });

        emit CreateGroup(title, startAt, endAt); // 触发创建组事件

        $.groups[$.groupPos] = newGroup; // 存储新的组
        $.groupPos++;
    }

    // 创建一个新的单元
    function createUnit(uint256 group, string calldata title) public onlyOwner {
        OracleXStorage storage $ = Storage();
        OracleXUnit memory newUnit = OracleXUnit({
            title: title,
            yesAmount: 0,
            noAmount: 0
        });

        uint256 groupUnitPos = $.groupUnitPos[group];
        $.groupUnits[group][groupUnitPos] = newUnit; // 存储新的单元
        $.groupUnitPos[group]++;

        emit CreateUnit(group, groupUnitPos, title); // 触发创建单元事件
    }

    // 清算操作，根据不同的清算类型计算奖励并转移资金
    function liquidate(
        uint256 group,
        uint256 unit,
        uint256 from,
        uint256 to,
        uint256 liquidateType
    ) public onlyOwner {
        OracleXStorage storage $ = Storage();
        OracleXUnit storage unitData = $.groupUnits[group][unit];

        uint256 reward;
        for (uint256 i = from; i < to; i++) {
            OracleXAction storage a = $.groupUnitActions[group][unit][i];
            if (!a.isFinished) {
                a.isFinished = true;
                // 根据清算类型计算奖励
                if (liquidateType == 0) {
                    if (!a.yesOrNo) {
                        reward =
                            a.amount +
                            (a.amount * unitData.yesAmount) /
                            unitData.noAmount;
                    }
                } else if (liquidateType == 1) {
                    if (a.yesOrNo) {
                        reward =
                            a.amount +
                            (a.amount * unitData.noAmount) /
                            unitData.yesAmount;
                    }
                } else {
                    reward = a.amount;
                }
                if (reward > 0) {
                    $.quote.safeTransfer(a.user, reward); // 转移奖励资金
                }

                emit Liquidate(a.user, group, unit, i, reward, liquidateType); // 触发清算事件

                reward = 0; // 重置奖励金额
            }
        }
    }

    // 定义错误，表示没有权限的账户尝试操作
    error OwnableUnauthorizedAccount(address account);

    // 事件定义：购买操作
    event Buy(
        address indexed user,
        uint256 group,
        uint256 unit,
        uint256 action,
        uint256 amount,
        bool yesOrNo
    );
    // 事件定义：出售操作
    event Sell(
        address indexed user,
        uint256 group,
        uint256 unit,
        uint256 action,
        uint256 amount
    );
    // 事件定义：创建组
    event CreateGroup(string title, uint256 startAt, uint256 endAt);
    // 事件定义：创建单元
    event CreateUnit(uint256 group, uint256 unit, string title);
    // 事件定义：清算操作
    event Liquidate(
        address indexed user,
        uint256 group,
        uint256 unit,
        uint256 action,
        uint256 amount,
        uint256 liquidateType
    );
}
