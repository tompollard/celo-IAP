pragma solidity ^0.4.22;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "./interfaces/IExchange.sol";
import "./FractionUtil.sol";
import "../common/Initializable.sol";
import "../common/interfaces/IERC20Token.sol";


/**
 * @title Contract that allows to exchange StableToken for GoldToken and vice versa
 * using a Constant Product Market Maker Model
 */
contract Exchange is IExchange, Initializable, Ownable {
  using SafeMath for uint256;
  using FractionUtil for FractionUtil.Fraction;

  event TokenPairAdded(
    address tokenA,
    address tokenB,
    uint256 tokenASupply,
    uint256 tokenBSupply,
    uint256 spreadNumerator,
    uint256 spreadDenominator
  );

  // solhint-disable-next-line
  event Exchange(
    address indexed exchanger,
    address indexed buyToken,
    address indexed sellToken,
    uint256 buyAmount,
    uint256 sellAmount
  );

  mapping(address => mapping(address => FractionUtil.Fraction)) public spreads;

  // TODO: Remove this one with https://github.com/celo-org/celo-monorepo/issues/2000
  // solhint-disable-next-line
  function() public payable {}

  /**
   * @dev Initializes the new exchange
   */
  function initialize() external initializer {
    owner = msg.sender;
  }

  /**
   * @dev Adds a TokenPair to this exchange. Assumes this contract to hold balances
   * of Token A and B such that the exchange rate of A:B is between the minimum and
   * maximum target price
   * @param tokenA Token A
   * @param tokenB Token B
   * @param spreadNumerator The numerator of the spread to be used for this pair
   * @param spreadDenominator The denominator of the spread to be used for this pair
   * @param targetPriceNumeratorMin The numerator of the targetPrice lower bound.
   * @param targetPriceDenominatorMin The denominator of targetPrice lower bound.
   * @param targetPriceNumeratorMax The numerator of the targetPrice upper bound.
   * @param targetPriceDenominatorMax The denominator of targetPrice upper bound.
   */
  function addTokenPair(
    address tokenA,
    address tokenB,
    uint256 spreadNumerator,
    uint256 spreadDenominator,
    uint256 targetPriceNumeratorMin,
    uint256 targetPriceDenominatorMin,
    uint256 targetPriceNumeratorMax,
    uint256 targetPriceDenominatorMax
  )
    external
    onlyOwner
  {
    require(tokenA != tokenB, "Cannot create a pair from the same token");
    require(spreads[tokenA][tokenB].denominator == 0, "Token pair alrady exists");

    FractionUtil.Fraction memory spread;
    spread = FractionUtil.Fraction(spreadNumerator, spreadDenominator);
    require(spread.denominator > 0, "spreadDenominator has to be greater than 0");
    require(spread.isLessThan(FractionUtil.Fraction(1, 1)), "spread is larger than 1.0");

    require(IERC20Token(tokenA).balanceOf(address(this)) > 0, "Token A balance is 0");
    require(IERC20Token(tokenB).balanceOf(address(this)) > 0, "Token B balance is 0");

    uint256 currentPriceNumerator;
    uint256 currentPriceDenominator;

    (currentPriceNumerator, currentPriceDenominator) = getTokenPrice(tokenA, tokenB);

    FractionUtil.Fraction memory currentPrice = FractionUtil.Fraction(
      currentPriceNumerator,
      currentPriceDenominator
    );

    require(
      currentPrice.isLessThanOrEqualTo(
        FractionUtil.Fraction(targetPriceNumeratorMax, targetPriceDenominatorMax)
      ), "Current token balances yield a larger targetPrice than specified");
    require(
      currentPrice.isGreaterThanOrEqualTo(
        FractionUtil.Fraction(targetPriceNumeratorMin, targetPriceDenominatorMin)
      ), "Current token balances yield a smaller targetPrice than specified");

    spreads[tokenA][tokenB] = spread;
    spreads[tokenB][tokenA] = spread;

    emit TokenPairAdded(
      tokenA,
      tokenB,
      IERC20Token(tokenA).balanceOf(address(this)),
      IERC20Token(tokenB).balanceOf(address(this)),
      spread.numerator,
      spread.denominator
    );
  }

  /**
   * @dev Returns the spread for a token pair
   * @param tokenA Token A
   * @param tokenB Token B
   * @return (spread.numerator, spread.denominator)
   */
  function getSpread(address tokenA, address tokenB) public view returns (uint256, uint256) {
    FractionUtil.Fraction storage spread = spreads[tokenA][tokenB];
    return (spread.numerator, spread.denominator);
  }

  /**
   * @dev Returns the amount of buyToken a user would get for sellAmount of sellToken
   * @param buyToken The token the exchange gives back to the user
   * @param sellToken The token the exchange receives from the user
   * @param sellAmount The amount of sellToken the user is selling to the exchange
   * @return The corresponding buyToken amount.
   */
  function getBuyTokenAmount(
    address buyToken,
    address sellToken,
    uint256 sellAmount
  )
    public
    view
    returns (uint256)
  {
    FractionUtil.Fraction storage spread = spreads[buyToken][sellToken];
    require(spread.denominator != 0, "Token pair does not exist");

    uint256 buyTokenSupply = IERC20Token(buyToken).balanceOf(address(this));
    uint256 sellTokenSupply = IERC20Token(sellToken).balanceOf(address(this));

    uint256 x = spread.denominator.sub(spread.numerator).mul(sellAmount);
    uint256 numerator = x.mul(buyTokenSupply);
    uint256 denominator = sellTokenSupply.mul(spread.denominator).add(x);

    return numerator.div(denominator);
  }

  /**
   * @dev Returns the amount of sellToken a user would need to exchange to receive buyAmount of
   * buyToken.
   * @param buyToken The token the exchange gives back to the user
   * @param sellToken The token the exchange receives from the user
   * @param buyAmount The amount of buyToken the user would like to purchase.
   * @return The corresponding sellToken amount.
   */
  function getSellTokenAmount(
    address buyToken,
    address sellToken,
    uint256 buyAmount
  )
    public
    view
    returns (uint256)
  {
    FractionUtil.Fraction storage spread = spreads[buyToken][sellToken];
    require(spread.denominator != 0, "Token pair does not exist");

    uint256 buyTokenSupply = IERC20Token(buyToken).balanceOf(address(this));
    uint256 sellTokenSupply = IERC20Token(sellToken).balanceOf(address(this));

    uint256 numerator = spread.denominator.mul(buyAmount).mul(sellTokenSupply);
    uint256 denominator = spread.denominator.sub(spread.numerator).mul(
      buyTokenSupply.sub(buyAmount)
    );

    return numerator.div(denominator);
  }

  /**
   * @dev Returns the price of buyToken in terms of sellToken
   * @param buyToken The token the exchange gives back to the user
   * @param sellToken The token the exchange receives from the user
   * @return (price.numerator, price.denominator)
   */
  function getTokenPrice(
    address buyToken,
    address sellToken
  )
    public
    view
    returns (uint256, uint256)
  {
    uint256 buyTokenSupply = IERC20Token(buyToken).balanceOf(address(this));
    uint256 sellTokenSupply = IERC20Token(sellToken).balanceOf(address(this));
    return (sellTokenSupply, buyTokenSupply);
  }

  /**
   * @dev Exchanges sellAmount of sellToken in exchange for at least minBuyAmount of buyToken
   * Requires the sellAmount to have been approved to the exchange
   * @param buyToken The token the exchange gives back to the user
   * @param sellToken The token the exchange receives from the user
   * @param sellAmount The amount of sellToken the user is selling to the exchange
   * @param minBuyAmount The minimum amount of buyToken the user has to receive for this
   * transaction to succeed
   * @return The amount of buyToken that was transfered
   */
  // solhint-disable-next-line
  function exchange(
    address buyToken,
    address sellToken,
    uint256 sellAmount,
    uint256 minBuyAmount
  )
    public
    returns (uint256)
  {
    uint256 buyAmount = getBuyTokenAmount(buyToken, sellToken, sellAmount);

    require(buyAmount >= minBuyAmount, "Calculated buyAmount was less than specified minBuyAmount");

    require(
      IERC20Token(sellToken).transferFrom(msg.sender, address(this), sellAmount),
      "Transfer of sell token failed"
    );
    require(
      IERC20Token(buyToken).transfer(msg.sender, buyAmount),
      "Transfer of buyToken failed"
    );

    emit Exchange(msg.sender, buyToken, sellToken, buyAmount, sellAmount);
    return buyAmount;
  }

}
