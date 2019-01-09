pragma solidity ^0.4.23;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";


// TODO(asa): Inherit from SafeMath when possible.
library PartialAmount {

  using SafeMath for uint256;

  /**
   * @dev Calculates partial value given a numerator and denominator, checking for rounding errors.
   * @param value Value to calculate partial of.
   * @param numerator Numerator.
   * @param denominator Denominator.
   * @param decimals The maximal decimal place for which rounding errors are permitted.
   * @return Partial value of target.
   */
  function getPartialAmount(
    uint256 value,
    uint256 numerator,
    uint256 denominator,
    uint256 decimals
  )
    internal
    pure
    returns (uint256)
  {
    uint256 precision = 10 ** decimals;
    uint256 precisePartialAmount = numerator.mul(precision).mul(value).div(denominator);
    uint256 partialAmount = numerator.mul(value).div(denominator);
    require(partialAmount.mul(precision) == precisePartialAmount, "Rounding error.");
    return partialAmount;
  }

  /**
   * @dev Calculates partial value given a numerator and denominator.
   * @param value Value to calculate partial of.
   * @param numerator Numerator.
   * @param denominator Denominator.
   * @return Partial value of target.
   */
  function getPartialAmount(
    uint256 value,
    uint256 numerator,
    uint256 denominator
  )
    internal
    pure
    returns (uint256)
  {
    return numerator.mul(value).div(denominator);
  }
}
