/* eslint-disable */
const {ethers} = require('hardhat');

// is Testnet or Mainnet Deploy
const isTestnet = true

// Contracts
let Token;

// Ownership
const newOwner = "0xA753d39dB9713caf8D7C4dDEDcD670f65D28707A";

// Values
const ONE = "1000000000000000000";
const ONE_HUNDRED = "100000000000000000000";
const ONE_HUNDRED_THOUSAND = "100000000000000000000000";
const ONE_MILLION = "1000000000000000000000000";

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

  const Deployed = await Contract.deploy(...args, {nonce: getNonce()});
  console.log(name, ': ', Deployed.address);
  await sleep(5000);

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

    console.log('Deploying on', isTestnet ? 'Testnet!' : 'Mainnet!');
    await sleep(1000);

    const tokenArgs = [
        "Test Token",
        "TEST",
        18,
        ONE_MILLION
    ];

    // Fetch Governance Manager
    Token = await deployContract('Token', 'contracts/Token.sol:Token', tokenArgs);

    await Token.changeOwner(newOwner, { nonce: getNonce() });
    await sleep(2000);
    console.log('Changed Owner');

    // Verify Contracts
    await verify(Token.address, tokenArgs);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
