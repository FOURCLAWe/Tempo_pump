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

    uint256 public constant FEE = 100;            // 1%
    uint256 public constant FEE_DENOM = 10000;
    uint256 public constant TARGET_RAISE = 12_000 * 1e6; // 12,000 USDC
    uint256 public constant INITIAL_PRICE = 1e12;

    struct Launch {
        address token;
        address creator;
        uint256 raised;       // 净募集 USDC
        uint256 tokensSold;   // 已卖出代币数量
        bool graduated;
    }

    mapping(address => Launch) public launches;
    mapping(address => bool) public isLaunch;
    address[] public allLaunches;

    event LaunchCreated(address indexed token, address indexed creator, string name);
    event TokenBought(address indexed token, address indexed buyer, uint256 usdcIn, uint256 tokensOut);
    event TokenSold(address indexed token, address indexed seller, uint256 tokensIn, uint256 usdcOut);
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
            tokensSold: 0,
            graduated: false
        });

        isLaunch[tokenAddr] = true;
        allLaunches.push(tokenAddr);

        emit LaunchCreated(tokenAddr, msg.sender, _name);
        return tokenAddr;
    }

    // ===== 买入 =====
    function buy(address tokenAddr, uint256 usdcAmount) external nonReentrant {
        require(isLaunch[tokenAddr], "Invalid launch");
        Launch storage l = launches[tokenAddr];

        uint256 fee = (usdcAmount * FEE) / FEE_DENOM;
        uint256 afterFee = usdcAmount - fee;

        require(USDC.transferFrom(msg.sender, address(this), usdcAmount), "USDC transfer failed");

        uint256 price = getPrice(tokenAddr);
        uint256 tokensOut = (afterFee * 1e18) / price;

        require(TempoMemeToken(tokenAddr).transfer(msg.sender, tokensOut), "Token transfer failed");

        l.raised += afterFee;
        l.tokensSold += tokensOut;

        emit TokenBought(tokenAddr, msg.sender, usdcAmount, tokensOut);

        if (l.raised >= TARGET_RAISE && !l.graduated) {
            l.graduated = true;
            emit LaunchGraduated(tokenAddr);
        }
    }

    // ===== 卖出 =====
    function sell(address tokenAddr, uint256 tokenAmount) external nonReentrant {
        require(isLaunch[tokenAddr], "Invalid launch");
        Launch storage l = launches[tokenAddr];
        require(l.raised > 0, "No liquidity");

        // 按当前曲线价格计算返还 USDC
        uint256 price = getPrice(tokenAddr);
        uint256 usdcBack = (tokenAmount * price) / 1e18;

        // 收取 1% 手续费
        uint256 fee = (usdcBack * FEE) / FEE_DENOM;
        uint256 usdcOut = usdcBack - fee;

        require(usdcOut <= l.raised, "Insufficient liquidity");

        // 用户转入代币，合约转出 USDC
        require(TempoMemeToken(tokenAddr).transferFrom(msg.sender, address(this), tokenAmount), "Token transfer failed");
        require(USDC.transfer(msg.sender, usdcOut), "USDC transfer failed");

        l.raised -= usdcOut;
        l.tokensSold -= tokenAmount;

        emit TokenSold(tokenAddr, msg.sender, tokenAmount, usdcOut);
    }

    // ===== 曲线价格 =====
    function getPrice(address tokenAddr) public view returns (uint256) {
        uint256 raised = launches[tokenAddr].raised;
        if (raised == 0) return INITIAL_PRICE;
        uint256 progress = (raised * 1e18) / TARGET_RAISE;
        return INITIAL_PRICE + (progress * progress) / 7e10;
    }

    // ===== 预估买入 =====
    function estimateBuy(address tokenAddr, uint256 usdcAmount) external view returns (uint256 tokensOut, uint256 fee) {
        fee = (usdcAmount * FEE) / FEE_DENOM;
        uint256 afterFee = usdcAmount - fee;
        uint256 price = getPrice(tokenAddr);
        tokensOut = (afterFee * 1e18) / price;
    }

    // ===== 预估卖出 =====
    function estimateSell(address tokenAddr, uint256 tokenAmount) external view returns (uint256 usdcOut, uint256 fee) {
        uint256 price = getPrice(tokenAddr);
        uint256 usdcBack = (tokenAmount * price) / 1e18;
        fee = (usdcBack * FEE) / FEE_DENOM;
        usdcOut = usdcBack - fee;
    }

    function getLaunchCount() external view returns (uint256) {
        return allLaunches.length;
    }

    function withdrawFees() external onlyOwner {
        // 只提取手续费部分，不动流动性
        uint256 totalRaised = 0;
        for (uint256 i = 0; i < allLaunches.length; i++) {
            totalRaised += launches[allLaunches[i]].raised;
        }
        uint256 balance = USDC.balanceOf(address(this));
        if (balance > totalRaised) {
            USDC.transfer(owner(), balance - totalRaised);
        }
    }
}
