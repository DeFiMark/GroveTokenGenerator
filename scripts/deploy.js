/* eslint-disable */
const {ethers} = require('hardhat');

// Contracts
let BaseToken;
let CustomToken;
let RewardToken;

let FeeReceiver;

let DistributorGenerator;
let TaxReceiverGenerator;
let TokenGenerator;

let Distributor;

// Ownership
// const newOwner = "0xA753d39dB9713caf8D7C4dDEDcD670f65D28707A";

// Values
const ONE_HUNDREDTH        = "10000000000000000";
const POINT_ONE            = "100000000000000000";
const ONE                  = "1000000000000000000";
const ONE_HALF             = "500000000000000000";
const ONE_HUNDRED          = "100000000000000000000";
const ONE_HUNDRED_THOUSAND = "100000000000000000000000";
const ONE_MILLION          = "1000000000000000000000000";

// Cost of Deploying
const BASE_TOKEN_COST   = "1000000000000000000";    // 1 Native Asset
const CUSTOM_TOKEN_COST = "2000000000000000000";    // 2 Native Asset
const REWARD_TOKEN_COST = "3000000000000000000";    // 3 Native Asset

const minGas = ethers.utils.parseUnits("3", "gwei")

async function verify(address, args) {
  try {
    // verify the token contract code
    await hre.run('verify:verify', {
      address: address,
      constructorArguments: args,
    });
  } catch (e) {
    console.log('error verifying contract', e);
  }
  await sleep(1000);
}

function getNonce() {
  return baseNonce + nonceOffset++;
}

async function deployContract(name = 'Contract', path, args) {
  const Contract = await ethers.getContractFactory(path);

  const Deployed = await Contract.deploy(...args, {nonce: getNonce(), gasPrice: minGas });
  console.log(name, ': ', Deployed.address);
  await sleep(6000);

  return Deployed;
}

async function fetchContract(path, address) {
    // Fetch Deployed Factory
    const Contract = await ethers.getContractAt(path, address);
    console.log('Fetched Contract: ', Contract.address, '\nVerify Against: ', address, '\n');
    await sleep(3000);
    return Contract;
}

async function sleep(ms) {
  return new Promise(resolve => {
    setTimeout(() => {
      return resolve();
    }, ms);
  });
}

async function main() {
    console.log('Starting Deploy');

    // addresses
    [owner] = await ethers.getSigners();

    // fetch data on deployer
    console.log('Deploying contracts with the account:', owner.address);
    console.log('Account balance:', (await owner.getBalance()).toString());

    // manage nonce
    baseNonce = await ethers.provider.getTransactionCount(owner.address);
    nonceOffset = 0;
    console.log('Account nonce: ', baseNonce);

    const newOwner = "0x319428B799cE4e286e74767719523F275b911F1e";

    await sleep(1000);

    // Deploy Implementation Contracts
    BaseToken = await deployContract('BaseToken Implementation', 'contracts/Tokens/BaseToken.sol:BaseToken', []);
    CustomToken = await deployContract('CustomToken Implementation', 'contracts/Tokens/CustomToken.sol:CustomToken', []);
    RewardToken = await deployContract('RewardToken Implementation', 'contracts/Tokens/RewardToken.sol:RewardToken', []);
    FeeReceiver = await deployContract('FeeReceiver Implementation', 'contracts/TaxReceivers/FeeReceiver.sol:FeeReceiver', []);
    Distributor = await deployContract('Distributor Implementation', 'contracts/Distributors/Distributor.sol:Distributor', []);

    // Deploy Generators
    DistributorGenerator = await deployContract('Distributor Generator', 'contracts/Generators/DistributorGenerator.sol:DistributorGenerator', [Distributor.address]);
    TaxReceiverGenerator = await deployContract('TaxReceiver Generator', 'contracts/Generators/TaxReceiverGenerator.sol:TaxReceiverGenerator', [FeeReceiver.address]);
    TokenGenerator = await deployContract('Token Generator', 'contracts/Generators/TokenGenerator.sol:TokenGenerator', [newOwner]);

    // Set up base tokens inside of token generator
    await TokenGenerator.setTokenType(0, BaseToken.address, BASE_TOKEN_COST, { nonce: getNonce(), gasPrice: minGas });
    console.log('Set Token Type 0');
    await sleep(5000);
    await TokenGenerator.setTokenTypeAndExternalGenerators(1, CustomToken.address, CUSTOM_TOKEN_COST, [TaxReceiverGenerator.address], { nonce: getNonce(), gasPrice: minGas });
    console.log('Set Token Type 1');
    await sleep(5000);
    await TokenGenerator.setTokenTypeAndExternalGenerators(2, RewardToken.address, REWARD_TOKEN_COST, [TaxReceiverGenerator.address, DistributorGenerator.address], { nonce: getNonce(), gasPrice: minGas });
    console.log('Set Token Type 2');
    await sleep(5000);

    // change owner
    await TokenGenerator.changeOwner(newOwner, { nonce: getNonce(), gasPrice: minGas });
    console.log('Set New Owner In Token Generator');
    await sleep(5000);

    await DistributorGenerator.changeOwner(newOwner, { nonce: getNonce(), gasPrice: minGas });
    console.log('Set New Owner In Distributor Generator');
    await sleep(5000);

    await TaxReceiverGenerator.changeOwner(newOwner, { nonce: getNonce(), gasPrice: minGas });
    console.log('Set New Owner In Distributor Generator');
    await sleep(5000);

    // Verify Contracts
    await verify(BaseToken.address, []);
    await verify(CustomToken.address, []);
    await verify(RewardToken.address, []);
    await verify(FeeReceiver.address, []);
    await verify(Distributor.address, []);
    await verify(DistributorGenerator.address, [Distributor.address]);
    await verify(TaxReceiverGenerator.address, [FeeReceiver.address]);
    await verify(TokenGenerator.address, [owner.address]);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
