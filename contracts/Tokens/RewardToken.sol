//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./CustomToken.sol";
import "./IDistributor.sol";

contract RewardToken is CustomToken {

    // distributor
    IDistributor public distributor;

    constructor() CustomToken() {}

    function __init__(bytes calldata payload) external override {
        super.__init__(payload);
    }

    function pairExternalContracts(address[] calldata assets) external override {
        require(msg.sender == factory, 'Not Factory');
        require(feeReceiver == address(0) && address(distributor) == address(0), 'Already Paired');
        require(assets.length == 2, 'Invalid Length');
        require(assets[0] != address(0) && assets[1] != address(0), 'Zero Address');

        // set receiver
        feeReceiver = assets[0];
        distributor = IDistributor(assets[1]);

        // set share of owner
        distributor.setShare(_owner, _balances[_owner]);
        distributor.setRewardExempt(address(this), true);
        distributor.setRewardExempt(feeReceiver, true);
    }

    function setFeeRecipient(address recipient) external override onlyOwner {
        super.setFeeRecipient(recipient);
        distributor.setRewardExempt(feeReceiver, true);
    }

    function _transferFrom(address sender, address recipient, uint256 amount) internal override {
        super._transferFrom(sender, recipient, amount);
        if (address(distributor) != address(0)) {
            distributor.setShare(sender, _balances[sender]);
            distributor.setShare(recipient, _balances[recipient]);
            distributor.process();
        }
    }

    function setDistributor(address distributor_) external onlyOwner {
        require(distributor_ != address(0), 'Zero Address');
        distributor = IDistributor(distributor_);
        permissions[distributor_].isFeeExempt = true;
    }

    

}