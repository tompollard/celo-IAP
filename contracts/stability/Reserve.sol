pragma solidity ^0.4.22;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

import "./FractionUtil.sol";
import "./interfaces/IReserve.sol";
import "./interfaces/IBSTAuction.sol";
import "./interfaces/IMedianator.sol";
import "./interfaces/IStableToken.sol";

import "../common/Initializable.sol";
import "../common/UsingRegistry.sol";
import "../common/interfaces/IGoldToken.sol";


/**
 * @title Ensures price stability of StableTokens with respect to their pegs
 */
contract Reserve is IReserve, Ownable, Initializable, UsingRegistry {

  using FractionUtil for FractionUtil.Fraction;
  using SafeMath for uint256;

  mapping(address => bool) private _tokens;

  modifier onlyBy(string identifier) {
    require(msg.sender == registry.getAddressFor(identifier));
    _;
  }

  modifier isStableToken(address token) {
    require(_tokens[token]);
    _;
  }

  function() external payable {} // solhint-disable no-empty-blocks

  function initialize(address registryAddress) external initializer {
    owner = msg.sender;
    setRegistry(registryAddress);
  }

  /**
   * @notice Add a token that the reserve will stablize.
   * @param token The address of the token being stabilized.
   */
  function addToken(address token) external onlyOwner returns (bool) {
    require(_tokens[token] == false);
    _tokens[token] = true;
    return true;
  }

  /**
   * @notice Remove a token that the reserve will no longer stabilize.
   * @param token The address of the token no longer being stabilized.
   */
  function removeToken(address token) external onlyOwner isStableToken(token) returns (bool) {
    _tokens[token] = false;
    return true;
  }

  /**
   * @notice Burns all tokens held by the Reserve.
   * @param token The address of the token to burn.
   */
  function burnToken(address token) external isStableToken(token) returns (bool) {
    IStableToken stableToken = IStableToken(token);
    require(stableToken.burn(stableToken.balanceOf(address(this))));
    return true;
  }

  /**
   * @notice Mint tokens.
   * @param to The address that will receive the minted tokens.
   * @param token The address of the token to mint.
   * @param value The amount of tokens to mint.
   */
  function mintToken(
    address to,
    address token,
    uint256 value
  )
    external
    isStableToken(token)
    returns (bool)
  {
    require(
      msg.sender == registry.getAddressFor(AUCTION_REGISTRY_ID) ||
      msg.sender == registry.getAddressFor(BOND_TOKEN_REGISTRY_ID)
    );
    IStableToken stableToken = IStableToken(token);
    stableToken.mint(to, value);
    return true;
  }

  /**
   * @notice Transfer gold.
   * @param to The address that will receive the gold.
   * @param value The amount of gold to transfer.
   */
  function transferGold(
    address to,
    uint256 value
  )
    external
    onlyBy(AUCTION_REGISTRY_ID)
    returns (bool)
  {
    IGoldToken goldToken = IGoldToken(registry.getAddressFor(GOLD_TOKEN_REGISTRY_ID));
    require(goldToken.transfer(to, value));
    return true;
  }

  /**
   * @notice Starts an auction to adjust the supply of StableToken.
   * @param stableTokenAddress The address of the StableToken.
   * @dev Throws if stableTokenAddress is not in the TokenRegistry or if it doesn't need rebasing.
   */
  function rebaseToken(
    address stableTokenAddress
  )
    external
    isStableToken(stableTokenAddress)
    returns (bool)
  {
    IStableToken stableToken = IStableToken(stableTokenAddress);
    require(stableToken.needsRebase());
    stableToken.resetLastRebase();

    uint256 totalSupply = stableToken.totalSupply();
    uint256 targetSupply = stableToken.targetTotalSupply();

    address sellToken;
    address buyToken;
    uint256 cap;
    if (totalSupply > targetSupply) {
      // Contraction
      sellToken = stableTokenAddress;
      buyToken = registry.getAddressFor(GOLD_TOKEN_REGISTRY_ID);
      cap = totalSupply.sub(targetSupply);
    } else {
      // Expansion
      sellToken = registry.getAddressFor(GOLD_TOKEN_REGISTRY_ID);
      buyToken = stableTokenAddress;
      cap = targetSupply.sub(totalSupply);
    }

    IBSTAuction auction = IBSTAuction(registry.getAddressFor(AUCTION_REGISTRY_ID));
    auction.reset(sellToken, buyToken);
    auction.start(
      sellToken,
      buyToken,
      stableTokenAddress,
      cap
    );
    return true;
  }

  /**
   * @notice Allows exchange of Gold and StableToken at the current exchange rate.
   * @param makerTokenAddress Address of the token being provided by msg.sender.
   * @param takerTokenAddress Address of the token being provided by reserve.
   * @param makerTokenAmount Amount of makerToken to transfer from maker to taker.
   * @param takerTokenAmount Amount of takerToken to transfer from taker to maker.
   * @return Total amount of takerToken filled in exchange.
   */
  function exchangeGoldAndStableTokens(
    address makerTokenAddress,
    address takerTokenAddress,
    uint256 makerTokenAmount,
    uint256 takerTokenAmount
  )
    external
    returns(uint256)

  {
    IGoldToken goldToken = IGoldToken(registry.getAddressFor(GOLD_TOKEN_REGISTRY_ID));
    // Require exchange of Gold and Stable tokens
    require(
      (makerTokenAddress == address(goldToken)) !=
      (takerTokenAddress == address(goldToken))
    );
    require(_tokens[makerTokenAddress] != _tokens[takerTokenAddress]);

    // Require exchange rate to match market rate from medianator
    require(
      checkValidExchangeRate(
        makerTokenAddress,
        takerTokenAddress,
        makerTokenAmount,
        takerTokenAmount
      )
    );

    if (makerTokenAddress == address(goldToken)) {
      require(goldToken.transferFrom(msg.sender, address(this), makerTokenAmount));
      // Mint dollars to exchange for gold
      require(IStableToken(takerTokenAddress).mint(msg.sender, takerTokenAmount));
    } else {
      require(
        IStableToken(makerTokenAddress).transferFrom(
          msg.sender,
          address(this),
          makerTokenAmount
        )
      );
      IStableToken(makerTokenAddress).burn(makerTokenAmount);
      require(goldToken.transfer(msg.sender, takerTokenAmount));
    }

    return takerTokenAmount;
  }

  function tokens(address addr) external view returns (bool) {
    return _tokens[addr];
  }

  /*
   * Internal functions
   */
  /**
   * @notice Checks that the provided exchange rate is >= the medianator exchange rate.
   * @param makerTokenAddress The address of the token provided by 'maker'.
   * @param takerTokenAddress The address of the token provided by 'taker'.
   * @param makerTokenAmount The amount of makerToken provided by 'maker'.
   * @param takerTokenAmount The amount of takerToken provided by 'taker'.
   * @return Whether or not the provided exchange rate is >= the medianator exchange rate.
   */
  function checkValidExchangeRate(
    address makerTokenAddress,
    address takerTokenAddress,
    uint256 makerTokenAmount,
    uint256 takerTokenAmount
  )
    internal
    view
    returns(bool)
  {
    IMedianator medianator = IMedianator(registry.getAddressFor(MEDIANATOR_REGISTRY_ID));
    uint256 baseAmount;
    uint256 counterAmount;
    (baseAmount, counterAmount) = medianator.getExchangeRate(makerTokenAddress, takerTokenAddress);
    FractionUtil.Fraction memory actual = FractionUtil.Fraction(
      baseAmount,
      counterAmount
    );
    FractionUtil.Fraction memory given = FractionUtil.Fraction(
      makerTokenAmount,
      takerTokenAmount
    );
    return given.isGreaterThanOrEqualTo(actual);
  }
}
