//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../lib/Ownable.sol";
import "../lib/TransferHelper.sol";
import "../interfaces/IBaseToken.sol";
import "../interfaces/ICustomToken.sol";
import "../interfaces/IExternalGenerator.sol";

contract TokenGenerator is Ownable {

    // User Info
    struct UserInfo {
        uint256 discountPercentage;
        address[] tokensGenerated;
    }

    // Maps user to info related to user
    mapping ( address => UserInfo ) private userInfo;

    // List of all tokens generated
    address[] public allTokens;

    // Payment Token
    address public paymentToken;

    // Payment Recipient
    address public paymentRecipient;

    // Implementation Struct for TokenType
    struct TokenType {
        address implementation;
        uint256 cost;
        address[] externalGenerators;
    }

    // Maps a tokenType to an implementation address and cost
    mapping ( uint16 => TokenType ) public tokenTypes;

    // Maps a token to its specific generated assets
    mapping ( address => address[] ) private generatedAssetsForToken;

    // Events
    event TokenCreated(address tokenAddress, uint16 tokenType);

    function setDiscountPercentage(address user, uint256 discountPercentage) external onlyOwner {
        userInfo[user].discountPercentage = discountPercentage;
    }

    function setTokenType(uint16 tokenType, address implementation, uint256 cost) external onlyOwner {
        tokenTypes[tokenType].implementation = implementation;
        tokenTypes[tokenType].cost = cost;
        tokenTypes[tokenType].externalGenerators = new address[](0);
    }

    function setExternalGenerators(uint16 tokenType, address[] calldata generators) external onlyOwner {
        tokenTypes[tokenType].externalGenerators = generators;
    }

    function setTokenTypeAndExternalGenerators(uint16 tokenType, address implementation, uint256 cost, address[] calldata generators) external onlyOwner {
        tokenTypes[tokenType].implementation = implementation;
        tokenTypes[tokenType].cost = cost;
        tokenTypes[tokenType].externalGenerators = generators;
    }

    function setCost(uint16 tokenType, uint256 cost) external onlyOwner {
        tokenTypes[tokenType].cost = cost;
    }

    function setImplementation(uint16 tokenType, address implementation) external onlyOwner {
        tokenTypes[tokenType].implementation = implementation;
    }

    function setPaymentToken(address token) external onlyOwner {
        paymentToken = token;
    }

    function setPaymentRecipient(address recipient) external onlyOwner {
        paymentRecipient = recipient;
    }

    function ownerGenerate(bytes calldata initPayload, bytes calldata extraPayload, uint16 tokenType, bytes[] calldata generatedAssetPayloads) external onlyOwner {
        _generate(initPayload, extraPayload, tokenType, generatedAssetPayloads);
    }

    function generate(bytes calldata initPayload, bytes calldata extraPayload, uint16 tokenType, bytes[] calldata generatedAssetPayloads) external {
        // handle payment
        _handlePayment(msg.sender, tokenType);

        // generate
        _generate(initPayload, extraPayload, tokenType, generatedAssetPayloads);
    }

    function _generate(bytes calldata initPayload, bytes calldata extraPayload, uint16 tokenType, bytes[] calldata generatedAssetPayloads) internal {
        require(tokenTypes[tokenType].implementation != address(0), "Invalid Token Type");
        
        // clone asset based on desired implementation
        address newAsset = IBaseToken(tokenTypes[tokenType].implementation).clone();
        emit TokenCreated(newAsset, tokenType);

        // determine if this token has external generators, to know whether its custom or basic
        uint len = tokenTypes[tokenType].externalGenerators.length;

        if (len > 0) {
            // custom token creation

            // initialize token with basic initialization
            ICustomToken(newAsset).__init__(initPayload);

            // initialize token with extra data
            ICustomToken(newAsset).__extra_init__(extraPayload);

            // loop through external generators, generating necessary assets
            address[] memory generatedAssets = new address[](len);
            for (uint i = 0; i < len;) {
                generatedAssets[i] = IExternalGenerator(tokenTypes[tokenType].externalGenerators[i]).generate(newAsset, generatedAssetPayloads[i]);
                unchecked { ++i; }
            }

            // add to mapping
            generatedAssetsForToken[newAsset] = generatedAssets;

            // pair external contracts with the token
            ICustomToken(newAsset).pairExternalContracts(generatedAssets);

        } else {
            
            // initialize token, acts as constructor
            IBaseToken(newAsset).__init__(initPayload);

            // set empty mapping
            generatedAssetsForToken[newAsset] = new address[](0);
        }

        // add to list of tokens
        allTokens.push(newAsset);
        userInfo[msg.sender].tokensGenerated.push(newAsset);
    }

    function _handlePayment(address user, uint16 tokenType) internal {
        uint256 cost = tokenTypes[tokenType].cost;
        if (cost > 0) {
            uint256 discount = (cost * userInfo[user].discountPercentage) / 100;
            uint256 finalCost = cost - discount;
            _transferIn(finalCost);
        }
    }

    function _transferIn(uint256 amount) internal {
        require(
            IERC20(paymentToken).balanceOf(msg.sender) >= amount,
            "Insufficient Balance"
        );
        require(
            IERC20(paymentToken).allowance(msg.sender, address(this)) >= amount,
            "Insufficient Allowance"
        );
        TransferHelper.safeTransferFrom(paymentToken, msg.sender, paymentRecipient, amount);
    }

    function getDiscountForUser(address user) external view returns (uint256) {
        return userInfo[user].discountPercentage;
    }

    function getTokensGeneratedForUser(address user) external view returns (address[] memory) {
        return userInfo[user].tokensGenerated;
    }

    function getAllGeneratedTokens() external view returns (address[] memory) {
        return allTokens;
    }

    function paginateAllGeneratedTokens(uint256 start, uint256 end) external view returns (address[] memory) {
        if (end > allTokens.length) {
            end = allTokens.length;
        }
        address[] memory result = new address[](end - start);
        for (uint i = start; i < end; i++) {
            result[i - start] = allTokens[i];
        }
        return result;
    }

    function getGeneratedAssetsForToken(address token) external view returns (address[] memory) {
        return generatedAssetsForToken[token];
    }
}