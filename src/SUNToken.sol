// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Fixed-supply Sunflower Garden token. The launch factory distributes the supply.
/// @dev Any transfer out of PoolManager is taxed, including withdrawals, not just swaps.
///      Transfers into PoolManager take precedence and are always untaxed.
contract SUNToken {
    string public constant name = "Sunflower Garden";
    string public constant symbol = "SUN";
    uint8 public constant decimals = 18;
    uint256 public constant totalSupply = 1_000_000_000 * 10 ** 18;
    uint256 public constant CREATOR_TAX_BPS = 50;
    uint256 public constant BPS_DENOMINATOR = 10_000;
    address public constant POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address public constant CREATOR_WALLET = 0xEeaF04a41aC45A605E30dc6a41A44E6F75Ddf8b6;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    error ERC20InvalidSender(address sender);
    error ERC20InvalidReceiver(address receiver);
    error ERC20InvalidSpender(address spender);
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor() {
        balanceOf[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);
    }

    function approve(address spender, uint256 value) external returns (bool) {
        if (spender == address(0)) revert ERC20InvalidSpender(spender);
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 approved = allowance[from][msg.sender];
        if (approved != type(uint256).max) {
            if (approved < value) revert ERC20InsufficientAllowance(msg.sender, approved, value);
            unchecked {
                allowance[from][msg.sender] = approved - value;
            }
        }
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) private {
        if (from == address(0)) revert ERC20InvalidSender(from);
        if (to == address(0)) revert ERC20InvalidReceiver(to);
        uint256 available = balanceOf[from];
        if (available < value) revert ERC20InsufficientBalance(from, available, value);

        // Validate the full debit before arithmetic. It cannot exceed the fixed supply.
        uint256 tax = from == POOL_MANAGER && to != POOL_MANAGER ? (value * CREATOR_TAX_BPS) / BPS_DENOMINATOR : 0;
        unchecked {
            balanceOf[from] = available - value;
        }
        if (tax != 0) {
            balanceOf[CREATOR_WALLET] += tax;
            emit Transfer(from, CREATOR_WALLET, tax);
        }
        balanceOf[to] += value - tax;
        emit Transfer(from, to, value - tax);
    }
}
