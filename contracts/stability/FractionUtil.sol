pragma solidity ^0.4.23;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";


library FractionUtil {

  using SafeMath for uint256;

  struct Fraction {
    uint256 numerator;
    uint256 denominator;
  }

  /**
   * @dev Returns whether exchange rate "x" is equal to exchange rate "y".
   * @param x An Fraction struct.
   * @param y An Fraction struct.
   * @return x == y
   */
  function equals(
    Fraction x,
    Fraction y
  )
    internal
    pure
    returns (bool)
  {
    return x.numerator.mul(y.denominator) == y.numerator.mul(x.denominator);
  }

  /**
   * @dev Returns a new exchange rate that is the sum of two rates.
   * @param x An Fraction struct.
   * @param y An Fraction struct.
   * @return x + y
   */
  function add(
    Fraction x,
    Fraction y
  )
    internal
    pure
    returns (uint256, uint256)
  {
    return (
      x.numerator.mul(y.denominator).add(y.numerator.mul(x.denominator)),
      x.denominator.mul(y.denominator)
    );
  }

  /**
   * @dev Returns a new exchange rate that is the two rates subtracted from each other.
   * @param x An Fraction struct.
   * @param y An Fraction struct.
   * @return x - y
   */
  function sub(
    Fraction x,
    Fraction y
  )
    internal
    pure
    returns (uint256, uint256)
  {
    require(isGreaterThanOrEqualTo(x, y));
    return (
      x.numerator.mul(y.denominator).sub(y.numerator.mul(x.denominator)),
      x.denominator.mul(y.denominator)
    );
  }

  /**
   * @dev Returns whether exchange rate "x" is greater than exchange rate "y".
   * @param x An Fraction struct.
   * @param y An Fraction struct.
   * @return x > y
   */
  function isGreaterThan(
    Fraction x,
    Fraction y
  )
    internal
    pure
    returns (bool)
  {
    return x.numerator.mul(y.denominator) > y.numerator.mul(x.denominator);
  }

  /**
   * @dev Returns whether exchange rate "x" is greater than or equal to exchange rate "y".
   * @param x An Fraction struct.
   * @param y An Fraction struct.
   * @return x >= y
   */
  function isGreaterThanOrEqualTo(
    Fraction x,
    Fraction y
  )
    internal
    pure
    returns (bool)
  {
    return x.numerator.mul(y.denominator) >= y.numerator.mul(x.denominator);
  }

  /**
   * @dev Returns whether exchange rate "x" is less than exchange rate "y".
   * @param x An Fraction struct.
   * @param y An Fraction struct.
   * @return x < y
   */
  function isLessThan(
    Fraction x,
    Fraction y
  )
    internal
    pure
    returns (bool)
  {
    return x.numerator.mul(y.denominator) < y.numerator.mul(x.denominator);
  }

  /**
   * @dev Returns whether exchange rate "x" is less than or equal to exchange rate "y".
   * @param x An Fraction struct.
   * @param y An Fraction struct.
   * @return x <= y
   */
  function isLessThanOrEqualTo(
    Fraction x,
    Fraction y
  )
    internal
    pure
    returns (bool)
  {
    return x.numerator.mul(y.denominator) <= y.numerator.mul(x.denominator);
  }

  /**
   * @dev Returns whether exchange rate "z" is between exchange rates "x" and "y".
   * @param z An Fraction struct.
   * @param x An Fraction struct representing a rate lower than "y".
   * @param y An Fraction struct representing a rate higher than "x".
   * @return x <= z <= y
   */
  function isBetween(
    Fraction z,
    Fraction x,
    Fraction y
  )
    internal
    pure
    returns (bool)
  {
    return isLessThanOrEqualTo(x, z) && isLessThanOrEqualTo(z, y);
  }
}
