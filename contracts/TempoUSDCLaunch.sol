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

    uint256 constant FEE = 100;
    uint256 constant FEE_D = 10000;
    uint256 constant TARGET = 12_000 * 1e6;
    uint256 constant SUPPLY = 1_000_000_000 * 1e18;
    uint256 constant INIT_P = 4;
    uint256 constant SLOPE = 120;

    struct Launch {
        address creator;
        uint256 raised;
        uint256 sold;
        bool graduated;
    }
    mapping(address => Launch) public launches;
    mapping(address => bool) public isLaunch;
    address[] public allLaunches;

    event LaunchCreated(address indexed token, address indexed creator, string name, string symbol);
    event TokenBought(address indexed token, address indexed buyer, uint256 usdcIn, uint256 tokensOut);
    event TokenSold(address indexed token, address indexed seller, uint256 tokensIn, uint256 usdcOut);
    event Graduated(address indexed token);

    modifier nonReentrant() { require(!_lock); _lock = true; _; _lock = false; }
    modifier onlyOwner() { require(msg.sender == owner); _; }

    constructor(address _usdc) { USDC = IERC20(_usdc); owner = msg.sender; }

    function createLaunch(string calldata _name, string calldata _symbol) external returns (address) {
        TempoMemeToken token = new TempoMemeToken(_name, _symbol, address(this));
        address a = address(token);
        launches[a] = Launch(msg.sender, 0, 0, false);
        isLaunch[a] = true;
        allLaunches.push(a);
        emit LaunchCreated(a, msg.sender, _name, _symbol);
        return a;
    }

    function getPrice(address t) public view returns (uint256) {
        uint256 r = (launches[t].sold * 1e9) / SUPPLY;
        return INIT_P + (SLOPE * r * r) / 1e18;
    }

    function buy(address t, uint256 usdcAmt) external nonReentrant {
        require(isLaunch[t]);
        uint256 fee = usdcAmt * FEE / FEE_D;
        uint256 net = usdcAmt - fee;
        require(USDC.transferFrom(msg.sender, address(this), usdcAmt));
        uint256 out = net * 1e18 / getPrice(t);
        require(out > 0);
        require(TempoMemeToken(t).transfer(msg.sender, out));
        launches[t].raised += net;
        launches[t].sold += out;
        totalFees += fee;
        emit TokenBought(t, msg.sender, usdcAmt, out);
        if (launches[t].raised >= TARGET && !launches[t].graduated) {
            launches[t].graduated = true;
            emit Graduated(t);
        }
    }

    function sell(address t, uint256 tokenAmt) external nonReentrant {
        require(isLaunch[t]);
        Launch storage l = launches[t];
        require(l.raised > 0);
        uint256 back = tokenAmt * getPrice(t) / 1e18;
        uint256 fee = back * FEE / FEE_D;
        uint256 out = back - fee;
        require(out > 0 && out <= l.raised);
        require(TempoMemeToken(t).transferFrom(msg.sender, address(this), tokenAmt));
        require(USDC.transfer(msg.sender, out));
        l.raised -= out;
        if (l.sold >= tokenAmt) l.sold -= tokenAmt;
        totalFees += fee;
        emit TokenSold(t, msg.sender, tokenAmt, out);
    }

    function estimateBuy(address t, uint256 usdcAmt) external view returns (uint256 out, uint256 fee) {
        fee = usdcAmt * FEE / FEE_D;
        out = (usdcAmt - fee) * 1e18 / getPrice(t);
    }

    function estimateSell(address t, uint256 tokenAmt) external view returns (uint256 out, uint256 fee) {
        uint256 back = tokenAmt * getPrice(t) / 1e18;
        fee = back * FEE / FEE_D;
        out = back - fee;
    }

    function getLaunchCount() external view returns (uint256) { return allLaunches.length; }

    function withdrawFees() external onlyOwner {
        uint256 f = totalFees; totalFees = 0;
        require(USDC.transfer(owner, f));
    }
}
