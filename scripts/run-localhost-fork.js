const hre = require('hardhat');
const { TASK_NODE_CREATE_SERVER } = require('hardhat/builtin-tasks/task-names');
// const Compound = require('@compound-finance/compound-js');
const jsonRpcUrl = 'http://localhost:8545';

(async function () {
  console.log(`\nRunning a hardhat localhost fork of mainnet at ${jsonRpcUrl}\n`);

  const jsonRpcServer = await hre.run(TASK_NODE_CREATE_SERVER, {
    hostname: 'localhost',
    port: 8545,
    provider: hre.network.provider,
  });

  await jsonRpcServer.listen();
})().catch(console.error)
