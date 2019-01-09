pragma solidity ^0.4.24;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

import "./interfaces/IRegistry.sol";

// Ideally, UsingRegistry should inherit from Initializable and implement initialize() which calls
// setRegistry(). TypeChain currently has problems resolving overloaded functions, so this is not
// possible right now.
// TODO(amy): Fix this when the TypeChain issue resolves.

contract UsingRegistry is Ownable {

  event RegistrySet(address indexed registryAddress);

  // solhint-disable state-visibility
  string constant ADDRESS_BASED_ENCRYPTION_REGISTRY_ID = "AddressBasedEncryption";
  string constant AUCTION_REGISTRY_ID = "Auction";
  string constant BOND_TOKEN_REGISTRY_ID = "BondToken";
  string constant GOLD_TOKEN_REGISTRY_ID = "GoldToken";
  string constant MEDIANATOR_REGISTRY_ID = "Medianator";
  string constant RESERVE_REGISTRY_ID = "Reserve";  
  // solhint-enable state-visibility

  IRegistry public registry;

  /**
   * @notice Updates the address pointing to a Registry contract.
   * @param registryAddress The address of a registry contract for routing to other contracts.
   */
  function setRegistry(address registryAddress) public onlyOwner {
    registry = IRegistry(registryAddress);
    emit RegistrySet(registryAddress);
  }
}
