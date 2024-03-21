//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./ICustomToken.sol";

contract CustomTokenData {

    // total supply
    uint256 internal _totalSupply;

    // token data
    string internal _name;
    string internal _symbol;
    uint8  internal _decimals;

    // mintable
    bool internal _mintable;
    bool internal _burnable;

    // Fees
    uint256 public buyFee;
    uint256 public sellFee;
    uint256 public transferFee;
    uint256 public constant TAX_DENOM = 10000;

    // Fee Receiver
    address public feeReceiver;

    // Whether trading is paused or not
    bool public paused;

    // Owner
    address public owner;
    address internal factory;

    // balances
    mapping (address => uint256) internal _balances;
    mapping (address => mapping (address => uint256)) internal _allowances;

    // Maximum Sell Limit
    uint256 public max_sell_limit;
    uint256 public max_sell_limit_duration;

    // Sell Limit Enabled
    bool public sellLimitEnabled;

    // Max Sell Limit Info
    struct UserInfo {
        uint256 totalSold;
        uint256 hourStarted;
        uint256 timeJoined;
    }

    // Address => Max Sell Limit Info
    mapping ( address => UserInfo ) public userInfo;

    // permissions
    struct Permissions {
        bool isFeeExempt;
        bool isLiquidityPool;
        bool isSellLimitExempt;
        bool isBlacklisted;
    }
    mapping ( address => Permissions ) public permissions;

    modifier onlyOwner() {
        require(msg.sender == owner, 'Not Owner');
        _;
    }

    event SetFeeRecipient(address recipient);
    event SetAutomatedMarketMaker(address account, bool isAMM);
    event Blacklisted(address account, bool isBlacklisted);
    event SetFees(uint buyFee, uint sellFee, uint transferFee);
    event SetFeeExemption(address account, bool isExempt);
    event SetSellLimitExemption(address account, bool isExempt);
}


contract CustomToken is CustomTokenData, ICustomToken, Cloneable {

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
        require(owner != address(0), 'No Owner');

        // set factory for later calls
        factory = msg.sender;

        // allocate initial balance to be the total supply
        permissions[owner].isFeeExempt = true;
        _balances[owner] = _totalSupply;
        emit Transfer(address(0), owner, _totalSupply);        
    }

    function __extra_init__(bytes calldata payload) external override {
        require(msg.sender == factory, 'Only Factory');
        (
            buyFee,
            sellFee,
            transferFee
        ) = abi.decode(payload, (uint256, uint256, uint256));
    }

    function pairExternalContracts(address[] calldata assets) external override {
        require(msg.sender == factory, 'Not Factory');
        require(feeReceiver == address(0), 'Already Paired');
        require(assets.length == 1, 'Invalid Length');
        require(assets[0] != address(0), 'Zero Address');

        // set receiver
        feeReceiver = assets[0];
        permissions[feeReceiver].isFeeExempt = true;
        permissions[feeReceiver].isSellLimitExempt = true;
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



    function setSelllimitEnabled(bool _enabled) external onlyOwner {
        sellLimitEnabled = _enabled;
    }

    function withdraw(address token) external onlyOwner {
        require(token != address(0), 'Zero Address');
        bool s = IERC20(token).transfer(msg.sender, IERC20(token).balanceOf(address(this)));
        require(s, 'Failure On Token Withdraw');
    }

    function withdrawBNB() external onlyOwner {
        (bool s,) = payable(msg.sender).call{value: address(this).balance}("");
        require(s);
    }

    function setFeeRecipient(address recipient) external onlyOwner {
        require(recipient != address(0), 'Zero Address');
        feeReceiver = recipient;
        permissions[recipient].isFeeExempt = true;
        permissions[recipient].isSellLimitExempt = true;
        emit SetFeeRecipient(recipient);
    }

    function registerAutomatedMarketMaker(address account) external onlyOwner {
        require(account != address(0), 'Zero Address');
        require(!permissions[account].isLiquidityPool, 'Already An AMM');
        permissions[account].isLiquidityPool = true;
        emit SetAutomatedMarketMaker(account, true);
    }

    function unRegisterAutomatedMarketMaker(address account) external onlyOwner {
        require(account != address(0), 'Zero Address');
        require(permissions[account].isLiquidityPool, 'Not An AMM');
        permissions[account].isLiquidityPool = false;
        emit SetAutomatedMarketMaker(account, false);
    }

    function blackListAddress(address account) external onlyOwner {
        require(account != address(0), 'Zero Address');
        permissions[account].isBlacklisted = true;
        emit Blacklisted(account, true);
    }

    function removeBlackListFromAddress(address account) external onlyOwner {
        require(account != address(0), 'Zero Address');
        permissions[account].isBlacklisted = false;
        emit Blacklisted(account, false);
    }

    function pause() external onlyOwner {
        paused = true;
    }

    function unPause() external onlyOwner {
        paused = false;
    }

    function setFees(uint _buyFee, uint _sellFee, uint _transferFee) external onlyOwner {
        require(
            _buyFee <= 5000,
            'Buy Fee Too High'
        );
        require(
            _sellFee <= 5000,
            'Sell Fee Too High'
        );
        require(
            _transferFee <= 5000,
            'Transfer Fee Too High'
        );

        buyFee = _buyFee;
        sellFee = _sellFee;
        transferFee = _transferFee;

        emit SetFees(_buyFee, _sellFee, _transferFee);
    }

    function setFeeExempt(address account, bool isExempt) external onlyOwner {
        require(account != address(0), 'Zero Address');
        permissions[account].isFeeExempt = isExempt;
        emit SetFeeExemption(account, isExempt);
    }

    function setMaxSellLimitExempt(address account, bool isExempt) external onlyOwner {
        require(account != address(0), 'Zero Address');
        permissions[account].isSellLimitExempt = isExempt;
        emit SetSellLimitExemption(account, isExempt);
    }

    function setMaxSellLimit(uint256 newLimit) external onlyOwner {
        require(
            newLimit >= _totalSupply / 1_000_000,
            'Max Sell Limit Too Low'
        );
        max_sell_limit = newLimit;
    }

    function setMaxSellLimitDuration(uint256 newDuration) external onlyOwner {
        require(
            newDuration > 0,
            'Zero Duration'
        );
        max_sell_limit_duration = newDuration;
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
        require(
            paused == false || msg.sender == this.getOwner(),
            'Paused'
        );
        require(
            permissions[sender].isBlacklisted == false && permissions[recipient].isBlacklisted == false,
            'Blacklisted'
        );
        
        // decrement sender balance
        _balances[sender] -= amount;

        // fee for transaction
        (uint256 fee, uint8 TRANSFER_TYPE) = getTax(sender, recipient, amount);

        // give amount to recipient less fee
        uint256 sendAmount = amount - fee;
        require(sendAmount > 0, 'Zero Amount');

        // allocate balance
        _balances[recipient] += sendAmount;
        emit Transfer(sender, recipient, sendAmount);

        // allocate fee if any
        if (fee > 0) {

            // if recipient field is valid
            bool isValidRecipient = feeReceiver != address(0) && feeReceiver != address(this);

            // allocate amount to recipient
            address feeRecipient = isValidRecipient ? feeReceiver : address(this);

            // allocate fee
            _balances[feeRecipient] += fee;
            emit Transfer(sender, feeRecipient, fee);

            // if valid and trigger is enabled, trigger tokenomics mid transfer
            if (trigger && isValidRecipient) {
                (bool success,) = feeRecipient.call(
                    abi.encodeWithSelector(bytes4(keccak256(bytes('trigger(uint8)')))),
                    TRANSFER_TYPE
                );
                success;
            }
        }

        // apply max sell limit if applicable
        if (sellLimitEnabled && permissions[recipient].isLiquidityPool && !permissions[sender].isSellLimitExempt) {

            if (timeSinceLastSale(sender) >= max_sell_limit_duration) {

                // its been over the time duration, set total sold and reset timer
                userInfo[sender].totalSold = amount;
                userInfo[sender].hourStarted = block.timestamp;

            } else {
                
                // time limit has not been surpassed, increment total sold
                unchecked {
                    userInfo[sender].totalSold += amount;
                }

            }

            // ensure max limit is preserved
            require(
                userInfo[sender].totalSold <= max_sell_limit,
                'Sell Exceeds Max Sell Limit'
            );

        }

        return true;
    }

    function getTax(address sender, address recipient, uint256 amount) public view returns (uint256, uint8 TRANSFER_TYPE) {
        if ( permissions[sender].isFeeExempt || permissions[recipient].isFeeExempt ) {
            return (0, address(0), false);
        }
        return permissions[sender].isLiquidityPool ? 
               (amount.mul(buyFee).div(TAX_DENOM), 0) : 
               permissions[recipient].isLiquidityPool ? 
               (amount.mul(sellFee).div(TAX_DENOM), 1) :
               (amount.mul(transferFee).div(TAX_DENOM), 2);
    }

    receive() external payable {}

    /**
        @dev Deploys and returns the address of a clone of address(this
        Created by DeFi Mark To Allow Clone Contract To Easily Create Clones Of Itself
        Without redundancy
     */
    function clone() external override returns(address) {
        /// @solidity memory-safe-assembly
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(ptr, 0x14), shl(0x60, address(this)))
            mstore(add(ptr, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            instance := create(0, ptr, 0x37)
        }
        require(instance != address(0), "ERC1167: create failed");
    }

    function encodeInitArgs(
        string memory __name,
        string memory __symbol,
        uint8 __decimals,
        uint256 __totalSupply,
        address __initialRecipient
    ) external pure returns (bytes memory) {
        return abi.encode(__name, __symbol, __decimals, __totalSupply, __initialRecipient);
    }
}