pragma solidity ^0.4.24;
/* solhint-disable func-order */

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/math/Math.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";

import "./interfaces/IBSTAuction.sol";
import "./PartialAmount.sol";
import "./SortedBids.sol";
import "./interfaces/IReserve.sol";
import "../common/interfaces/IERC20Token.sol";
import "../common/Initializable.sol";
import "../common/UsingRegistry.sol";

/*
 * A capped multi-stage first-price sealed-bid auction for ERC20 tokens.
 * en.wikipedia.org/wiki/First-price_sealed-bid_auction
 *
 * The auction receives sellToken in return for buyToken. Bidders submit their
 * bids by specifying the amount of sellToken they wish to exchange for a
 * specified amount of buyToken. The auction fills these bids up until 'cap' of
 * the capped token has been exchanged, where the capped token can be
 * either sellToken or buyToken.
 *
 * Stages:
 *   Commit: In the commit phase bidders submit binding sealed bids. To make the
 *   bid binding, the total amount of sellToken that could possibly be
 *   exchanged by this bid is transferred to this contract.
 *
 *   Reveal: In the reveal phase bidders submit the corresponding amount of buyToken that was
 *   used to create the bid hash submitted in the commit phase.
 *
 *   Fill: In the fill phase bidders are able to claim their portion of the auction proceeds.
 *   Bidders must call fill() in this stage in order to get their money back, even if their bid
 *   did not win. This is to ensure bidders cannot renege on their bid.
 *
 * Once the fill phase is over, users can withdraw their purchased buyToken
 * and any unspent sellToken.
 */

/**
 * @title A capped multi-stage first-price sealed-bid auction for ERC20 tokens.
 */
contract BSTAuction is IBSTAuction, Ownable, Initializable, UsingRegistry {

  using PartialAmount for uint256;
  using SafeMath for uint256;
  using SortedBids for SortedBids.Tree;

  enum AuctionStage {
    Reset,
    Commit,
    Reveal,
    Fill,
    Ended
  }

  enum BidState {
    Committed,
    Revealed,
    Filled
  }

  event AuctionStarted(
    address indexed sellToken,
    address indexed buyToken,
    uint256 indexed nonce,
    uint256 startTime,
    uint256 stageDuration,
    address cappedToken,
    uint256 cap
  );

  event AuctionStageChanged(
    address indexed sellToken,
    address indexed buyToken,
    uint256 indexed nonce,
    AuctionStage stage
  );

  event Commit(
    address indexed sellToken,
    address indexed buyToken,
    address indexed bidder,
    uint256 nonce,
    uint256 committedSellTokenAmount,
    uint256 bidIndex
  );

  event Reveal(
    address indexed sellToken,
    address indexed buyToken,
    address indexed bidder,
    uint256 nonce,
    uint256 sellTokenAmount,
    uint256 buyTokenAmount,
    uint256 bidIndex
  );

  event Fill(
    address indexed sellToken,
    address indexed buyToken,
    address indexed bidder,
    uint256 nonce,
    uint256 sellTokenAmount,
    uint256 buyTokenAmount,
    uint256 bidIndex
  );

  event Withdrawal(
    address indexed token,
    address indexed bidder,
    uint256 amount
  );

  struct AuctionParams {
    // The current stage of this auction.
    AuctionStage stage;
    // The address of the token (sellToken or buyToken) whose total exchange will be capped.
    // TODO(asa): This should be a boolean
    address cappedToken;
    // The maximum value of cappedToken that will be exchanged.
    uint256 cap;
    // The duration of each auction stage in seconds.
    uint256 stageDuration;
    // The time at which the auction started in seconds since epoch.
    uint256 startTime;
    // The nonce used to identify a particular auction.
    uint256 nonce;
  }

  struct UserBids {
    // The nonce used to identify which auction is being bid on.
    uint256 nonce;
    // The actual bids indexed by bidIndex
    Bid[] bids;
  }

  struct Bid {
    // Whether this bid has been committed, revealed, or filled.
    BidState state;
    // The bid's id in the sortedBids tree.
    uint64 bidId;
    // Allows the bidder to bid without revealing their buyTokenAmount.
    bytes32 bidHash;
    // An amount of sellToken >= the bidder's sellTokenAmount.
    uint256 committedSellTokenAmount;
  }

  // Maps sellToken and buyToken to the AuctionParams for that auction.
  mapping(address => mapping(address => AuctionParams)) private auctions;
  // Maps sellToken and buyToken to the BST of sorted bids for that auction.
  mapping(address => mapping(address => SortedBids.Tree)) public sortedBids;

  // Maps sellToken, buyToken, and bidder's account to the bidder's UserBid for that auction.
  // TODO(asa): Find a way to move this into AuctionParams
  mapping(address => mapping(address => mapping(address => UserBids))) public userBids;

  // Maps a token and bidder to the amount of that token they are owed by this contract.
  mapping(address => mapping(address => uint256)) public pendingWithdrawals;
  // Newly created auctions will have each stage last this many seconds.
  // TODO(asa): We should set a lower bound on this.
  uint256 public stageDuration;
  // A unique identifier for each auction.
  uint256 public nonce;

  /**
   * @notice Initializes public variables.
   * @param _stageDuration The duration in seconds of the Commit, Reveal, and Fill stages.
   */
  function initialize(
    uint256 _stageDuration,
    address registryAddress
  )
    external
    initializer
  {
    owner = msg.sender;
    stageDuration = _stageDuration;
    nonce = 0;
    setRegistry(registryAddress);
  }

  /**
   * @notice Throws if called by any address other than Reserve.
   */
  modifier onlyReserve() {
    require(msg.sender == registry.getAddressFor(RESERVE_REGISTRY_ID));
    _;
  }

  /**
   * @notice Sets the duration of newly created auction stages.
   * @param value The duration in seconds of the Commit, Reveal, and Fill stages.
   */
  function setStageDuration(uint256 value) external onlyOwner {
    stageDuration = value;
  }

  /**
   * @notice Resets an auction not already in progress.
   * @param sellToken Address of token to be exchanged by bidders.
   * @param buyToken Address of token to be exchanged by auction.
   */
  function reset(
    address sellToken,
    address buyToken
  )
    external
    onlyReserve
  {
    advanceStageIfComplete(sellToken, buyToken);
    AuctionParams storage auction = auctions[sellToken][buyToken];
    require(
      auction.stage == AuctionStage.Ended ||
      auction.stage == AuctionStage.Reset
    );

    if (auction.stage == AuctionStage.Ended) {
      auction.stage = AuctionStage.Reset;
      emit AuctionStageChanged(sellToken, buyToken, auction.nonce, auction.stage);
    }
  }

  /**
   * @notice Starts an auction.
   * @param sellToken Address of token to be exchanged by bidder.
   * @param buyToken Address of token to be exchanged by auction.
   * @param cappedToken Address of token whose total exchange will be capped.
   * @param cap The maximum number of cappedTokens to be exchanged.
   */
  function start(
    address sellToken,
    address buyToken,
    address cappedToken,
    uint256 cap
  )
    external
    onlyReserve
  {
    requireStage(sellToken, buyToken, AuctionStage.Reset);
    require((cappedToken == sellToken) != (cappedToken == buyToken));
    require(cap > 0 && stageDuration > 0);
    nonce = nonce.add(1);

    AuctionParams storage auction = auctions[sellToken][buyToken];
    auction.stage = AuctionStage.Commit;
    auction.cappedToken = cappedToken;
    auction.cap = cap;
    auction.stageDuration = stageDuration;
    // solhint-disable-next-line not-rely-on-time
    auction.startTime = now;
    auction.nonce = nonce;

    sortedBids[sellToken][buyToken].reinitializeTree(sellToken == cappedToken);

    emit AuctionStageChanged(sellToken, buyToken, auction.nonce, auction.stage);
    emit AuctionStarted(
      sellToken,
      buyToken,
      auction.nonce,
      auction.startTime,
      auction.stageDuration,
      auction.cappedToken,
      auction.cap
    );
  }

  // TODO(asa): Allow contracts to commit on behalf of a user
  /**
   * @notice Allows users to submit binding sealed bids.
   * @param sellToken Address of token to be exchanged by bidder.
   * @param buyToken Address of token to be exchanged by auction.
   * @param committedSellTokenAmount The amount of sellToken to be committed.
   * @param bidHash The hash of the bid whose contents will be revealed.
   */
  // solhint-disable-next-line
  function commit(
    address sellToken,
    address buyToken,
    uint256 committedSellTokenAmount,
    bytes32 bidHash
  )
    external
    returns (uint256)
  {
    advanceStageIfComplete(sellToken, buyToken);
    requireStage(sellToken, buyToken, AuctionStage.Commit);

    require(committedSellTokenAmount > 0);
    IReserve reserve = IReserve(registry.getAddressFor(RESERVE_REGISTRY_ID));
    require(
      IERC20Token(sellToken).transferFrom(
        msg.sender,
        address(reserve),
        committedSellTokenAmount
      )
    );

    if (reserve.tokens(sellToken)) {
      require(reserve.burnToken(sellToken));
    }

    UserBids storage userBid = userBids[sellToken][buyToken][msg.sender];

    uint256 bidIndex;
    if (userBid.nonce < auctions[sellToken][buyToken].nonce) {
      delete userBid.bids;
      bidIndex = 0;
      userBid.nonce = auctions[sellToken][buyToken].nonce;
    } else {
      bidIndex = userBid.bids.length;
    }

    Bid memory newBidParams;
    newBidParams.state = BidState.Committed;
    newBidParams.committedSellTokenAmount = committedSellTokenAmount;
    newBidParams.bidHash = bidHash;
    userBid.bids.push(newBidParams);

    emit Commit(sellToken, buyToken, msg.sender, userBid.nonce, committedSellTokenAmount, bidIndex);
    return bidIndex;
  }

  /**
   * @notice Allows users to reveal their sealed bids.
   * @param sellToken Address of token to be exchanged by bidder.
   * @param buyToken Address of token to be exchanged by auction.
   * @param salt The random salt used to generate the bidHash.
   * @param sellTokenAmount The amount of sellToken the bidder wishes to exchange.
   * @param buyTokenAmount The amount of buyToken the bidder wishes to exchange.
   */
  // solhint-disable-next-line
  function reveal(
    address sellToken,
    address buyToken,
    uint256 salt,
    uint256 sellTokenAmount,
    uint256 buyTokenAmount,
    uint256 bidIndex
  )
    external
  {
    advanceStageIfComplete(sellToken, buyToken);
    requireStage(sellToken, buyToken, AuctionStage.Reveal);
    AuctionParams storage auction = auctions[sellToken][buyToken];
    UserBids storage userBid = userBids[sellToken][buyToken][msg.sender];

    require(userBid.bids.length > bidIndex);
    require(userBid.nonce == auction.nonce);
    Bid storage bid = userBid.bids[bidIndex];
    require(bid.state == BidState.Committed);
    require(
      keccak256(
        abi.encodePacked(sellTokenAmount, buyTokenAmount, salt, auction.nonce)
      ) == bid.bidHash);

    require(sellTokenAmount <= bid.committedSellTokenAmount);
    bid.state = BidState.Revealed;

    bid.bidId = sortedBids[sellToken][buyToken].insert(
      sellTokenAmount,
      buyTokenAmount,
      msg.sender
    );

    emit Reveal(
      sellToken,
      buyToken,
      msg.sender,
      auction.nonce,
      sellTokenAmount,
      buyTokenAmount,
      bidIndex
    );
  }

  /**
   * @notice Allows users to fill their revealed bids.
   * @param sellToken Address of token to be exchanged by bidder.
   * @param buyToken Address of token to be exchanged by auction.
   */
  // solhint-disable-next-line
  function fill(
    address sellToken,
    address buyToken,
    uint256 bidIndex
  )
    external
    returns (uint256, uint256)
  {
    advanceStageIfComplete(sellToken, buyToken);
    requireStage(sellToken, buyToken, AuctionStage.Fill);
    AuctionParams storage auction = auctions[sellToken][buyToken];
    require(userBids[sellToken][buyToken][msg.sender].bids.length > bidIndex);
    Bid storage bid = userBids[sellToken][buyToken][msg.sender].bids[bidIndex];
    SortedBids.Bid storage bidFromTree = sortedBids[sellToken][buyToken].bids[bid.bidId];
    require(
      userBids[sellToken][buyToken][msg.sender].nonce == auction.nonce &&
      bid.state == BidState.Revealed
    );

    // The amount of sellToken to be paid by the bidder to the auction.
    uint256 fillSellTokenAmount = 0;
    // The amount of buyToken to be paid by the auction to the bidder.
    uint256 fillBuyTokenAmount = 0;

    uint256 cappedTokenAmountAtHigherRates =
      sortedBids[sellToken][buyToken].totalFromHigherExchangeRates(bid.bidId);

    // TODO(asa): All bids will either be filled completely or not at all except for one.
    // For those bids, this logic can be simpler.
    if (cappedTokenAmountAtHigherRates <= auction.cap) {
      if (auction.cappedToken == sellToken) {
        fillSellTokenAmount = Math.min256(
          bidFromTree.sellTokenAmount,
          auction.cap.sub(cappedTokenAmountAtHigherRates)
        );

        fillBuyTokenAmount = fillSellTokenAmount.getPartialAmount(
          bidFromTree.buyTokenAmount,
          bidFromTree.sellTokenAmount
        );
      } else {
        fillBuyTokenAmount = Math.min256(
          bidFromTree.buyTokenAmount,
          auction.cap.sub(cappedTokenAmountAtHigherRates)
        );

        fillSellTokenAmount = fillBuyTokenAmount.getPartialAmount(
          bidFromTree.sellTokenAmount,
          bidFromTree.buyTokenAmount
        );
      }
    }

    bid.state = BidState.Filled;

    incrementPendingWithdrawals(
      sellToken,
      msg.sender,
      bid.committedSellTokenAmount.sub(fillSellTokenAmount)
    );
    incrementPendingWithdrawals(buyToken, msg.sender, fillBuyTokenAmount);
    emit Fill(
      sellToken,
      buyToken,
      msg.sender,
      auction.nonce,
      fillSellTokenAmount,
      fillBuyTokenAmount,
      bidIndex
    );
    return (fillSellTokenAmount, fillBuyTokenAmount);
  }

  /**
   * @notice Allows users to withdraw sellToken/buyToken from filled bids.
   * @param token Address of token to withdraw.
   */
  function withdraw(address token) external returns (uint256) {
    uint256 amount = pendingWithdrawals[token][msg.sender];
    require(amount > 0);
    IReserve reserve = IReserve(registry.getAddressFor(RESERVE_REGISTRY_ID));
    require(reserve.tokens(token) || token == registry.getAddressFor(GOLD_TOKEN_REGISTRY_ID));

    pendingWithdrawals[token][msg.sender] = 0;
    if (reserve.tokens(token)) {
      require(reserve.mintToken(msg.sender, token, amount));
    } else {
      require(reserve.transferGold(msg.sender, amount));
    }
    emit Withdrawal(token, msg.sender, amount);
    return amount;
  }

  /**
   * @notice Gets the number of bids committed to by 'user' in the most recent auction for a token
   * pair.
   */
  function getNumBids(
    address sellToken,
    address buyToken,
    address user
  )
    external
    view
    returns (uint256)
  {
    UserBids storage bids = userBids[sellToken][buyToken][user];
    AuctionParams storage auction = auctions[sellToken][buyToken];
    if (bids.nonce == auction.nonce) {
      return bids.bids.length;
    } else {
      return 0;
    }
  }

  function getBidParams(
    address sellToken,
    address buyToken,
    address user,
    uint256 bidIndex
  )
    external
    view
    returns (
      uint256,
      uint64,
      bytes32,
      uint256
    )
  {
    Bid storage bid = userBids[sellToken][buyToken][user].bids[bidIndex];
    return (
      uint256(bid.state),
      bid.bidId,
      bid.bidHash,
      bid.committedSellTokenAmount
    );
  }

  /**
   * @notice Returns the current stage of the auction
   * @param sellToken Address of token to be exchanged by bidders.
   * @param buyToken Address of token to be exchanged by auction.
   */
  function getStage(address sellToken, address buyToken) public view returns (AuctionStage) {
    AuctionParams storage auction = auctions[sellToken][buyToken];
    // TODO(asa): Rework this function for gas optimization, as all conditionals will be evaluated
    // in almost all calls to this function.
    // solhint-disable not-rely-on-time
    if (auction.stage == AuctionStage.Reset) {
      return auction.stage;
    } else if (
      now >= stageStartTime(auction.startTime, auction.stageDuration, AuctionStage.Ended)
    ) {
      return AuctionStage.Ended;
    } else if (now >= stageStartTime(auction.startTime, auction.stageDuration, AuctionStage.Fill)) {
      return AuctionStage.Fill;
    } else if (
      now >= stageStartTime(auction.startTime, auction.stageDuration, AuctionStage.Reveal)
    ) {
      return AuctionStage.Reveal;
    } else {
      return auction.stage;
    }
    // solhint-enable not-rely-on-time
  }

  /**
   * @notice Returns the auction parameters.
   * @param sellToken Address of token to be exchanged by bidders.
   * @param buyToken Address of token to be exchanged by auction.
   * @return The unpacked AuctionParams struct.
   */
  function getAuctionParams(
    address sellToken,
    address buyToken
  )
    public
    view
    returns (AuctionStage, address, uint256, uint256, uint256, uint256)
  {
    AuctionParams storage auction = auctions[sellToken][buyToken];
    return (
      getStage(sellToken, buyToken),
      auction.cappedToken,
      auction.cap,
      auction.stageDuration,
      auction.startTime,
      auction.nonce
    );
  }

  /*
   * Internal functions
   */
  /**
   * @notice Throws if the auction is not in a particular stage.
   * @dev Should be used as a modifier, needs to be a function to stay under EVM stack depth limit.
   * @param sellToken Address of token to be exchanged by bidders.
   * @param buyToken Address of token to be exchanged by auction.
   */
  function requireStage(
    address sellToken,
    address buyToken,
    AuctionStage stage
  )
    internal
    view
  {
    require(auctions[sellToken][buyToken].stage == stage, "Incorrect stage.");
  }

  /**
   * @notice Returns the start time of a particular auction stage
   * @param auctionStartTime The start time of the auction in seconds since epoch.
   * @param auctionStageDuration The duration of each auction stage in seconds.
   * @param stage The stage of the auction for which the start time will be returned.
   * @return The start time of 'stage' in seconds since epoch.
   */
  function stageStartTime(
    uint256 auctionStartTime,
    uint256 auctionStageDuration,
    AuctionStage stage
  )
    public
    pure
    returns (uint256)
  {
    return auctionStartTime.add(auctionStageDuration.mul(uint256(stage).sub(1)));
  }

  /**
   * @notice Advances the auction to the next stage if current stage is over.
   * @dev Should be used as a modifier, needs to be a function to stay under EVM stack depth limit.
   * @param sellToken Address of token to be exchanged by bidders.
   * @param sellToken Address of token to be exchanged by bidders.
   * @param buyToken Address of token to be exchanged by auction.
   */
  function advanceStageIfComplete(
    address sellToken,
    address buyToken
  )
    internal
  {
    AuctionParams storage auction = auctions[sellToken][buyToken];
    AuctionStage currentStage = getStage(sellToken, buyToken);
    if (auction.stage != currentStage) {
      auction.stage = currentStage;
      emit AuctionStageChanged(sellToken, buyToken, auction.nonce, auction.stage);
    }
  }

  /**
   * @notice Increments an account's pendingWithdrawals for a token by 'value'.
   * @param token The token for which pendingWithdrawals should be incremented.
   * @param account The account for which pendingWithdrawals should be incremented.
   * @param value The value by which pendingWithdrawals should be incremented.
   */
  function incrementPendingWithdrawals(
    address token,
    address account,
    uint256 value
  )
    internal
  {
    pendingWithdrawals[token][account] = pendingWithdrawals[token][account].add(
      value
    );
  }
}
