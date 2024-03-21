//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../interfaces/IBaseToken.sol";

contract BaseTokenData {

    // total supply
    uint256 internal _totalSupply;

    // token data
    string internal _name;
    string internal _symbol;
    uint8  internal _decimals;

    // mintable
    bool internal _mintable;
    bool internal _burnable;

    // Owner
    address public owner;

    // balances
    mapping (address => uint256) internal _balances;
    mapping (address => mapping (address => uint256)) internal _allowances;

    modifier onlyOwner() {
        require(msg.sender == owner, 'Not Owner');
        _;
    }
}


contract BaseToken is BaseTokenData, IBaseToken {

    function __init__(bytes calldata payload) external {
        require(owner == address(0), 'Already Initialized');
        (
            _name,
            _symbol,
            _decimals,
            _totalSupply,
            _mintable,
            _burnable,
            owner
        ) = abi.decode(payload, (string, string, uint8, uint256, bool, bool, address));
        require(owner != address(0), 'Zero Owner');
        
        // allocate initial balance to be the total supply
        _balances[owner] = _totalSupply;
        emit Transfer(address(0), owner, _totalSupply);        
    }

    function totalSupply() external view override returns (uint256) { return _totalSupply; }
    function balanceOf(address account) public view override returns (uint256) { return _balances[account]; }
    function allowance(address holder, address spender) external view override returns (uint256) { return _allowances[holder][spender]; }
    
    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /** Transfer Function */
    function transfer(address recipient, uint256 amount) external override returns (bool) {
        return _transferFrom(msg.sender, recipient, amount);
    }

    /** Transfer Function */
    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        _allowances[sender][msg.sender] -= amount;
        return _transferFrom(sender, recipient, amount);
    }

    function setOwner(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    function disableMintable() external onlyOwner {
        require(_mintable, 'Not Mintable');
        _mintable = false;
    }
    
    function toggleBurnable() external onlyOwner {
        _burnable = !_burnable;
    }
    
    function mint(address to, uint256 qty) external onlyOwner {
        require(_mintable, 'Not Mintable');
        _totalSupply += qty;
        _balances[to] += qty;
        emit Transfer(address(0), to, qty);
    }

    function burn(uint256 qty) external {
        require(_burnable, 'Not Burnable');
        require(_balances[msg.sender] >= qty, 'Insufficient Balance');
        require(qty > 0, 'Zero Amount');
        _balances[msg.sender] -= qty;
        _totalSupply -= qty;
        emit Transfer(msg.sender, address(0), qty);
    }

    /** Internal Transfer */
    function _transferFrom(address sender, address recipient, uint256 amount) internal returns (bool) {
        require(
            recipient != address(0),
            'Zero Recipient'
        );
        require(
            amount > 0,
            'Zero Amount'
        );
        require(
            amount <= balanceOf(sender),
            'Insufficient Balance'
        );
        
        // decrement sender balance
        _balances[sender] -= amount;
        _balances[recipient] += amount;

        // emit transfer
        emit Transfer(sender, recipient, amount);
        return true;
    }

    receive() external payable {}

    /**
        @dev Deploys and returns the address of a clone of address(this
        Created by DeFi Mark To Allow Clone Contract To Easily Create Clones Of Itself
        Without redundancy
     */
    function clone() external override returns(address) {
        return _clone(address(this));
    }

    /**
     * @dev Deploys and returns the address of a clone that mimics the behaviour of `implementation`.
     *
     * This function uses the create opcode, which should never revert.
     */
    function _clone(address implementation) internal returns (address instance) {
        /// @solidity memory-safe-assembly
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(ptr, 0x14), shl(0x60, implementation))
            mstore(add(ptr, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            instance := create(0, ptr, 0x37)
        }
        require(instance != address(0), "ERC1167: create failed");
    }
}