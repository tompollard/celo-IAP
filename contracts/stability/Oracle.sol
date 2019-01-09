pragma solidity ^0.4.22;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "./FractionUtil.sol";
import "./interfaces/IOracle.sol";
import "../common/Initializable.sol";


/**
 * @title A simple oracle for exchange rates.
 */
contract Oracle is IOracle, Ownable, Initializable {

  using FractionUtil for FractionUtil.Fraction;

  mapping (address => mapping (address => FractionUtil.Fraction)) public exchangeRates;

  event ExchangeRateSet(
    address indexed makerToken,
    address indexed takerToken,
    uint256 makerAmount,
    uint256 takerAmount
  );

  function initialize() external initializer {
    owner = msg.sender;
  }

  /**
   * @notice Sets exchange rate in the form of (maker token amount, taker token amount).
   * @param makerToken Address of maker token. 0 is reserved for taker token's peg.
   * @param takerToken Address of taker token. 0 is reserved for maker token's peg.
   * @param makerAmount The amount of maker token.
   * @param takerAmount The amount of taker token.
   */
  function setExchangeRate(
    address makerToken,
    address takerToken,
    uint256 makerAmount,
    uint256 takerAmount
  )
    external
    onlyOwner
  {
    require(makerToken != 0 || takerToken != 0);
    setExchangeRateHelper(makerToken, takerToken, makerAmount, takerAmount);
    setExchangeRateHelper(takerToken, makerToken, takerAmount, makerAmount);
  }

  /**
   * @notice Gets the exchange rate in the form of (maker token amount, taker token amount).
   * @param makerToken Address of maker token. 0 is reserved for taker token's peg.
   * @param takerToken Address of taker token.
   * @return The maker token amount in an exchange rate maker/taker pair.
   * @return The taker token amount in an exchange rate maker/taker pair.
   */
  function getExchangeRate(
    address makerToken,
    address takerToken
  )
    external
    view
    returns (uint256, uint256)
  {
    require(makerToken != 0 || takerToken != 0);
    FractionUtil.Fraction storage exchangeRate = exchangeRates[makerToken][takerToken];
    require(exchangeRate.numerator > 0 && exchangeRate.denominator > 0);
    return (exchangeRate.numerator, exchangeRate.denominator);
  }

  /*
   * Internal functions
   */
  /**
   * @notice Sets the exchange rate in the form of (maker token amount, taker token amount).
   * @param makerToken Address of maker token. 0 is reserved for taker token's peg.
   * @param takerToken Address of taker token. 0 is reserved for maker token's peg.
   * @param makerAmount The amount of maker token.
   * @param takerAmount The amount of taker token.
   */
  function setExchangeRateHelper(
    address makerToken,
    address takerToken,
    uint256 makerAmount,
    uint256 takerAmount
  )
    internal
  {
    require(makerAmount > 0 && takerAmount > 0);
    FractionUtil.Fraction storage exchangeRate = exchangeRates[makerToken][takerToken];
    exchangeRate.numerator = makerAmount;
    exchangeRate.denominator = takerAmount;
    emit ExchangeRateSet(makerToken, takerToken, makerAmount, takerAmount);
  }
}
