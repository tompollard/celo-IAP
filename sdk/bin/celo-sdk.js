#!/usr/bin/env node
const exec = require('child_process').exec
const fs = require('fs')
const promisify = require('util').promisify
const path = require('path')
const storage = require('@google-cloud/storage')
const gcs = new storage.Storage(
  (config = {
    projectId: 'celo-testnet',
  })
)

// TODO(asa): Move this to a shared library
function execCmd(cmd) {
  return new Promise((resolve, reject) => {
    if (process.env.CELOTOOL_VERBOSE === 'true') console.debug('$ ' + cmd)
    // @ts-ignore
    exec(cmd, (err, stdout, stderr) => {
      if (process.env.CELOTOOL_VERBOSE === 'true') {
        console.debug(stdout)
        console.error(stderr)
      }
      if (err) reject(err)
      else resolve([stdout, stderr])
    })
  })
}

// TODO(asa): Use @google-cloud/storage, tar-stream to do all of this directly in node
async function downloadContractArtifacts(gcsBucket, environment, outputDir) {
  console.debug(
    `Downloading contract artifacts from ${gcsBucket} to ${outputDir} for environment ${environment}`
  )
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir)
  }

  await execCmd(
    `curl https://www.googleapis.com/storage/v1/b/contract_artifacts/o/${environment}?alt=media > ${environment}.tar.gz`
  )
  await execCmd(`tar -zxvf ${environment}.tar.gz --directory ${outputDir}`)
  await execCmd(`rm ${environment}.tar.gz`)
}

const toFile = promisify(fs.writeFile)

async function writeProxiedContractGetter(artifactDir, contractName, outputDir) {
  const artifact = JSON.parse(
    fs.readFileSync(path.join(artifactDir, `${contractName}.json`)).toString()
  )
  const proxyArtifact = JSON.parse(
    fs.readFileSync(path.join(artifactDir, `${contractName}Proxy.json`)).toString()
  )
  // TODO(asa): Don't hardcode this
  const networkId = '1101'
  const proxyAddress = proxyArtifact.networks[networkId].address
  // TODO(asa): Use prettify to clean these up
  await toFile(
    `${outputDir}/${contractName}.ts`,
    `
import * as Web3 from 'web3'
import { ${contractName} as ${contractName}Type } from 'types/${contractName}'
export default async function getInstance(web3: Web3.default, account: string = null) {
  const contract = new web3.eth.Contract(${JSON.stringify(
    artifact.abi,
    null,
    2
  )}, "${proxyAddress}") as unknown as ${contractName}Type
  contract.options.from = account || (await web3.eth.getAccounts())[0]
  return contract
}
`
  )
}

async function writeProxiedContractGetters(artifactDir, outputDir, environment) {
  await downloadContractArtifacts('contract_artifacts', environment, artifactDir)
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir)
  }

  const jsonDir = path.join(artifactDir, `build/${environment}/contracts`)
  const proxiedContracts = fs
    .readdirSync(jsonDir)
    .filter((filename) => /\w+Proxy.json$/.test(filename))
    .map((proxyContractName) => proxyContractName.slice(0, -'Proxy.json'.length))

  proxiedContracts.forEach(async function(contractName) {
    await writeProxiedContractGetter(jsonDir, contractName, outputDir)
  })
}

// TODO(asa): Require environment to be set or default to integration
const argv = require('minimist')(process.argv.slice(2))

async function buildSdk() {
  const modulePath = path.dirname(__dirname)
  if (argv._.length === 0) {
    console.error('First argument should be the environment name')
    process.exit(1)
  }
  const network = argv._[0]
  // TODO(asa): Run tsc after this
  await writeProxiedContractGetters(
    path.join(modulePath, '.artifacts'),
    path.join(modulePath, './contracts'),
    network
  )
  const contractArtifactsPattern = path.join(
    modulePath,
    '.artifacts/build/',
    network,
    'contracts/*.json'
  )
  await execCmd(
    `yarn run --cwd="${modulePath}" typechain --target="web3-1.0.0" --outDir=types "${contractArtifactsPattern}"`
  )
}

buildSdk()
