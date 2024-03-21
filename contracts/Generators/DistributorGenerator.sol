//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../lib/Ownable.sol";
import "../interfaces/IExternalGenerator.sol";
import "../interfaces/IImplementation.sol";
import "../lib/Cloneable.sol";

contract DistributorGenerator is Ownable, IExternalGenerator {

    address public implementation;
    event CreatedDistributor(address distributor, address indexed token);

    constructor(address _implementation) {
        implementation = _implementation;
    }
    
    function setImplementation(address _implementation) external onlyOwner {
        implementation = _implementation;
    }

    function generate(address token, bytes calldata payload) external override returns (address) {
        
        // clone implementation
        address distributor = Cloneable(implementation).clone();
        
        // decode payload to attach token to it
        (
            address router,
            address rewardToken,
            uint256 minDistribution
        ) = abi.decode(payload, (address, address, uint256));

        // encode new payload to include token
        bytes memory newPayload = abi.encode(token, router, rewardToken, minDistribution);

        // initialize distributor
        IImplementation(distributor).__init__(newPayload);
        emit CreatedDistributor(distributor, token);

        // return new address
        return distributor;
    }
}