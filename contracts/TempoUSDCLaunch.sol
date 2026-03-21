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
        name = _name;
        symbol = _symbol;
        balanceOf[_to] = totalSupply;
        emit Transfer(address(0), _to, totalSupply);
    }

    function transfer(address to, uint256 v) external returns (bool) {
        balanceOf[msg.sender] -= v;
        balanceOf[to] += v;
        emit Transfer(msg.sender, to, v);
        return true;
    }

    function approve(address s, uint256 v) external returns (bool) {
        allowance[msg.sender][s] = v;
        emit Approval(msg.sender, s, v);
        return true;
    }

    function transferFrom(address from, address to, uint256 v) external returns (bool) {
        allowance[from][msg.sender] -= v;
        balanceOf[from] -= v;
        balanceOf[to] += v;
        emit Transfer(from, to, v);
        return true;
    }
}

contract TempoUSDCLaunch {
    address public owner;
    IERC20 public immutable USDC;
    uint256 public totalFees;
    bool private _lock;

    uint256 constant FEE = 100;
    uint256 constant FEE_D = 10000;
    uint256 constant SALE_CAP = 800_000_000 * 1e18;
    uint256 constant WAD = 1e18;
    uint256 constant PRICE_SCALE = 1e30;
    uint256 constant INIT_P = 3e12;
    uint256 constant PRICE_DELTA = 62e12;

    struct Launch {
        address creator;
        uint256 raised;
        uint256 sold;
        bool graduated;
    }

    mapping(address => Launch) public launches;
    mapping(address => bool) public isLaunch;
    address[] public allLaunches;

    event LaunchCreated(address indexed token, address indexed creator, string name, string symbol, string meta);
    event TokenBought(address indexed token, address indexed buyer, uint256 usdcIn, uint256 tokensOut);
    event TokenSold(address indexed token, address indexed seller, uint256 tokensIn, uint256 usdcOut);
    event Graduated(address indexed token);
    event LaunchUsdcWithdrawn(address indexed token, address indexed to, uint256 amount);
    event LaunchTokensWithdrawn(address indexed token, address indexed to, uint256 amount);

    modifier nonReentrant() {
        require(!_lock);
        _lock = true;
        _;
        _lock = false;
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    modifier onlyLaunchAdmin(address t) {
        require(msg.sender == owner || msg.sender == launches[t].creator);
        _;
    }

    constructor(address _usdc) {
        USDC = IERC20(_usdc);
        owner = msg.sender;
    }

    function _createLaunch(
        string calldata _name,
        string calldata _symbol,
        string calldata _meta
    ) internal returns (address) {
        TempoMemeToken token = new TempoMemeToken(_name, _symbol, address(this));
        address t = address(token);
        launches[t] = Launch({creator: msg.sender, raised: 0, sold: 0, graduated: false});
        isLaunch[t] = true;
        allLaunches.push(t);
        emit LaunchCreated(t, msg.sender, _name, _symbol, _meta);
        return t;
    }

    function createLaunch(
        string calldata _name,
        string calldata _symbol,
        string calldata _meta
    ) external returns (address) {
        return _createLaunch(_name, _symbol, _meta);
    }

    function createToken(
        string calldata _name,
        string calldata _symbol,
        string calldata _meta
    ) external returns (address) {
        return _createLaunch(_name, _symbol, _meta);
    }

    function getPrice(address t) public view returns (uint256) {
        uint256 sold = launches[t].sold;
        if (sold > SALE_CAP) sold = SALE_CAP;
        uint256 r = (sold * WAD) / SALE_CAP;
        return INIT_P + (PRICE_DELTA * r * r) / WAD / WAD;
    }

    function buy(address t, uint256 usdcAmt) external nonReentrant {
        require(isLaunch[t]);
        Launch storage l = launches[t];
        require(!l.graduated);

        uint256 fee = usdcAmt * FEE / FEE_D;
        uint256 net = usdcAmt - fee;
        uint256 out = net * PRICE_SCALE / getPrice(t);

        require(out > 0);
        require(l.sold + out <= SALE_CAP);
        require(USDC.transferFrom(msg.sender, address(this), usdcAmt));
        require(TempoMemeToken(t).transfer(msg.sender, out));

        l.raised += net;
        l.sold += out;
        totalFees += fee;

        emit TokenBought(t, msg.sender, usdcAmt, out);

        if (l.sold >= SALE_CAP) {
            l.graduated = true;
            emit Graduated(t);
        }
    }

    function sell(address t, uint256 tokenAmt) external nonReentrant {
        require(isLaunch[t]);
        Launch storage l = launches[t];
        require(!l.graduated);
        require(l.raised > 0);

        uint256 back = tokenAmt * getPrice(t) / PRICE_SCALE;
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
        out = (usdcAmt - fee) * PRICE_SCALE / getPrice(t);
    }

    function estimateSell(address t, uint256 tokenAmt) external view returns (uint256 out, uint256 fee) {
        uint256 back = tokenAmt * getPrice(t) / PRICE_SCALE;
        fee = back * FEE / FEE_D;
        out = back - fee;
    }

    function getLaunchCount() external view returns (uint256) {
        return allLaunches.length;
    }

    function withdrawLaunchUSDC(address t, address to, uint256 amount) external onlyLaunchAdmin(t) {
        Launch storage l = launches[t];
        require(l.graduated);
        require(amount <= l.raised);
        l.raised -= amount;
        require(USDC.transfer(to, amount));
        emit LaunchUsdcWithdrawn(t, to, amount);
    }

    function withdrawLaunchTokens(address t, address to, uint256 amount) external onlyLaunchAdmin(t) {
        Launch storage l = launches[t];
        require(l.graduated);
        require(TempoMemeToken(t).transfer(to, amount));
        emit LaunchTokensWithdrawn(t, to, amount);
    }

    function withdrawFees() external onlyOwner {
        uint256 f = totalFees;
        totalFees = 0;
        require(USDC.transfer(owner, f));
    }
}
