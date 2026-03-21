// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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

    uint256 public constant FEE = 100;              // 1%
    uint256 public constant FEE_DENOM = 10000;
    uint256 public constant TARGET_RAISE = 12_000 * 1e6;  // 12,000 USDC (6 decimals)
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 1e18; // 1B tokens

    // 初始市值 $4000, 毕业市值 $65000
    // price = A + B * tokensSold^2
    // A = 4000e6 / 1B = 4e-3 * 1e6 / 1e9 => 用整数: 初始价格 = 4000 * 1e6 / 1e9 = 4 (单位: 1e-6 USDC per 1e-18 token)
    // 实际: price in (USDC_units * 1e18 / token_units)
    // 初始: 4000 USDC / 1B tokens = 4e-6 USDC/token = 4 (in 1e-6 units)
    // 毕业: 65000 USDC / 800M tokens ≈ 8.125e-5 USDC/token
    // 用 tokensSold 驱动曲线，单位换算后:
    // price(sold) = INIT_PRICE + SLOPE * sold / TOTAL_SUPPLY
    // INIT_PRICE = 4 (1e-6 USDC per token, 即 price * 1e12 = wei per token)
    // 存储单位: price 以 "USDC_6 per token_18" 表示，即 price * 1e18 = USDC(6dec) per token

    // 简化: price (USDC 6dec) per 1e18 tokens
    // 初始价格: 4000 USDC / 1B = 4e-6 USDC/token => per 1e18 tokens = 4e-6 * 1e18 = 4e12 (USDC 6dec units)
    // 但 USDC 6dec: 1 USDC = 1e6, so price = 4e-6 USDC = 4e-6 * 1e6 = 4 (USDC 6dec units) per token
    // price per token (USDC 6dec) = 4 at start
    // 以 tokensSold (1e18 units) 驱动:
    // price = 4 + slope * sold^2 / TOTAL^2
    // 毕业时 sold ≈ 800M*1e18, price ≈ 81 (65000/800M * 1e6)
    // slope = (81 - 4) * TOTAL^2 / sold^2 ≈ 77 * (1B)^2 / (800M)^2 ≈ 120

    uint256 public constant INIT_PRICE = 4;    // 4e-6 USDC per token (USDC 6dec per token 18dec)
    uint256 public constant PRICE_SLOPE = 120; // 曲线斜率

    struct Launch {
        address token;
        address creator;
        uint256 raised;       // 净募集 USDC (6 decimals)
        uint256 tokensSold;   // 已卖出代币数量 (18 decimals)
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

    // 当前价格: USDC(6dec) per token(18dec)
    function getPrice(address tokenAddr) public view returns (uint256) {
        uint256 sold = launches[tokenAddr].tokensSold;
        // price = INIT_PRICE + PRICE_SLOPE * (sold/TOTAL_SUPPLY)^2
        uint256 ratio = (sold * 1e9) / TOTAL_SUPPLY; // ratio in 1e9 units (0~1e9)
        return INIT_PRICE + (PRICE_SLOPE * ratio * ratio) / 1e18;
    }

    // 积分计算: 买入 usdcAmount(6dec) 能得到多少代币
    // 用简单近似: 按当前价格计算 (足够准确)
    function _calcTokensOut(address tokenAddr, uint256 usdcAfterFee) internal view returns (uint256) {
        uint256 price = getPrice(tokenAddr);
        if (price == 0) price = INIT_PRICE;
        // tokensOut = usdcAfterFee / price (注意单位)
        // usdcAfterFee: 6dec, price: 6dec per token(18dec)
        // tokensOut(18dec) = usdcAfterFee(6dec) * 1e18 / price(6dec per token18dec)
        return (usdcAfterFee * 1e18) / price;
    }

    // 买入
    function buy(address tokenAddr, uint256 usdcAmount) external nonReentrant {
        require(isLaunch[tokenAddr], "Invalid launch");
        Launch storage l = launches[tokenAddr];

        uint256 fee = (usdcAmount * FEE) / FEE_DENOM;
        uint256 afterFee = usdcAmount - fee;

        require(USDC.transferFrom(msg.sender, address(this), usdcAmount), "USDC transfer failed");

        uint256 tokensOut = _calcTokensOut(tokenAddr, afterFee);
        require(tokensOut > 0, "Too small");

        require(TempoMemeToken(tokenAddr).transfer(msg.sender, tokensOut), "Token transfer failed");

        l.raised += afterFee;
        l.tokensSold += tokensOut;

        emit TokenBought(tokenAddr, msg.sender, usdcAmount, tokensOut);

        if (l.raised >= TARGET_RAISE && !l.graduated) {
            l.graduated = true;
            emit LaunchGraduated(tokenAddr);
        }
    }

    // 卖出
    function sell(address tokenAddr, uint256 tokenAmount) external nonReentrant {
        require(isLaunch[tokenAddr], "Invalid launch");
        Launch storage l = launches[tokenAddr];
        require(l.raised > 0, "No liquidity");

        uint256 price = getPrice(tokenAddr);
        // usdcBack(6dec) = tokenAmount(18dec) * price(6dec per token18dec) / 1e18
        uint256 usdcBack = (tokenAmount * price) / 1e18;
        uint256 fee = (usdcBack * FEE) / FEE_DENOM;
        uint256 usdcOut = usdcBack - fee;

        require(usdcOut > 0, "Too small");
        require(usdcOut <= l.raised, "Insufficient liquidity");

        require(TempoMemeToken(tokenAddr).transferFrom(msg.sender, address(this), tokenAmount), "Token transfer failed");
        require(USDC.transfer(msg.sender, usdcOut), "USDC transfer failed");

        l.raised -= usdcOut;
        if (l.tokensSold >= tokenAmount) l.tokensSold -= tokenAmount;

        emit TokenSold(tokenAddr, msg.sender, tokenAmount, usdcOut);
    }

    // 预估买入
    function estimateBuy(address tokenAddr, uint256 usdcAmount) external view returns (uint256 tokensOut, uint256 fee) {
        fee = (usdcAmount * FEE) / FEE_DENOM;
        tokensOut = _calcTokensOut(tokenAddr, usdcAmount - fee);
    }

    // 预估卖出
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
