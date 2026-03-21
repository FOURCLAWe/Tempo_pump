// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract TempoMemeToken {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    uint256 public constant totalSupply = 1_000_000_000 * 1e18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    constructor(string memory _name, string memory _symbol, address _to) {
        name = _name; symbol = _symbol;
        balanceOf[_to] = totalSupply;
        emit Transfer(address(0), _to, totalSupply);
    }
    function transfer(address to, uint256 v) external returns (bool) {
        balanceOf[msg.sender] -= v; balanceOf[to] += v;
        emit Transfer(msg.sender, to, v); return true;
    }
    function approve(address s, uint256 v) external returns (bool) {
        allowance[msg.sender][s] = v; emit Approval(msg.sender, s, v); return true;
    }
    function transferFrom(address from, address to, uint256 v) external returns (bool) {
        allowance[from][msg.sender] -= v; balanceOf[from] -= v; balanceOf[to] += v;
        emit Transfer(from, to, v); return true;
    }
}

contract TempoUSDCLaunch {
    address public owner;
    IERC20 public immutable USDC;
    uint256 public totalFees;
    bool private _lock;

    // ── 手续费 1% ──
    uint256 constant FEE     = 100;
    uint256 constant FEE_D   = 10000;

    // ── xy=k 虚拟流动性池参数 ──
    // 初始市值 $3,600 | 毕业市值 $62,500 | 募资目标 $12,000 | 售出 80%
    uint256 constant VIRTUAL_USDC  = 3_789_473_684;          // 3789.47 USDC (1e6精度)
    uint256 constant VIRTUAL_TOKEN = 1_052_631_579 * 1e18;   // 虚拟代币池 (1e18精度)
    uint256 constant TOTAL_SUPPLY  = 1_000_000_000 * 1e18;   // 实际总供应 10亿
    uint256 constant GRAD_SOLD     = 800_000_000   * 1e18;   // 毕业阈值：售出 8亿（80%）
    uint256 constant TARGET_USDC   = 12_000        * 1e6;    // 毕业募资目标 12,000 USDC
    uint256 constant DEX_RESERVE   = 200_000_000   * 1e18;   // 迁移外盘 2亿（20%）

    struct Launch {
        address creator;
        uint256 raised;      // 实际募资 USDC (1e6精度)
        uint256 sold;        // 已售出代币 (1e18精度)
        bool    graduated;
    }

    mapping(address => Launch) public launches;
    mapping(address => bool)   public isLaunch;
    address[] public allLaunches;

    event LaunchCreated(address indexed token, address indexed creator, string name, string symbol, string meta);
    event TokenBought(address indexed token, address indexed buyer, uint256 usdcIn, uint256 tokensOut);
    event TokenSold(address indexed token, address indexed seller, uint256 tokensIn, uint256 usdcOut);
    event Graduated(address indexed token, uint256 raised, uint256 dexTokens);

    modifier onlyOwner() { require(msg.sender == owner); _; }
    modifier nonReentrant() { require(!_lock); _lock = true; _; _lock = false; }

    constructor(address _usdc) {
        owner = msg.sender;
        USDC  = IERC20(_usdc);
    }

    // ── 当前价格：(VIRTUAL_USDC + raised) / (VIRTUAL_TOKEN - sold) ──
    // 返回值单位：USDC(1e6) per token(1e18)
    function getPrice(address t) public view returns (uint256) {
        Launch storage l = launches[t];
        uint256 usdcPool  = VIRTUAL_USDC + l.raised;
        uint256 tokenPool = VIRTUAL_TOKEN - l.sold;
        require(tokenPool > 0, "pool empty");
        return usdcPool * 1e18 / tokenPool;
    }

    // ── 创建代币 ──
    function createLaunch(
        string calldata name,
        string calldata symbol,
        string calldata meta
    ) external returns (address) {
        TempoMemeToken token = new TempoMemeToken(name, symbol, address(this));
        address t = address(token);
        launches[t] = Launch({ creator: msg.sender, raised: 0, sold: 0, graduated: false });
        isLaunch[t] = true;
        allLaunches.push(t);
        emit LaunchCreated(t, msg.sender, name, symbol, meta);
        return t;
    }

    function createToken(
        string calldata name,
        string calldata symbol,
        string calldata meta
    ) external returns (address) {
        TempoMemeToken token = new TempoMemeToken(name, symbol, address(this));
        address t = address(token);
        launches[t] = Launch({ creator: msg.sender, raised: 0, sold: 0, graduated: false });
        isLaunch[t] = true;
        allLaunches.push(t);
        emit LaunchCreated(t, msg.sender, name, symbol, meta);
        return t;
    }

    // ── 买入：输入 USDC，获得代币 ──
    // xy=k: token_out = token_pool - k/(usdc_pool + net)
    function buy(address t, uint256 usdcAmt) external nonReentrant {
        require(isLaunch[t], "not a launch");
        Launch storage l = launches[t];
        require(!l.graduated, "graduated");

        uint256 fee = usdcAmt * FEE / FEE_D;
        uint256 net = usdcAmt - fee;
        require(net > 0, "too small");

        // xy=k 计算
        uint256 usdcPool  = VIRTUAL_USDC + l.raised;
        uint256 tokenPool = VIRTUAL_TOKEN - l.sold;
        uint256 k         = usdcPool * tokenPool;  // 注意：大数，需防溢出
        uint256 newUsdcPool  = usdcPool + net;
        uint256 newTokenPool = k / newUsdcPool;
        uint256 tokensOut    = tokenPool - newTokenPool;

        require(tokensOut > 0, "zero out");
        require(l.sold + tokensOut <= GRAD_SOLD, "exceeds curve cap");

        // 转入 USDC
        require(USDC.transferFrom(msg.sender, address(this), usdcAmt), "usdc transfer failed");
        // 转出代币
        require(TempoMemeToken(t).transfer(msg.sender, tokensOut), "token transfer failed");

        l.raised += net;
        l.sold   += tokensOut;
        totalFees += fee;

        emit TokenBought(t, msg.sender, usdcAmt, tokensOut);

        // 毕业检查
        if (l.sold >= GRAD_SOLD && !l.graduated) {
            l.graduated = true;
            emit Graduated(t, l.raised, DEX_RESERVE);
        }
    }

    // ── 卖出：输入代币，获得 USDC ──
    // xy=k: usdc_out = usdc_pool - k/(token_pool + tokens_in)
    function sell(address t, uint256 tokenAmt) external nonReentrant {
        require(isLaunch[t], "not a launch");
        Launch storage l = launches[t];
        require(!l.graduated, "graduated");
        require(l.raised > 0, "no liquidity");

        uint256 usdcPool  = VIRTUAL_USDC + l.raised;
        uint256 tokenPool = VIRTUAL_TOKEN - l.sold;
        uint256 k         = usdcPool * tokenPool;
        uint256 newTokenPool = tokenPool + tokenAmt;
        uint256 newUsdcPool  = k / newTokenPool;
        uint256 usdcBack     = usdcPool - newUsdcPool;

        uint256 fee = usdcBack * FEE / FEE_D;
        uint256 out = usdcBack - fee;

        require(out > 0, "zero out");
        require(out <= l.raised, "insufficient pool");

        // 转入代币
        require(TempoMemeToken(t).transferFrom(msg.sender, address(this), tokenAmt), "token transfer failed");
        // 转出 USDC
        require(USDC.transfer(msg.sender, out), "usdc transfer failed");

        l.raised -= out;
        l.sold   -= tokenAmt;
        totalFees += fee;

        emit TokenSold(t, msg.sender, tokenAmt, out);
    }

    // ── 预估买入 ──
    function estimateBuy(address t, uint256 usdcAmt) external view returns (uint256 tokensOut, uint256 fee) {
        Launch storage l = launches[t];
        fee = usdcAmt * FEE / FEE_D;
        uint256 net = usdcAmt - fee;
        uint256 usdcPool  = VIRTUAL_USDC + l.raised;
        uint256 tokenPool = VIRTUAL_TOKEN - l.sold;
        uint256 k         = usdcPool * tokenPool;
        uint256 newUsdcPool  = usdcPool + net;
        uint256 newTokenPool = k / newUsdcPool;
        tokensOut = tokenPool - newTokenPool;
    }

    // ── 预估卖出 ──
    function estimateSell(address t, uint256 tokenAmt) external view returns (uint256 usdcOut, uint256 fee) {
        Launch storage l = launches[t];
        uint256 usdcPool  = VIRTUAL_USDC + l.raised;
        uint256 tokenPool = VIRTUAL_TOKEN - l.sold;
        uint256 k         = usdcPool * tokenPool;
        uint256 newTokenPool = tokenPool + tokenAmt;
        uint256 newUsdcPool  = k / newTokenPool;
        uint256 usdcBack     = usdcPool - newUsdcPool;
        fee    = usdcBack * FEE / FEE_D;
        usdcOut = usdcBack - fee;
    }

    // ── 查询 ──
    function getLaunchCount() external view returns (uint256) { return allLaunches.length; }

    function getLaunchInfo(address t) external view returns (
        address creator,
        uint256 raised,
        uint256 sold,
        bool graduated,
        uint256 price,
        uint256 progress  // 售出进度 bps (10000 = 100%)
    ) {
        Launch storage l = launches[t];
        creator    = l.creator;
        raised     = l.raised;
        sold       = l.sold;
        graduated  = l.graduated;
        price      = getPrice(t);
        progress   = l.sold * 10000 / GRAD_SOLD;
    }

    // ── 提取手续费 ──
    function withdrawFees() external onlyOwner {
        uint256 f = totalFees;
        totalFees = 0;
        require(USDC.transfer(owner, f), "transfer failed");
    }

    // ── 毕业后提取剩余代币（迁移外盘用）──
    function withdrawGraduatedTokens(address t, address to) external onlyOwner {
        require(isLaunch[t], "not a launch");
        require(launches[t].graduated, "not graduated");
        uint256 bal = TempoMemeToken(t).balanceOf(address(this));
        require(bal > 0, "no tokens");
        require(TempoMemeToken(t).transfer(to, bal), "transfer failed");
    }

    // ── 毕业后提取募资 USDC（迁移外盘用）──
    function withdrawGraduatedUSDC(address t, address to) external onlyOwner {
        require(isLaunch[t], "not a launch");
        require(launches[t].graduated, "not graduated");
        uint256 raised = launches[t].raised;
        require(raised > 0, "no usdc");
        launches[t].raised = 0;
        require(USDC.transfer(to, raised), "transfer failed");
    }

    // ── 转移 owner ──
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0));
        owner = newOwner;
    }
}
