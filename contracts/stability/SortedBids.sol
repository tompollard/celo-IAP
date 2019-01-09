pragma solidity ^0.4.24;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";

import "./FractionUtil.sol";


library SortedBids {

  using SafeMath for uint256;
  using FractionUtil for FractionUtil.Fraction;

  /*
   * The data stored in a tree node.
   * A node is considered nil if its id is 0 or the nonce is not equal to the
   * tree's nonce.
   */
  struct Bid {
    // Nonce to reuse storage.
    uint64 nonce;
    // Id of the parent node.
    uint64 parent;
    // Id of the left child.
    uint64 left;
    // Id of the right child.
    uint64 right;
    // Node color for red-black tree operations.
    bool red;
    // Amount of sell token the bidder wishes to sell.
    uint256 sellTokenAmount;
    // Amount of buy token the bidder wishes to buy.
    uint256 buyTokenAmount;
    // The bidder's address.
    address bidder;
    // The amount of capped token in the subtree rooted at this node.
    uint256 totalCapped;
  }

  /*
   * The BST storing bids.
   */
  struct Tree {
    // Nonce to reuse storage. Only bids with the same nonce as the tree they're
    // in are considered valid.
    uint64 nonce;
    // Used to allocate unique ids to each new bid.
    uint64 latestId;
    // Id of the root of the tree.
    uint64 root;
    // Is the sell token capped?
    bool sellTokenCapped;
    // The list of all bids in the tree. Maps unique ids to Bid structs.
    mapping(uint64 => Bid) bids;
  }

  /**
   * @notice Reinitializes the tree, making it empty and reusing previously used
   * storage.
   * @param tree The tree to reinitialize.
   * @param sellTokenCapped True if the sell token is capped, false if the maker
   * token is capped.
   */
  function reinitializeTree(Tree storage tree, bool sellTokenCapped) internal {
    tree.root = 0;
    tree.nonce++;
    tree.sellTokenCapped = sellTokenCapped;
    tree.latestId = 0;
  }

  /**
   * @notice Calculates the total amount of capped token in bids with a higher
   * exchange rate.
   * @param tree The tree.
   * @param bidId The id of the bid, as returned by `insert`.
   * @return The total amount of capped token held in nodes that have a
   * higher exchange rate.
   */
  function totalFromHigherExchangeRates(Tree storage tree, uint64 bidId)
    internal
    view
    returns (uint256)
  {
    require(!isNil(tree, bidId));

    uint256 total = getTotalCapped(tree, tree.bids[bidId].left);

    uint64 parent = tree.bids[bidId].parent;
    uint64 currentNode = bidId;
    while (!isNil(tree, parent)) {
      if (tree.bids[parent].right == currentNode) {
        total = total.add(getTotalCapped(tree, tree.bids[parent].left));
        total = total.add((tree.sellTokenCapped ?
                    tree.bids[parent].sellTokenAmount :
                    tree.bids[parent].buyTokenAmount));
      }

      currentNode = parent;
      parent = tree.bids[parent].parent;
    }

    return total;
  }

  /**
   * @notice Inserts bid into tree, possibly causing it to become unbalanced.
   * @param tree The tree into which we're inserting.
   * @param bid The new bid to be inserted.
   * @param bidId The id of the new bid.
   */
  function insertUnbalanced(Tree storage tree, Bid storage bid, uint64 bidId)
    internal
  {
    uint64 id = tree.root;
    uint64 parent = id;
    uint256 cappedTokenAmount = (tree.sellTokenCapped ? bid.sellTokenAmount : bid.buyTokenAmount);
    while (!isNil(tree, id)) {
      parent = id;
      tree.bids[parent].totalCapped = tree.bids[parent].totalCapped.add(
        cappedTokenAmount
      );
      if (bidGreaterThan(bid, tree.bids[id])) {
        id = tree.bids[id].left;
      } else {
        id = tree.bids[id].right;
      }
    }

    bid.parent = parent;

    if (!isNil(tree, parent)) {
      if (bidGreaterThan(bid, tree.bids[parent])) {
        tree.bids[parent].left = bidId;
      } else {
        tree.bids[parent].right = bidId;
      }
    } else {
      tree.root = bidId;
    }
  }

  function insert(
    Tree storage tree,
    uint256 sellTokenAmount,
    uint256 buyTokenAmount,
    address bidder
  )
    internal
    returns (uint64)
  {
    tree.latestId++;
    Bid storage bid = tree.bids[tree.latestId];
    bid.nonce = tree.nonce;
    bid.left = 0;
    bid.right = 0;
    bid.red = true;
    bid.sellTokenAmount = sellTokenAmount;
    bid.buyTokenAmount = buyTokenAmount;
    bid.bidder = bidder;
    bid.totalCapped = (tree.sellTokenCapped ? sellTokenAmount : buyTokenAmount);

    insertUnbalanced(tree, bid, tree.latestId);
    balance1(tree, tree.latestId);

    return tree.latestId;
  }

  function balance1(Tree storage tree, uint64 n) private {
    uint64 p = tree.bids[n].parent;
    if (isNil(tree, p)) {
      tree.bids[n].red = false;
    } else {
      if (tree.bids[p].red) {
        uint64 g = grandparent(tree, n);
        uint64 u = uncle(tree, n);
        if (!isNil(tree, u) && tree.bids[u].red) {
          tree.bids[p].red = false;
          tree.bids[u].red = false;
          tree.bids[g].red = true;
          balance1(tree, g);
        } else {
          if ((n == tree.bids[p].right) && (p == tree.bids[g].left)) {
            rotateLeft(tree, p);
            n = tree.bids[n].left;
          } else if ((n == tree.bids[p].left) && (p == tree.bids[g].right)) {
            rotateRight(tree, p);
            n = tree.bids[n].right;
          }

          balance2(tree, n);
        }
      }
    }
  }

  function balance2(Tree storage tree, uint64 n) private {
    uint64 p = tree.bids[n].parent;
    uint64 g = grandparent(tree, n);

    tree.bids[p].red = false;
    tree.bids[g].red = true;

    if ((n == tree.bids[p].left) && (p == tree.bids[g].left)) {
      rotateRight(tree, g);
    } else {
      rotateLeft(tree, g);
    }
  }

  function grandparent(Tree storage tree, uint64 n) private view returns (uint64) {
    return tree.bids[tree.bids[n].parent].parent;
  }

  function uncle(Tree storage tree, uint64 n) private view returns (uint64) {
    uint64 g = grandparent(tree, n);
    if (isNil(tree, g))
      return 0;

    if (tree.bids[n].parent == tree.bids[g].left)
      return tree.bids[g].right;
    return tree.bids[g].left;
  }

  function sibling(Tree storage tree, uint64 n) private view returns (uint64) {
    uint64 p = tree.bids[n].parent;
    if (n == tree.bids[p].left) {
      return tree.bids[p].right;
    } else {
      return tree.bids[p].left;
    }
  }

  function rotateRight(Tree storage tree, uint64 n) private {
    uint64 pivot = tree.bids[n].left;
    uint64 p = tree.bids[n].parent;
    tree.bids[pivot].parent = p;
    if (!isNil(tree, p)) {
      if (tree.bids[p].left == n) {
        tree.bids[p].left = pivot;
      } else {
        tree.bids[p].right = pivot;
      }
    } else {
      tree.root = pivot;
    }

    tree.bids[n].left = tree.bids[pivot].right;
    if (!isNil(tree, tree.bids[pivot].right)) {
      tree.bids[tree.bids[pivot].right].parent = n;
    }

    tree.bids[n].parent = pivot;
    tree.bids[pivot].right = n;

    recalculateTotalsAfterRotation(tree, n, pivot);
  }

  function rotateLeft(Tree storage tree, uint64 n) private {
    uint64 pivot = tree.bids[n].right;
    uint64 p = tree.bids[n].parent;
    tree.bids[pivot].parent = p;
    if (!isNil(tree, p)) {
      if (tree.bids[p].left == n) {
        tree.bids[p].left = pivot;
      } else {
        tree.bids[p].right = pivot;
      }
    } else {
      tree.root = pivot;
    }

    tree.bids[n].right = tree.bids[pivot].left;
    if (!isNil(tree, tree.bids[pivot].left)) {
      tree.bids[tree.bids[pivot].left].parent = n;
    }

    tree.bids[n].parent = pivot;
    tree.bids[pivot].left = n;

    recalculateTotalsAfterRotation(tree, n, pivot);
  }

  /**
   * @notice Recalculates the totalCapped value for nodes involved in a rotation
   * @param tree The tree in which the rotation took place.
   * @param n The node for which the rotation was done.
   * @param pivot The pivot in the rotation.
   */
  function recalculateTotalsAfterRotation(Tree storage tree, uint64 n, uint64 pivot) private {
    tree.bids[pivot].totalCapped = tree.bids[n].totalCapped;

    tree.bids[n].totalCapped =
      tree.bids[tree.bids[n].left].totalCapped.add(
      tree.bids[tree.bids[n].right].totalCapped
      ).add(
        (tree.sellTokenCapped ?
          tree.bids[n].sellTokenAmount :
          tree.bids[n].buyTokenAmount)
      );
  }

  function isNil(Tree storage tree, uint64 node) private view returns (bool) {
    return node == 0 || tree.nonce != tree.bids[node].nonce;
  }

  function getTotalCapped(Tree storage tree, uint64 node) private view returns (uint256) {
    if (isNil(tree, node)) {
      return 0;
    }

    return tree.bids[node].totalCapped;
  }

  /**
   * @notice The comparison function defining the order in the BST. We order by
   * decreasing ratios of sell to buy token.
   */
  function bidGreaterThan(Bid storage bid1, Bid storage bid2) private view returns (bool) {
    FractionUtil.Fraction memory value1 = FractionUtil.Fraction(
      bid1.sellTokenAmount,
      bid1.buyTokenAmount
    );
    FractionUtil.Fraction memory value2 = FractionUtil.Fraction(
      bid2.sellTokenAmount,
      bid2.buyTokenAmount
    );

    return value1.isGreaterThan(value2);
  }
}
