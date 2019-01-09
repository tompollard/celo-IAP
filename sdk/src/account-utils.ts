import * as prompts from 'prompts'

// TODO(asa): Fix Web3 type here
export async function unlockAccount(web3: any, duration: number) {
  const accounts = await web3.eth.getAccounts()
  const response = await prompts({
    type: 'password',
    name: 'password',
    message: 'Please enter a password to unlock your account',
  })
  await web3.eth.personal.unlockAccount(accounts[0], response.password, duration)
  const account = accounts[0]
  return account
}
