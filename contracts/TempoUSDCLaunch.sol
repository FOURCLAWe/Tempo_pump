// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ===== 内联 ReentrancyGuard =====
abstract contract ReentrancyGuard {
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;
    uint256 private _status;
    constructor() { _status = NOT_ENTERED; }
    modifier nonReentrant() {
        require(_status != ENTERED, "ReentrancyGuard: reentrant call");
        _status = ENTERED;
        _;
        _status = NOT_ENTERED;
    }
}

// ===== 内联 Ownable =====
abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }
    modifier onlyOwner() {
        require(_owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }
    function owner() public view returns (address) { return _owner; }
}

// ===== 内联 ERC20 =====
interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

contract TempoMemeToken {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
        totalSupply = 1_000_000_000 * 10**18;
        balanceOf[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

contract TempoUSDCLaunch is Ownable, ReentrancyGuard {

    IERC20 public immutable USDC;

    uint256 public constant FEE = 100;
    uint256 public constant FEE_DENOM = 10000;
    uint256 public constant TARGET_RAISE = 12_000 * 1e6;
    uint256 public constant INITIAL_PRICE = 1e12;

    struct Launch {
        address token;
        address creator;
        uint256 raised;
        bool graduated;
    }

    mapping(address => Launch) public launches;
    mapping(address => bool) public isLaunch;
    address[] public allLaunches;

    event LaunchCreated(address indexed token, address indexed creator, string name);
    event TokenBought(address indexed token, address indexed buyer, uint256 usdcIn, uint256 tokensOut);
    event LaunchGraduated(address indexed token);

    constructor(address _usdc) {
        USDC = IERC20(_usdc);
    }

    function createLaunch(string memory _name, string memory _symbol) external returns (address) {
        TempoMemeToken token = new TempoMemeToken(_name, _symbol);
        address tokenAddr = address(token);

        launches[tokenAddr] = Launch({
            token: tokenAddr,
            creator: msg.sender,
            raised: 0,
            graduated: false
        });

        isLaunch[tokenAddr] = true;
        allLaunches.push(tokenAddr);

        emit LaunchCreated(tokenAddr, msg.sender, _name);
        return tokenAddr;
    }

    function buy(address tokenAddr, uint256 usdcAmount) external nonReentrant {
        require(isLaunch[tokenAddr], "Invalid launch");
        Launch storage l = launches[tokenAddr];
        require(!l.graduated, "Already graduated");

        uint256 fee = (usdcAmount * FEE) / FEE_DENOM;
        uint256 afterFee = usdcAmount - fee;

        require(USDC.transferFrom(msg.sender, address(this), usdcAmount), "USDC transfer failed");

        uint256 price = getPrice(tokenAddr);
        uint256 tokensOut = (afterFee * 1e18) / price;

        require(TempoMemeToken(tokenAddr).transfer(msg.sender, tokensOut), "Token transfer failed");
        l.raised += afterFee;

        emit TokenBought(tokenAddr, msg.sender, usdcAmount, tokensOut);

        if (l.raised >= TARGET_RAISE) {
            l.graduated = true;
            emit LaunchGraduated(tokenAddr);
        }
    }

    function getPrice(address tokenAddr) public view returns (uint256) {
        uint256 raised = launches[tokenAddr].raised;
        if (raised == 0) return INITIAL_PRICE;
        uint256 progress = (raised * 1e18) / TARGET_RAISE;
        return INITIAL_PRICE + (progress * progress) / 7e10;
    }

    function getLaunchCount() external view returns (uint256) {
        return allLaunches.length;
    }

    function withdrawFees() external onlyOwner {
        USDC.transfer(owner(), USDC.balanceOf(address(this)));
    }
}
