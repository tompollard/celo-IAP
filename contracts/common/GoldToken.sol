pragma solidity ^0.4.22;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";

import "./Initializable.sol";
import "./interfaces/IGoldToken.sol";


contract GoldToken is Initializable, IGoldToken {

  using SafeMath for uint256;

  // Address of the TRANSFER precompiled contract.
  // solhint-disable state-visibility
  address constant TRANSFER = address(0xfd);
  string constant NAME = "Celo Gold";
  string constant SYMBOL = "cGLD";
  uint8 constant DECIMALS = 18;
  // solhint-enable state-visibility

  mapping (address => mapping (address => uint256)) internal allowed;

  event Transfer(
    address indexed from,
    address indexed to,
    uint256 value
  );

  event TransferComment(
    string comment
  );

  event Approval(
    address indexed owner,
    address indexed spender,
    uint256 value
  );

  /**
   * @notice Sets 'initialized' to true.
   */
  // solhint-disable-next-line no-empty-blocks
  function initialize() external initializer {}

  /**
   * @dev Transfers Celo Gold from one address to another.
   * @param to The address to transfer Celo Gold to.
   * @param value The amount of Celo Gold to transfer.
   * @return True if the transaction succeeds.
   */
  // solhint-disable-next-line no-simple-event-func-name
  function transfer(address to, uint256 value) external returns (bool) {
    return _transfer(to, value);
  }

  /**
   * @dev Transfers Celo Gold from one address to another with a comment.
   * @param to The address to transfer Celo Gold to.
   * @param value The amount of Celo Gold to transfer.
   * @param comment The transfer comment
   * @return True if the transaction succeeds.
   */
  function transferWithComment(address to, uint256 value, string comment) external returns (bool) {
    bool succeeded = _transfer(to, value);
    emit TransferComment(comment);
    return succeeded;
  }

  /**
   * @dev Approve a user to transfer Celo Gold on behalf of another user.
   * @param spender The address which is being approved to spend Celo Gold.
   * @param value The amount of Celo Gold approved to the spender.
   * @return True if the transaction succeeds.
   */
  function approve(address spender, uint256 value) external returns (bool) {
    allowed[msg.sender][spender] = value;
    emit Approval(msg.sender, spender, value);
    return true;
  }

  /**
   * @dev Transfers Celo Gold from one address to another on behalf of a user.
   * @param from The address to transfer Celo Gold from.
   * @param to The address to transfer Celo Gold to.
   * @param value The amount of Celo Gold to transfer.
   * @return True if the transaction succeeds.
   */
  function transferFrom(address from, address to, uint256 value) external returns (bool) {
    require(to != address(0));
    require(value <= balanceOf(from));
    require(value <= allowed[from][msg.sender]);

    require(
      // solhint-disable-next-line avoid-call-value
      TRANSFER.call.value(0).gas(gasleft())(
        from, to, value
      )
    );
    allowed[from][msg.sender] = allowed[from][msg.sender].sub(value);
    emit Transfer(from, to, value);
    return true;
  }

  /**
   * @return The name of the Celo Gold token.
   */
  function name() external pure returns (string) {
    return NAME;
  }

  /**
   * @return The symbol of the Celo Gold token.
   */
  function symbol() external pure returns (string) {
    return SYMBOL;
  }

  /**
   * @return The number of decimal places to which Celo Gold is divisible.
   */
  function decimals() external pure returns (uint8) {
    return DECIMALS;
  }

  /**
   * @return The total amount of Celo Gold in existence.
   */
  // TODO(asa): Implement totalSupply
  function totalSupply() external pure returns (uint256) {
    return 0;
  }

  /**
   * @dev Gets the amount of owner's Celo Gold allowed to be spent by spender.
   * @param owner The owner of the Celo Gold.
   * @param owner The spender of the Celo Gold.
   * @return The amount of Celo Gold owner is allowing spender to spend.
   */
  function allowance(address owner, address spender) external view returns (uint256) {
    return allowed[owner][spender];
  }

  /**
   * @dev Gets the balance of the specified address.
   * @param who The address to query the balance of.
   * @return The balance of the specified address.
   */
  function balanceOf(address who) public view returns (uint256) {
    return who.balance;
  }

  /**
   * @dev internal Celo Gold transfer from one address to another.
   * @param to The address to transfer Celo Gold to.
   * @param value The amount of Celo Gold to transfer.
   * @return True if the transaction succeeds.
   */
  function _transfer(address to, uint256 value) internal returns (bool) {
    require(to != address(0));
    require(value <= balanceOf(msg.sender));

    require(
      // solhint-disable-next-line avoid-call-value
      TRANSFER.call.value(0).gas(gasleft())(
        msg.sender, to, value
      )
    );
    emit Transfer(msg.sender, to, value);
    return true;
  }
}
