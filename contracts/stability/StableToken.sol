pragma solidity ^0.4.22;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/StandardToken.sol";

import "./interfaces/IStableToken.sol";
import "./FractionUtil.sol";
import "./interfaces/IMedianator.sol";
import "./PartialAmount.sol";
import "../common/Initializable.sol";
import "../common/UsingRegistry.sol";


/**
 * @title An ERC20 compliant token with adjustable supply.
 */
contract StableToken is IStableToken, StandardToken, Ownable, Initializable, UsingRegistry {

  using FractionUtil for FractionUtil.Fraction;
  using PartialAmount for uint256;
  using SafeMath for uint256;

  event MinterSet(address indexed _minter);
  event StableWindowSet(ExchangeRateRange window);

  event TransferComment(
    string comment
  );

  struct ExchangeRateRange {
    FractionUtil.Fraction min;
    FractionUtil.Fraction max;
  }

  struct StableTokenParams {
    uint256 rebasePeriod;
    uint256 lastRebase;
    ExchangeRateRange stableWindow;
  }

  string public name;
  string public symbol;
  address public minter;
  uint8 public decimals;
  StableTokenParams public params;

  /**
   * @notice Throws if called by any account other than the minter.
   */
  modifier onlyMinter() {
    require(msg.sender == minter);
    _;
  }

  /**
   * @param _name The name of the stable token (English)
   * @param _symbol A short symbol identifying the token (e.g. "cUSD")
   * @param _decimals Tokens are divisible to this many decimal places.
   * @param rebasePeriod The rebase period in seconds.
   * @param stableWindowMinBaseAmount The amount of the token's peg in the exchange rate defining
   *   the lower bound of the stable window.
   * @param stableWindowMinCounterAmount The amount of the stable token in the exchange rate
   *   defining the lower bound of the stable window.
   * @param stableWindowMaxBaseAmount The amount of the token's peg in the exchange rate defining
   *   the upper bound of the stable window.
   * @param stableWindowMaxCounterAmount The amount of the stable token in the exchange rate
   *   defining the upper bound of the stable window.
   */
  function initialize(
    string _name,
    string _symbol,
    uint8 _decimals,
    uint256 rebasePeriod,
    uint256 stableWindowMinBaseAmount,
    uint256 stableWindowMinCounterAmount,
    uint256 stableWindowMaxBaseAmount,
    uint256 stableWindowMaxCounterAmount,
    address registryAddress
  )
    external
    initializer
  {
    totalSupply_ = 0;
    owner = msg.sender;
    name = _name;
    symbol = _symbol;
    decimals = _decimals;
    // solhint-disable-next-line not-rely-on-time
    params.lastRebase = now;
    setRebasePeriod(rebasePeriod);
    setStableWindow(
      stableWindowMinBaseAmount,
      stableWindowMinCounterAmount,
      stableWindowMaxBaseAmount,
      stableWindowMaxCounterAmount
    );
    setRegistry(registryAddress);
  }

  // Should this be tied to the registry?
  /**
   * @notice Updates 'minter'.
   * @param _minter An address with special permissions to modify its balance
   */
  function setMinter(address _minter) external onlyOwner {
    minter = _minter;
    emit MinterSet(_minter);
  }

  /**
   * @notice Mints new StableToken and gives it to 'to'.
   * @param to The account for which to mint tokens.
   * @param value The amount of StableToken to mint.
   */
  function mint(address to, uint256 value) external onlyMinter returns (bool) {
    totalSupply_ = totalSupply_.add(value);
    balances[to] = balances[to].add(value);
    emit Transfer(address(0), to, value);
    return true;
  }

  /**
   * @dev Transfer token for a specified address
   * @param to The address to transfer to.
   * @param value The amount to be transferred.
   * @param comment The transfer comment.
   * @return True if the transaction succeeds.
   */
  function transferWithComment(address to, uint256 value, string comment) external returns (bool) {
    bool succeeded = transfer(to, value);
    emit TransferComment(comment);
    return succeeded;
  }

  /**
   * @notice Burns StableToken from the balance of 'minter'.
   * @param value The amount of StableToken to burn.
   */
  function burn(uint256 value) external onlyMinter returns (bool) {
    require(value <= balances[msg.sender]);
    totalSupply_ = totalSupply_.sub(value);
    balances[msg.sender] = balances[msg.sender].sub(value);
    return true;
  }

  /**
   * @notice Updates the last rebase to 'now'.
   */
  function resetLastRebase() external onlyMinter {
    // solhint-disable-next-line not-rely-on-time
    params.lastRebase = now;
  }

  /**
   * @notice Returns the unpacked params for this stable token.
   */
  function getStableTokenParams()
    external
    view
    returns (uint256, uint256, uint256, uint256, uint256, uint256)
  {
    return (
      params.rebasePeriod,
      params.lastRebase,
      params.stableWindow.min.numerator,
      params.stableWindow.min.denominator,
      params.stableWindow.max.numerator,
      params.stableWindow.max.denominator
    );
  }

  /**
   * @notice Returns the target total supply of this token.
   */
  function targetTotalSupply() external view returns (uint256) {
    uint256 pegAmount;
    uint256 tokenAmount;
    (pegAmount, tokenAmount) = getPrice();
    // TODO(asa): Check for rounding errors.
    return totalSupply().getPartialAmount(pegAmount, tokenAmount);
  }

  /**
   * @notice Returns whether or not the token needs to be rebased.
   */
  function needsRebase() external view returns (bool) {
    // solhint-disable-next-line not-rely-on-time
    if (now < params.lastRebase.add(params.rebasePeriod)) {
      return false;
    }

    uint256 pegAmount;
    uint256 tokenAmount;
    (pegAmount, tokenAmount) = getPrice();
    FractionUtil.Fraction memory price = FractionUtil.Fraction(
      pegAmount,
      tokenAmount
    );

    return (
      price.isLessThan(params.stableWindow.min) ||
      price.isGreaterThan(params.stableWindow.max)
    );
  }

  /**
   * @notice Updates the rebasePeriod for this token.
   * @param rebasePeriod The rebase period in seconds.
   */
  function setRebasePeriod(uint256 rebasePeriod) public onlyOwner {
    require(rebasePeriod > 0);
    params.rebasePeriod = rebasePeriod;
  }

  /**
   * @notice Sets the window for which a token is considered stable with respect to its peg.
   * @param stableWindowMinBaseAmount The amount of the token's peg in the exchange rate defining
   *   the lower bound of the stable window.
   * @param stableWindowMinCounterAmount The amount of the stable token in the exchange rate
   *   defining the lower bound of the stable window.
   * @param stableWindowMaxBaseAmount The amount of the token's peg in the exchange rate defining
   *   the upper bound of the stable window.
   * @param stableWindowMaxCounterAmount The amount of the stable token in the exchange rate
   *   defining the upper bound of the stable window.
   * @dev Throws if the stable window is not inclusive of an exchange rate of 1.
   */
  // TODO(asaj): Pass an ExchangeRateRange once web3 supports passing structs
  function setStableWindow(
    uint256 stableWindowMinBaseAmount,
    uint256 stableWindowMinCounterAmount,
    uint256 stableWindowMaxBaseAmount,
    uint256 stableWindowMaxCounterAmount
  )
    public
    onlyOwner
  {
    FractionUtil.Fraction memory one = FractionUtil.Fraction(1, 1);
    ExchangeRateRange memory stableWindow = ExchangeRateRange(
      FractionUtil.Fraction(stableWindowMinBaseAmount, stableWindowMinCounterAmount),
      FractionUtil.Fraction(stableWindowMaxBaseAmount, stableWindowMaxCounterAmount)
    );
    require(one.isBetween(stableWindow.min, stableWindow.max));
    params.stableWindow = stableWindow;
    emit StableWindowSet(stableWindow);
  }

  /**
   * @notice Returns the price of the token with respect to its peg.
   */
  function getPrice() internal view returns (uint256, uint256) {
    IMedianator medianator = IMedianator(registry.getAddressFor(MEDIANATOR_REGISTRY_ID));
    return medianator.getExchangeRate(0, address(this));
  }
}
